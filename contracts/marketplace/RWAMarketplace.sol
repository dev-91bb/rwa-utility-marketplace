// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IRWACertificate {
    function mint(
        address to,
        string calldata uri,
        string calldata assetType,
        string calldata serialNumber,
        address vendor,
        uint256 purchasePrice
    ) external returns (uint256);

    function getAsset(uint256 tokenId) external view returns (
        string memory assetType,
        string memory serialNumber,
        address vendor,
        uint256 purchasePrice,
        uint256 purchaseTime,
        uint8 status,
        uint256 statusUpdatedAt,
        uint256 redemptionFee
    );
}

interface IRWAStaking {
    function isStaking(address user) external view returns (bool);
    function notifyRewardAmount(uint256 amount) external;
}

interface IPriceFeed {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

/**
 * @title RWAMarketplace
 * @notice Multi-asset marketplace: direct sale + rental with promo/discount and revenue sharing
 */
contract RWAMarketplace is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error OnlyProxyAdmin();
    error InvalidListing();
    error NotSeller();
    error ListingNotActive();
    error StalePrice();
    error NotRental();
    error RentalNotActive();
    error NotTenant();
    error InvalidCategory();
    error SelfBuy();
    error FeeTooHigh();

    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR_ROLE");
    bytes32 public constant PROMO_ROLE = keccak256("PROMO_ROLE");

    enum AssetCategory { DIRECT_SALE, RENTAL }

    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 price;
        AssetCategory category;
        bool active;
    }

    struct RentalInfo {
        address tenant;
        uint256 rentAmount;     // per-period rent in $TOKEN
        uint256 lastPaidAt;
        bool active;
    }

    address private immutable _proxyAdmin;

    IERC20 public paymentToken;
    IRWACertificate public certificate;
    IRWAStaking public stakingContract;
    address public marketingWallet;

    uint256 public primaryFeeBps;    // 5% = 500
    uint256 public secondaryFeeBps;  // 3% = 300
    uint256 public rentalShareBps;   // 90% = 9000 → to staking pool
    uint256 public royaltyBps;       // e.g. 200 = 2%
    uint256 public constant BPS = 10000;
    uint256 public constant PRICE_STALENESS = 1 hours;

    // --- Promo/Discount ---
    bool public isPromotionActive;
    uint256 public discountBps; // e.g. 500 = 5%
    mapping(uint256 => bool) public promoEligibleItems; // tokenId => eligible

    // --- Listings & Rentals ---
    mapping(string => IPriceFeed) public priceFeeds;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => RentalInfo) public rentals; // listingId => rental
    uint256 private _listingIdCounter;

    event ItemPurchased(uint256 indexed tokenId, address indexed buyer, address indexed vendor, uint256 price);
    event ItemListed(uint256 indexed listingId, uint256 indexed tokenId, address indexed seller, uint256 price, AssetCategory category);
    event ItemDelisted(uint256 indexed listingId);
    event ItemSold(uint256 indexed listingId, uint256 indexed tokenId, address indexed buyer, uint256 price);
    event RentPaid(uint256 indexed listingId, address indexed tenant, uint256 amount, uint256 toStaking);
    event RentalStarted(uint256 indexed listingId, address indexed tenant, uint256 rentAmount);
    event RentalEnded(uint256 indexed listingId);
    event PriceFeedUpdated(string assetType, address feed);
    event PromotionToggled(bool active);
    event DiscountUpdated(uint256 bps);
    event PromoItemSet(uint256 indexed tokenId, bool eligible);
    event TokensRescued(address indexed token, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    function initialize(
        address paymentToken_,
        address certificate_,
        address stakingContract_,
        address marketingWallet_,
        address admin_,
        uint256 primaryFeeBps_,
        uint256 secondaryFeeBps_
    ) external initializer {
        if (paymentToken_ == address(0) || certificate_ == address(0) ||
            stakingContract_ == address(0) || marketingWallet_ == address(0) ||
            admin_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PROMO_ROLE, admin_);

        paymentToken = IERC20(paymentToken_);
        certificate = IRWACertificate(certificate_);
        stakingContract = IRWAStaking(stakingContract_);
        marketingWallet = marketingWallet_;
        primaryFeeBps = primaryFeeBps_;
        secondaryFeeBps = secondaryFeeBps_;
        rentalShareBps = 9000; // 90% to staking
        royaltyBps = 200;     // 2% royalty
    }

    // ============ Primary Market ============

    function purchaseItem(
        string calldata assetType,
        string calldata serialNumber,
        string calldata uri,
        address vendor,
        uint256 usdPrice
    ) external nonReentrant whenNotPaused {
        if (!hasRole(VENDOR_ROLE, vendor)) revert InvalidListing();

        uint256 tokenPrice = getTokenPrice(assetType, usdPrice);
        tokenPrice = _getEffectivePricePrimary(tokenPrice);
        _collectPrimaryFees(msg.sender, vendor, tokenPrice);

        uint256 tokenId = certificate.mint(msg.sender, uri, assetType, serialNumber, vendor, tokenPrice);

        emit ItemPurchased(tokenId, msg.sender, vendor, tokenPrice);
    }

    function _collectPrimaryFees(address buyer, address vendor, uint256 tokenPrice) internal {
        uint256 fee = (tokenPrice * primaryFeeBps) / BPS;
        paymentToken.safeTransferFrom(buyer, vendor, tokenPrice - fee);
        paymentToken.safeTransferFrom(buyer, marketingWallet, fee);
    }

    // ============ Secondary Market (P2P) ============

    function listItem(uint256 tokenId, uint256 price, AssetCategory category) external nonReentrant whenNotPaused {
        if (price == 0) revert ZeroAmount();

        IERC721(address(certificate)).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = ++_listingIdCounter;
        listings[listingId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            price: price,
            category: category,
            active: true
        });

        emit ItemListed(listingId, tokenId, msg.sender, price, category);
    }

    function delistItem(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.active) revert ListingNotActive();
        if (rentals[listingId].active) revert RentalNotActive(); // can't delist while rented

        listing.active = false;
        IERC721(address(certificate)).transferFrom(address(this), msg.sender, listing.tokenId);

        emit ItemDelisted(listingId);
    }

    function buyItem(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();
        if (listing.category != AssetCategory.DIRECT_SALE) revert InvalidCategory();
        if (msg.sender == listing.seller) revert SelfBuy();

        listing.active = false;

        uint256 effectivePrice = _getEffectivePrice(listing.tokenId, listing.price);
        uint256 fee = (effectivePrice * secondaryFeeBps) / BPS;

        // Royalty to original vendor
        uint256 royalty;
        try certificate.getAsset(listing.tokenId) returns (
            string memory, string memory, address vendor, uint256, uint256, uint8, uint256, uint256
        ) {
            if (vendor != address(0) && vendor != listing.seller) {
                royalty = (effectivePrice * royaltyBps) / BPS;
                paymentToken.safeTransferFrom(msg.sender, vendor, royalty);
            }
        } catch {}

        uint256 sellerAmount = effectivePrice - fee - royalty;

        paymentToken.safeTransferFrom(msg.sender, listing.seller, sellerAmount);
        paymentToken.safeTransferFrom(msg.sender, marketingWallet, fee);

        IERC721(address(certificate)).transferFrom(address(this), msg.sender, listing.tokenId);

        emit ItemSold(listingId, listing.tokenId, msg.sender, effectivePrice);
    }

    // ============ Rental Flow ============

    /// @notice Tenant starts renting a RENTAL-listed asset. NFT stays locked in contract.
    function startRental(uint256 listingId, uint256 rentAmount) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();
        if (listing.category != AssetCategory.RENTAL) revert NotRental();
        if (rentals[listingId].active) revert RentalNotActive();
        if (rentAmount == 0) revert ZeroAmount();

        rentals[listingId] = RentalInfo({
            tenant: msg.sender,
            rentAmount: rentAmount,
            lastPaidAt: block.timestamp,
            active: true
        });

        emit RentalStarted(listingId, msg.sender, rentAmount);
    }

    /// @notice Tenant pays periodic rent. 90% → Staking Pool, 10% → seller/marketing.
    function payRent(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        RentalInfo storage rental = rentals[listingId];
        if (!listing.active || !rental.active) revert RentalNotActive();
        if (rental.tenant != msg.sender) revert NotTenant();

        uint256 amount = rental.rentAmount;
        uint256 toStaking = (amount * rentalShareBps) / BPS;
        uint256 toSeller = amount - toStaking;

        rental.lastPaidAt = block.timestamp;

        // Transfer rent from tenant
        paymentToken.safeTransferFrom(msg.sender, address(this), toStaking);
        paymentToken.safeTransferFrom(msg.sender, listing.seller, toSeller);

        // Route staking share to revenue pool
        paymentToken.approve(address(stakingContract), toStaking);
        stakingContract.notifyRewardAmount(toStaking);

        emit RentPaid(listingId, msg.sender, amount, toStaking);
    }

    /// @notice Seller or admin ends rental
    function endRental(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotSeller();
        if (!rentals[listingId].active) revert RentalNotActive();

        rentals[listingId].active = false;

        emit RentalEnded(listingId);
    }

    // ============ Promo/Discount ============

    function _getEffectivePrice(uint256 tokenId, uint256 basePrice) internal view returns (uint256) {
        if (isPromotionActive && promoEligibleItems[tokenId] && stakingContract.isStaking(msg.sender)) {
            return basePrice - (basePrice * discountBps) / BPS;
        }
        return basePrice;
    }

    /// @notice Primary market discount — applies global promo if staker
    function _getEffectivePricePrimary(uint256 basePrice) internal view returns (uint256) {
        if (isPromotionActive && stakingContract.isStaking(msg.sender)) {
            return basePrice - (basePrice * discountBps) / BPS;
        }
        return basePrice;
    }

    function togglePromotion(bool active) external onlyRole(PROMO_ROLE) {
        isPromotionActive = active;
        emit PromotionToggled(active);
    }

    function setDiscountBps(uint256 bps) external onlyRole(PROMO_ROLE) {
        if (bps > BPS) revert FeeTooHigh();
        discountBps = bps;
        emit DiscountUpdated(bps);
    }

    function setPromoEligible(uint256 tokenId, bool eligible) external onlyRole(PROMO_ROLE) {
        promoEligibleItems[tokenId] = eligible;
        emit PromoItemSet(tokenId, eligible);
    }

    // ============ Price Oracle ============

    function getTokenPrice(string calldata assetType, uint256 usdPrice) public view returns (uint256) {
        IPriceFeed feed = priceFeeds[assetType];
        if (address(feed) == address(0)) revert InvalidListing();

        (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        if (block.timestamp - updatedAt > PRICE_STALENESS) revert StalePrice();

        uint8 decimals = feed.decimals();
        return (usdPrice * (10 ** decimals)) / uint256(price);
    }

    // ============ Admin ============

    function setPriceFeed(string calldata assetType, address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (feed == address(0)) revert ZeroAddress();
        priceFeeds[assetType] = IPriceFeed(feed);
        emit PriceFeedUpdated(assetType, feed);
    }

    function setFees(uint256 primaryBps, uint256 secondaryBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (primaryBps > BPS || secondaryBps > BPS) revert FeeTooHigh();
        primaryFeeBps = primaryBps;
        secondaryFeeBps = secondaryBps;
    }

    function setRentalShareBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > BPS) revert FeeTooHigh();
        rentalShareBps = bps;
    }

    function setRoyaltyBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > BPS) revert FeeTooHigh();
        royaltyBps = bps;
    }

    function setMarketingWallet(address wallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (wallet == address(0)) revert ZeroAddress();
        marketingWallet = wallet;
    }

    function setStakingContract(address staking) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (staking == address(0)) revert ZeroAddress();
        stakingContract = IRWAStaking(staking);
    }

    /// @notice Recover tokens accidentally sent to this contract
    function rescueTokens(address tokenAddr, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(tokenAddr).safeTransfer(msg.sender, amount);
        emit TokensRescued(tokenAddr, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    function proxyAdmin() external view returns (address) { return _proxyAdmin; }
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }
}
