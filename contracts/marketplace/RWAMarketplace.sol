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

/**
 * @title RWAMarketplace
 * @notice Listing-first marketplace with 6h price freshness, 24h escrow, dispute resolution
 *
 * All items must be listed before purchase. Prices in tokens.
 * Sale:   90% seller / 10% admin — escrowed 24h
 * Rental: 70% owner / 20% company / 10% admin — full upfront, escrowed 24h
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
    error PriceStale();
    error NotRental();
    error RentalNotActive();
    error RentalStillActive();
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
    uint256 public constant PRICE_FRESHNESS = 6 hours;

    // ============ Enums & Structs ============
    enum AssetCategory { DIRECT_SALE, RENTAL }
    enum ListingType { PRIMARY, SECONDARY }
    enum EscrowStatus { HELD, CLAIMABLE, FROZEN, RESOLVED }

    struct Listing {
        address seller;
        uint256 price;            // in tokens
        uint256 priceUpdatedAt;
        AssetCategory category;
        ListingType listingType;
        bool active;
        // Primary-only fields
        string assetType;
        string serialNumber;
        string uri;
        // Secondary-only: tokenId of existing NFT
        uint256 tokenId;
        // Rental-only fields
        uint256 rentalDuration;   // seconds (e.g., 30 days)
    }

    struct RentalInfo {
        address tenant;
        uint256 paidAmount;
        uint256 startedAt;
        uint256 endsAt;
        bool active;
    }

    struct Escrow {
        uint256 totalAmount;
        uint256 createdAt;
        EscrowStatus status;
        address[] recipients;
        uint256[] amounts;
    }

    // ============ State ============
    address private immutable _proxyAdmin;

    IERC20 public paymentToken;
    IRWACertificate public certificate;
    address public adminWallet;
    address public companyWallet;

    uint256 public saleSellerBps;    // 9000
    uint256 public saleAdminBps;     // 1000
    uint256 public rentalOwnerBps;   // 7000
    uint256 public rentalCompanyBps; // 2000
    uint256 public rentalAdminBps;   // 1000

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => RentalInfo) public rentals;
    mapping(uint256 => Escrow) public escrows;
    uint256 private _listingIdCounter;
    uint256 private _escrowIdCounter;

    // ============ Events ============
    event Listed(uint256 indexed listingId, address indexed seller, uint256 price, AssetCategory category, ListingType lType);
    event PriceUpdated(uint256 indexed listingId, uint256 oldPrice, uint256 newPrice);
    event Delisted(uint256 indexed listingId);
    event Purchased(uint256 indexed listingId, address indexed buyer, uint256 price, uint256 escrowId, uint256 tokenId);
    event RentalStarted(uint256 indexed listingId, address indexed tenant, uint256 amount, uint256 endsAt, uint256 escrowId);
    event RentalEnded(uint256 indexed listingId);
    event EscrowCreated(uint256 indexed escrowId, uint256 amount);
    event EscrowClaimed(uint256 indexed escrowId, address indexed recipient, uint256 amount);
    event EscrowFrozenEvt(uint256 indexed escrowId);
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

    // ============ Listing ============

    /// @notice Vendor lists a new (unminted) item for primary sale or rental
    function listNewItem(
        uint256 price,
        AssetCategory category,
        string calldata assetType,
        string calldata serialNumber,
        string calldata uri,
        uint256 rentalDuration
    ) external nonReentrant whenNotPaused onlyRole(VENDOR_ROLE) {
        if (price == 0) revert ZeroAmount();
        if (category == AssetCategory.RENTAL && rentalDuration == 0) revert ZeroAmount();

        uint256 listingId = ++_listingIdCounter;
        Listing storage l = listings[listingId];
        l.seller = msg.sender;
        l.price = price;
        l.priceUpdatedAt = block.timestamp;
        l.category = category;
        l.listingType = ListingType.PRIMARY;
        l.active = true;
        l.assetType = assetType;
        l.serialNumber = serialNumber;
        l.uri = uri;
        l.rentalDuration = rentalDuration;

        emit Listed(listingId, msg.sender, price, category, ListingType.PRIMARY);
    }

    /// @notice Owner lists an existing NFT for secondary sale or rental
    function listExistingItem(
        uint256 tokenId,
        uint256 price,
        AssetCategory category,
        uint256 rentalDuration
    ) external nonReentrant whenNotPaused {
        if (price == 0) revert ZeroAmount();
        if (category == AssetCategory.RENTAL && rentalDuration == 0) revert ZeroAmount();

        IERC721(address(certificate)).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = ++_listingIdCounter;
        Listing storage l = listings[listingId];
        l.seller = msg.sender;
        l.price = price;
        l.priceUpdatedAt = block.timestamp;
        l.category = category;
        l.listingType = ListingType.SECONDARY;
        l.active = true;
        l.tokenId = tokenId;
        l.rentalDuration = rentalDuration;

        emit Listed(listingId, msg.sender, price, category, ListingType.SECONDARY);
    }

    /// @notice Seller updates price — resets freshness timer
    function updatePrice(uint256 listingId, uint256 newPrice) external {
        Listing storage l = listings[listingId];
        if (l.seller != msg.sender) revert NotSeller();
        if (!l.active) revert ListingNotActive();
        if (newPrice == 0) revert ZeroAmount();

        uint256 oldPrice = l.price;
        l.price = newPrice;
        l.priceUpdatedAt = block.timestamp;

        emit PriceUpdated(listingId, oldPrice, newPrice);
    }

    function delistItem(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        if (l.seller != msg.sender) revert NotSeller();
        if (!l.active) revert ListingNotActive();
        if (rentals[listingId].active) revert RentalStillActive();

        l.active = false;

        if (l.listingType == ListingType.SECONDARY) {
            IERC721(address(certificate)).transferFrom(address(this), msg.sender, l.tokenId);
        }

        emit Delisted(listingId);
    }

    // ============ Purchase (Sale) ============

    /// @notice Buy a listed item. Price must be fresh (<6h).
    function purchaseItem(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage l = listings[listingId];
        if (!l.active) revert ListingNotActive();
        if (l.category != AssetCategory.DIRECT_SALE) revert InvalidCategory();
        if (msg.sender == l.seller) revert SelfBuy();
        _requireFreshPrice(l.priceUpdatedAt);

        l.active = false;
        uint256 price = l.price;

        paymentToken.safeTransferFrom(msg.sender, address(this), price);
        uint256 escrowId = _createSaleEscrow(l.seller, price);

        uint256 tokenId;
        if (l.listingType == ListingType.PRIMARY) {
            tokenId = certificate.mint(msg.sender, l.uri, l.assetType, l.serialNumber, l.seller, price);
        } else {
            tokenId = l.tokenId;
            IERC721(address(certificate)).transferFrom(address(this), msg.sender, tokenId);
        }

        emit Purchased(listingId, msg.sender, price, escrowId, tokenId);
    }

    // ============ Rental ============

    /// @notice Tenant rents a listed item. Pays full amount upfront. Price must be fresh.
    function startRental(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage l = listings[listingId];
        if (!l.active) revert ListingNotActive();
        if (l.category != AssetCategory.RENTAL) revert NotRental();
        if (rentals[listingId].active) revert RentalStillActive();
        _requireFreshPrice(l.priceUpdatedAt);

        uint256 amount = l.price;
        uint256 endsAt = block.timestamp + l.rentalDuration;

        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Escrow: 70% owner, 20% company, 10% admin
        address[] memory r = new address[](3);
        uint256[] memory a = new uint256[](3);
        r[0] = l.seller;       a[0] = (amount * rentalOwnerBps) / BPS;
        r[1] = companyWallet;   a[1] = (amount * rentalCompanyBps) / BPS;
        r[2] = adminWallet;     a[2] = amount - a[0] - a[1];
        uint256 escrowId = _createEscrow(r, a, amount);

        rentals[listingId] = RentalInfo({
            tenant: msg.sender,
            paidAmount: amount,
            startedAt: block.timestamp,
            endsAt: endsAt,
            active: true
        });

        // Mint NFT for primary rental
        if (l.listingType == ListingType.PRIMARY) {
            certificate.mint(msg.sender, l.uri, l.assetType, l.serialNumber, l.seller, amount);
        }

        emit RentalStarted(listingId, msg.sender, amount, endsAt, escrowId);
    }

    /// @notice Seller or admin ends rental (only after duration expires, or admin override)
    function endRental(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        RentalInfo storage r = rentals[listingId];
        if (!r.active) revert RentalNotActive();

        bool isAdmin = hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        bool isSeller = l.seller == msg.sender;
        if (!isSeller && !isAdmin) revert NotSeller();

        // Seller can only end after duration; admin can end anytime
        if (isSeller && !isAdmin && block.timestamp < r.endsAt) revert RentalStillActive();

        r.active = false;

        emit RentalEnded(listingId);
    }

    // ============ Escrow ============

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

    function _createSaleEscrow(address seller, uint256 totalAmount) internal returns (uint256) {
        address[] memory r = new address[](2);
        uint256[] memory a = new uint256[](2);
        r[0] = seller;       a[0] = (totalAmount * saleSellerBps) / BPS;
        r[1] = adminWallet;  a[1] = totalAmount - a[0];
        return _createEscrow(r, a, totalAmount);
    }

    function claimEscrow(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        if (e.status == EscrowStatus.FROZEN) revert EscrowFrozen();
        if (e.status != EscrowStatus.HELD && e.status != EscrowStatus.CLAIMABLE) revert NothingToClaim();
        if (e.status == EscrowStatus.HELD && block.timestamp < e.createdAt + ESCROW_PERIOD) revert EscrowNotReady();

        e.status = EscrowStatus.CLAIMABLE;

        uint256 claimed;
        for (uint256 i = 0; i < e.recipients.length; i++) {
            if (e.recipients[i] == msg.sender && e.amounts[i] > 0) {
                claimed += e.amounts[i];
                e.amounts[i] = 0;
            }
        }
        if (claimed == 0) revert NothingToClaim();

        paymentToken.safeTransfer(msg.sender, claimed);
        emit EscrowClaimed(escrowId, msg.sender, claimed);
    }

    function freezeEscrow(uint256 escrowId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Escrow storage e = escrows[escrowId];
        if (e.status != EscrowStatus.HELD) revert EscrowNotReady();
        e.status = EscrowStatus.FROZEN;
        emit EscrowFrozenEvt(escrowId);
    }

    function resolveEscrow(uint256 escrowId, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        Escrow storage e = escrows[escrowId];
        if (e.status != EscrowStatus.FROZEN) revert EscrowNotFrozen();

        uint256 remaining;
        for (uint256 i = 0; i < e.amounts.length; i++) remaining += e.amounts[i];
        if (amount > remaining) revert ZeroAmount();

        uint256 toDeduct = amount;
        for (uint256 i = 0; i < e.amounts.length && toDeduct > 0; i++) {
            if (e.amounts[i] >= toDeduct) { e.amounts[i] -= toDeduct; toDeduct = 0; }
            else { toDeduct -= e.amounts[i]; e.amounts[i] = 0; }
        }

        paymentToken.safeTransfer(to, amount);

        remaining = 0;
        for (uint256 i = 0; i < e.amounts.length; i++) remaining += e.amounts[i];
        if (remaining == 0) e.status = EscrowStatus.RESOLVED;

        emit EscrowResolved(escrowId, to, amount);
    }

    function unfreezeEscrow(uint256 escrowId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Escrow storage e = escrows[escrowId];
        if (e.status != EscrowStatus.FROZEN) revert EscrowNotFrozen();
        e.status = EscrowStatus.CLAIMABLE;
    }

    function getEscrow(uint256 escrowId) external view returns (
        uint256 totalAmount, uint256 createdAt, EscrowStatus status,
        address[] memory recipients, uint256[] memory amounts
    ) {
        Escrow storage e = escrows[escrowId];
        return (e.totalAmount, e.createdAt, e.status, e.recipients, e.amounts);
    }

    // ============ Internal ============

    function _requireFreshPrice(uint256 updatedAt) internal view {
        if (block.timestamp > updatedAt + PRICE_FRESHNESS) revert PriceStale();
    }

    // ============ Admin ============

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
