// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RWACertificate
 * @notice NFT representing ownership of real-world assets (gold, property, luxury goods)
 * @dev Each token is a certificate of ownership - redeemable for physical asset
 */
contract RWACertificate is
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error OnlyProxyAdmin();
    error AlreadyRedeemed();
    error NotRedeemed();
    error NotOwner();
    error InvalidStatus();
    error NotTransferable();

    enum AssetStatus {
        Active,     // Tradeable, not claimed
        Redeemed,   // Fee paid, awaiting pickup
        Fulfilled,  // Asset delivered, can burn
        Cancelled,  // Refunded
        Expired,    // Validity ended
        Disputed    // Frozen
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR_ROLE");

    struct Asset {
        string assetType;
        string serialNumber;
        address vendor;
        uint256 purchasePrice;
        uint256 purchaseTime;
        AssetStatus status;
        uint256 statusUpdatedAt;
        uint256 redemptionFee;
        address[] previousOwners;
    }

    address private immutable _proxyAdmin;
    uint256 private _tokenIdCounter;

    IERC20 public paymentToken;
    address public feeReceiver;

    mapping(uint256 => Asset) public assets;
    mapping(string => uint256) public redemptionFeeBps; // assetType => fee in BPS

    uint256 public constant BPS = 10000;

    event AssetMinted(uint256 indexed tokenId, address indexed buyer, address indexed vendor, string assetType, string serialNumber);
    event AssetRedeemed(uint256 indexed tokenId, address indexed holder, uint256 fee);
    event AssetBurned(uint256 indexed tokenId);
    event AssetStatusChanged(uint256 indexed tokenId, AssetStatus status);
    event RedemptionFeeUpdated(string assetType, uint256 feeBps);
    event FeeReceiverUpdated(address receiver);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address admin_,
        address paymentToken_,
        address feeReceiver_
    ) external initializer {
        if (admin_ == address(0) || paymentToken_ == address(0) || feeReceiver_ == address(0)) 
            revert ZeroAddress();

        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        paymentToken = IERC20(paymentToken_);
        feeReceiver = feeReceiver_;
    }

    function mint(
        address to,
        string calldata uri,
        string calldata assetType,
        string calldata serialNumber,
        address vendor,
        uint256 purchasePrice
    ) external onlyRole(MINTER_ROLE) whenNotPaused returns (uint256) {
        if (to == address(0) || vendor == address(0)) revert ZeroAddress();

        uint256 tokenId = ++_tokenIdCounter;

        assets[tokenId] = Asset({
            assetType: assetType,
            serialNumber: serialNumber,
            vendor: vendor,
            purchasePrice: purchasePrice,
            purchaseTime: block.timestamp,
            status: AssetStatus.Active,
            statusUpdatedAt: block.timestamp,
            redemptionFee: 0,
            previousOwners: new address[](0)
        });

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit AssetMinted(tokenId, to, vendor, assetType, serialNumber);
        return tokenId;
    }

    function redeem(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        
        Asset storage asset = assets[tokenId];
        if (asset.status != AssetStatus.Active) revert InvalidStatus();

        uint256 fee = (asset.purchasePrice * redemptionFeeBps[asset.assetType]) / BPS;
        
        if (fee > 0) {
            paymentToken.safeTransferFrom(msg.sender, feeReceiver, fee);
        }

        asset.status = AssetStatus.Redeemed;
        asset.statusUpdatedAt = block.timestamp;
        asset.redemptionFee = fee;

        emit AssetRedeemed(tokenId, msg.sender, fee);
        emit AssetStatusChanged(tokenId, AssetStatus.Redeemed);
    }

    function markFulfilled(uint256 tokenId) external onlyRole(VENDOR_ROLE) {
        Asset storage asset = assets[tokenId];
        if (asset.status != AssetStatus.Redeemed) revert InvalidStatus();
        
        asset.status = AssetStatus.Fulfilled;
        asset.statusUpdatedAt = block.timestamp;
        emit AssetStatusChanged(tokenId, AssetStatus.Fulfilled);
    }

    function cancel(uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Asset storage asset = assets[tokenId];
        if (asset.status == AssetStatus.Fulfilled) revert InvalidStatus();
        
        asset.status = AssetStatus.Cancelled;
        asset.statusUpdatedAt = block.timestamp;
        emit AssetStatusChanged(tokenId, AssetStatus.Cancelled);
    }

    function dispute(uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Asset storage asset = assets[tokenId];
        if (asset.status != AssetStatus.Active && asset.status != AssetStatus.Redeemed) 
            revert InvalidStatus();
        
        asset.status = AssetStatus.Disputed;
        asset.statusUpdatedAt = block.timestamp;
        emit AssetStatusChanged(tokenId, AssetStatus.Disputed);
    }

    function resolveDispute(uint256 tokenId, AssetStatus newStatus) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Asset storage asset = assets[tokenId];
        if (asset.status != AssetStatus.Disputed) revert InvalidStatus();
        
        asset.status = newStatus;
        asset.statusUpdatedAt = block.timestamp;
        emit AssetStatusChanged(tokenId, newStatus);
    }

    function getRedemptionFee(uint256 tokenId) external view returns (uint256) {
        Asset storage asset = assets[tokenId];
        return (asset.purchasePrice * redemptionFeeBps[asset.assetType]) / BPS;
    }

    function setRedemptionFee(string calldata assetType, uint256 feeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        redemptionFeeBps[assetType] = feeBps;
        emit RedemptionFeeUpdated(assetType, feeBps);
    }

    function setFeeReceiver(address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (receiver == address(0)) revert ZeroAddress();
        feeReceiver = receiver;
        emit FeeReceiverUpdated(receiver);
    }

    function burn(uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (assets[tokenId].status != AssetStatus.Fulfilled && 
            assets[tokenId].status != AssetStatus.Cancelled) revert InvalidStatus();
        _burn(tokenId);
        emit AssetBurned(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable) returns (address) {
        address from = _ownerOf(tokenId);
        
        // Track previous owner on transfer (not mint/burn)
        if (from != address(0) && to != address(0)) {
            if (assets[tokenId].status != AssetStatus.Active) revert NotTransferable();
            assets[tokenId].previousOwners.push(from);
        }
        
        return super._update(to, tokenId, auth);
    }

    function isRedeemed(uint256 tokenId) external view returns (bool) {
        return assets[tokenId].status == AssetStatus.Redeemed || 
               assets[tokenId].status == AssetStatus.Fulfilled;
    }

    function getAsset(uint256 tokenId) external view returns (Asset memory) {
        return assets[tokenId];
    }

    function getPreviousOwners(uint256 tokenId) external view returns (address[] memory) {
        return assets[tokenId].previousOwners;
    }

    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    function proxyAdmin() external view returns (address) { return _proxyAdmin; }
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }

    // Required overrides
    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
