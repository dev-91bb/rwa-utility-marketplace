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
 * @notice Primary & secondary market for RWA assets with Chainlink price feeds
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
    error InsufficientPayment();
    error ListingNotActive();
    error StalePrice();

    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR_ROLE");

    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    address private immutable _proxyAdmin;

    IERC20 public paymentToken;
    IRWACertificate public certificate;
    address public marketingWallet;

    uint256 public primaryFeeBps;    // 5% = 500
    uint256 public secondaryFeeBps;  // 3% = 300
    uint256 public constant BPS = 10000;
    uint256 public constant PRICE_STALENESS = 1 hours;

    mapping(string => IPriceFeed) public priceFeeds; // assetType => oracle
    mapping(uint256 => Listing) public listings;     // listingId => Listing
    uint256 private _listingIdCounter;

    event ItemPurchased(uint256 indexed tokenId, address indexed buyer, address indexed vendor, uint256 price);
    event ItemListed(uint256 indexed listingId, uint256 indexed tokenId, address indexed seller, uint256 price);
    event ItemDelisted(uint256 indexed listingId);
    event ItemSold(uint256 indexed listingId, uint256 indexed tokenId, address indexed buyer, uint256 price);
    event PriceFeedUpdated(string assetType, address feed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    function initialize(
        address paymentToken_,
        address certificate_,
        address marketingWallet_,
        address admin_,
        uint256 primaryFeeBps_,
        uint256 secondaryFeeBps_
    ) external initializer {
        if (paymentToken_ == address(0) || certificate_ == address(0) || 
            marketingWallet_ == address(0) || admin_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        paymentToken = IERC20(paymentToken_);
        certificate = IRWACertificate(certificate_);
        marketingWallet = marketingWallet_;
        primaryFeeBps = primaryFeeBps_;
        secondaryFeeBps = secondaryFeeBps_;
    }

    // ============ Primary Market ============

    function purchaseItem(
        string calldata assetType,
        string calldata serialNumber,
        string calldata uri,
        address vendor,
        uint256 usdPrice // Price in USD (8 decimals)
    ) external nonReentrant whenNotPaused {
        if (!hasRole(VENDOR_ROLE, vendor)) revert InvalidListing();

        uint256 tokenPrice = getTokenPrice(assetType, usdPrice);
        uint256 fee = (tokenPrice * primaryFeeBps) / BPS;
        uint256 vendorAmount = tokenPrice - fee;

        paymentToken.safeTransferFrom(msg.sender, vendor, vendorAmount);
        paymentToken.safeTransferFrom(msg.sender, marketingWallet, fee);

        uint256 tokenId = certificate.mint(msg.sender, uri, assetType, serialNumber, vendor, tokenPrice);

        emit ItemPurchased(tokenId, msg.sender, vendor, tokenPrice);
    }

    // ============ Secondary Market (P2P) ============

    function listItem(uint256 tokenId, uint256 price) external nonReentrant whenNotPaused {
        if (price == 0) revert ZeroAmount();

        IERC721(address(certificate)).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = ++_listingIdCounter;
        listings[listingId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit ItemListed(listingId, tokenId, msg.sender, price);
    }

    function delistItem(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.active) revert ListingNotActive();

        listing.active = false;
        IERC721(address(certificate)).transferFrom(address(this), msg.sender, listing.tokenId);

        emit ItemDelisted(listingId);
    }

    function buyItem(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();

        listing.active = false;

        uint256 fee = (listing.price * secondaryFeeBps) / BPS;
        uint256 sellerAmount = listing.price - fee;

        paymentToken.safeTransferFrom(msg.sender, listing.seller, sellerAmount);
        paymentToken.safeTransferFrom(msg.sender, marketingWallet, fee);

        IERC721(address(certificate)).transferFrom(address(this), msg.sender, listing.tokenId);

        emit ItemSold(listingId, listing.tokenId, msg.sender, listing.price);
    }

    // ============ Price Oracle ============

    function getTokenPrice(string calldata assetType, uint256 usdPrice) public view returns (uint256) {
        IPriceFeed feed = priceFeeds[assetType];
        if (address(feed) == address(0)) revert InvalidListing();

        (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        if (block.timestamp - updatedAt > PRICE_STALENESS) revert StalePrice();

        uint8 decimals = feed.decimals();
        // Convert USD price to token amount: usdPrice / tokenPriceInUsd
        return (usdPrice * (10 ** decimals)) / uint256(price);
    }

    // ============ Admin ============

    function setPriceFeed(string calldata assetType, address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (feed == address(0)) revert ZeroAddress();
        priceFeeds[assetType] = IPriceFeed(feed);
        emit PriceFeedUpdated(assetType, feed);
    }

    function setFees(uint256 primaryBps, uint256 secondaryBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        primaryFeeBps = primaryBps;
        secondaryFeeBps = secondaryBps;
    }

    function setMarketingWallet(address wallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (wallet == address(0)) revert ZeroAddress();
        marketingWallet = wallet;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    function proxyAdmin() external view returns (address) { return _proxyAdmin; }
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }
}
