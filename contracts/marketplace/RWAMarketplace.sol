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
}

interface IPriceFeed {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

/**
 * @title RWAMarketplace
 * @notice RWA marketplace with sale + rental, 24h escrow dispute window, multi-wallet splits
 *
 * Sale:  90% seller, 10% admin — all held 24h then claimable
 * Rental: 70% renter(owner), 20% company, 10% admin — all held 24h then claimable
 */
contract RWAMarketplace is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Errors ============
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
    error EscrowNotReady();
    error EscrowFrozen();
    error NothingToClaim();
    error EscrowNotFrozen();

    // ============ Constants & Roles ============
    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR_ROLE");
    uint256 public constant BPS = 10000;
    uint256 public constant ESCROW_PERIOD = 24 hours;
    uint256 public constant PRICE_STALENESS = 1 hours;

    // ============ Enums & Structs ============
    enum AssetCategory { DIRECT_SALE, RENTAL }

    enum EscrowStatus { HELD, CLAIMABLE, FROZEN, RESOLVED }

    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 price;
        AssetCategory category;
        bool active;
    }

    struct RentalInfo {
        address tenant;
        uint256 rentAmount;
        uint256 lastPaidAt;
        bool active;
    }

    struct Escrow {
        uint256 totalAmount;
        uint256 createdAt;
        EscrowStatus status;
        // Split amounts (pre-calculated at deposit time)
        address[] recipients;
        uint256[] amounts;
    }

    // ============ State ============
    address private immutable _proxyAdmin;

    IERC20 public paymentToken;
    IRWACertificate public certificate;
    address public adminWallet;
    address public companyWallet;

    // Fee splits in BPS
    uint256 public saleSellerBps;   // 9000 = 90%
    uint256 public saleAdminBps;    // 1000 = 10%
    uint256 public rentalOwnerBps;  // 7000 = 70%
    uint256 public rentalCompanyBps;// 2000 = 20%
    uint256 public rentalAdminBps;  // 1000 = 10%

    // Listings & Rentals
    mapping(string => IPriceFeed) public priceFeeds;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => RentalInfo) public rentals;
    uint256 private _listingIdCounter;

    // Escrow: escrowId => Escrow
    mapping(uint256 => Escrow) public escrows;
    uint256 private _escrowIdCounter;

    // ============ Events ============
    event ItemPurchased(uint256 indexed tokenId, address indexed buyer, address indexed vendor, uint256 price, uint256 escrowId);
    event ItemListed(uint256 indexed listingId, uint256 indexed tokenId, address indexed seller, uint256 price, AssetCategory category);
    event ItemDelisted(uint256 indexed listingId);
    event ItemSold(uint256 indexed listingId, uint256 indexed tokenId, address indexed buyer, uint256 price, uint256 escrowId);
    event RentPaid(uint256 indexed listingId, address indexed tenant, uint256 amount, uint256 escrowId);
    event RentalStarted(uint256 indexed listingId, address indexed tenant, uint256 rentAmount);
    event RentalEnded(uint256 indexed listingId);
    event PriceFeedUpdated(string assetType, address feed);
    event EscrowCreated(uint256 indexed escrowId, uint256 amount);
    event EscrowClaimed(uint256 indexed escrowId, address indexed recipient, uint256 amount);
    event EscrowFrozenEvent(uint256 indexed escrowId);
    event EscrowResolved(uint256 indexed escrowId, address indexed to, uint256 amount);
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
        address adminWallet_,
        address companyWallet_,
        address admin_
    ) external initializer {
        if (paymentToken_ == address(0) || certificate_ == address(0) ||
            adminWallet_ == address(0) || companyWallet_ == address(0) ||
            admin_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        paymentToken = IERC20(paymentToken_);
        certificate = IRWACertificate(certificate_);
        adminWallet = adminWallet_;
        companyWallet = companyWallet_;

        saleSellerBps = 9000;
        saleAdminBps = 1000;
        rentalOwnerBps = 7000;
        rentalCompanyBps = 2000;
        rentalAdminBps = 1000;
    }

    // ============ Escrow Internals ============

    function _createEscrow(
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 totalAmount
    ) internal returns (uint256 escrowId) {
        escrowId = ++_escrowIdCounter;
        escrows[escrowId] = Escrow({
            totalAmount: totalAmount,
            createdAt: block.timestamp,
            status: EscrowStatus.HELD,
            recipients: recipients,
            amounts: amounts
        });
        emit EscrowCreated(escrowId, totalAmount);
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

        // Pull full amount into contract as escrow
        paymentToken.safeTransferFrom(msg.sender, address(this), tokenPrice);

        // Build escrow splits: 90% vendor, 10% admin
        uint256 escrowId = _createSaleEscrow(vendor, tokenPrice);

        uint256 tokenId = certificate.mint(msg.sender, uri, assetType, serialNumber, vendor, tokenPrice);

        emit ItemPurchased(tokenId, msg.sender, vendor, tokenPrice, escrowId);
    }

    function _createSaleEscrow(address seller, uint256 totalAmount) internal returns (uint256) {
        address[] memory r = new address[](2);
        uint256[] memory a = new uint256[](2);
        r[0] = seller;       a[0] = (totalAmount * saleSellerBps) / BPS;
        r[1] = adminWallet;  a[1] = totalAmount - a[0];
        return _createEscrow(r, a, totalAmount);
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
        if (rentals[listingId].active) revert RentalNotActive();

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
        uint256 price = listing.price;

        // Pull full amount into contract as escrow
        paymentToken.safeTransferFrom(msg.sender, address(this), price);

        uint256 escrowId = _createSaleEscrow(listing.seller, price);

        IERC721(address(certificate)).transferFrom(address(this), msg.sender, listing.tokenId);

        emit ItemSold(listingId, listing.tokenId, msg.sender, price, escrowId);
    }

    // ============ Rental Flow ============

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

    /// @notice Tenant pays rent. 70% owner, 20% company, 10% admin — all held 24h
    function payRent(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        RentalInfo storage rental = rentals[listingId];
        if (!listing.active || !rental.active) revert RentalNotActive();
        if (rental.tenant != msg.sender) revert NotTenant();

        uint256 amount = rental.rentAmount;
        rental.lastPaidAt = block.timestamp;

        // Pull full amount into contract as escrow
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Build escrow splits: 70% owner, 20% company, 10% admin
        address[] memory r = new address[](3);
        uint256[] memory a = new uint256[](3);
        r[0] = listing.seller;  a[0] = (amount * rentalOwnerBps) / BPS;
        r[1] = companyWallet;   a[1] = (amount * rentalCompanyBps) / BPS;
        r[2] = adminWallet;     a[2] = amount - a[0] - a[1];

        uint256 escrowId = _createEscrow(r, a, amount);

        emit RentPaid(listingId, msg.sender, amount, escrowId);
    }

    /// @notice Seller or admin ends rental
    function endRental(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotSeller();
        if (!rentals[listingId].active) revert RentalNotActive();

        rentals[listingId].active = false;

        emit RentalEnded(listingId);
    }

    // ============ Escrow: Claim & Dispute ============

    /// @notice Recipient claims their share after 24h dispute window
    function claimEscrow(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        if (e.status == EscrowStatus.FROZEN) revert EscrowFrozen();
        if (e.status != EscrowStatus.HELD && e.status != EscrowStatus.CLAIMABLE) revert NothingToClaim();
        if (e.status == EscrowStatus.HELD && block.timestamp < e.createdAt + ESCROW_PERIOD) revert EscrowNotReady();

        e.status = EscrowStatus.CLAIMABLE;

        uint256 claimed;
        for (uint256 i = 0; i < e.recipients.length; i++) {
            if (e.recipients[i] == msg.sender && e.amounts[i] > 0) {
                uint256 amt = e.amounts[i];
                e.amounts[i] = 0;
                claimed += amt;
            }
        }
        if (claimed == 0) revert NothingToClaim();

        paymentToken.safeTransfer(msg.sender, claimed);

        emit EscrowClaimed(escrowId, msg.sender, claimed);
    }

    /// @notice Admin freezes escrow during 24h window
    function freezeEscrow(uint256 escrowId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Escrow storage e = escrows[escrowId];
        if (e.status != EscrowStatus.HELD) revert EscrowNotReady();

        e.status = EscrowStatus.FROZEN;

        emit EscrowFrozenEvent(escrowId);
    }

    /// @notice Admin resolves frozen escrow — sends specified amount to any address
    function resolveEscrow(uint256 escrowId, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        Escrow storage e = escrows[escrowId];
        if (e.status != EscrowStatus.FROZEN) revert EscrowNotFrozen();

        // Deduct from remaining amounts
        uint256 remaining;
        for (uint256 i = 0; i < e.amounts.length; i++) {
            remaining += e.amounts[i];
        }
        if (amount > remaining) revert ZeroAmount();

        // Deduct proportionally from all recipients
        uint256 toDeduct = amount;
        for (uint256 i = 0; i < e.amounts.length && toDeduct > 0; i++) {
            if (e.amounts[i] >= toDeduct) {
                e.amounts[i] -= toDeduct;
                toDeduct = 0;
            } else {
                toDeduct -= e.amounts[i];
                e.amounts[i] = 0;
            }
        }

        paymentToken.safeTransfer(to, amount);

        // Check if fully resolved
        remaining = 0;
        for (uint256 i = 0; i < e.amounts.length; i++) {
            remaining += e.amounts[i];
        }
        if (remaining == 0) {
            e.status = EscrowStatus.RESOLVED;
        }

        emit EscrowResolved(escrowId, to, amount);
    }

    /// @notice Admin unfreezes escrow (dispute resolved in seller's favor)
    function unfreezeEscrow(uint256 escrowId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Escrow storage e = escrows[escrowId];
        if (e.status != EscrowStatus.FROZEN) revert EscrowNotFrozen();

        e.status = EscrowStatus.CLAIMABLE;
    }

    // ============ Escrow Views ============

    function getEscrow(uint256 escrowId) external view returns (
        uint256 totalAmount, uint256 createdAt, EscrowStatus status,
        address[] memory recipients, uint256[] memory amounts
    ) {
        Escrow storage e = escrows[escrowId];
        return (e.totalAmount, e.createdAt, e.status, e.recipients, e.amounts);
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

    function setSaleFeeBps(uint256 sellerBps, uint256 adminBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (sellerBps + adminBps != BPS) revert FeeTooHigh();
        saleSellerBps = sellerBps;
        saleAdminBps = adminBps;
    }

    function setRentalFeeBps(uint256 ownerBps, uint256 companyBps, uint256 adminBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (ownerBps + companyBps + adminBps != BPS) revert FeeTooHigh();
        rentalOwnerBps = ownerBps;
        rentalCompanyBps = companyBps;
        rentalAdminBps = adminBps;
    }

    function setAdminWallet(address wallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (wallet == address(0)) revert ZeroAddress();
        adminWallet = wallet;
    }

    function setCompanyWallet(address wallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (wallet == address(0)) revert ZeroAddress();
        companyWallet = wallet;
    }

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
