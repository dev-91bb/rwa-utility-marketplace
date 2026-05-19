// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PropertyToken
 * @notice ERC-1400 security token for fractional property ownership.
 *         Implements transfer restrictions (KYC), partition-based locking,
 *         operator authorization, and issuance/redemption hooks.
 * @dev Hybrid proxy pattern: immutable _proxyAdmin set in constructor.
 *      Partitions: bytes32("unlocked") = freely transferable (KYC required)
 *                  bytes32("locked")   = non-transferable (vesting / lock-up)
 */
contract PropertyToken is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    // ============ Errors ============
    error ZeroAddress();
    error OnlyProxyAdmin();
    error TransferRestricted(bytes1 reasonCode);
    error NotIssuable();
    error InvalidPartition(bytes32 partition);
    error InsufficientPartitionBalance();
    error NotOperator();

    // ============ ERC-1066 Reason Codes ============
    bytes1 public constant TRANSFER_SUCCESS       = 0x51;
    bytes1 public constant TRANSFER_FAILURE       = 0x50;
    bytes1 public constant INSUFFICIENT_BALANCE   = 0x52;
    bytes1 public constant TRANSFERS_HALTED       = 0x54;
    bytes1 public constant FUNDS_LOCKED           = 0x55;
    bytes1 public constant INVALID_SENDER         = 0x56;
    bytes1 public constant INVALID_RECEIVER       = 0x57;

    // ============ Partitions ============
    bytes32 public constant PARTITION_UNLOCKED = bytes32("unlocked");
    bytes32 public constant PARTITION_LOCKED   = bytes32("locked");

    // ============ Hybrid Proxy ============
    address private immutable _proxyAdmin;
    uint256 public constant VERSION = 1;

    // ============ ERC-1400 State ============
    address public kycRegistry;
    bool public issuable;

    string public propertyId;
    uint256 public totalValueUSD;
    uint256 public tokenPriceUSD;
    uint256 public maxSupply;       // hard cap — set at initialize, never changes

    /// @dev partition => holder => balance
    mapping(bytes32 => mapping(address => uint256)) private _partitionBalances;

    /// @dev holder => partitions list
    mapping(address => bytes32[]) private _holderPartitions;

    /// @dev global operators (authorized for all holders)
    mapping(address => bool) private _globalOperators;

    /// @dev partition => operator => holder => authorized
    mapping(bytes32 => mapping(address => mapping(address => bool))) private _partitionOperators;

    // ============ Events (ERC-1400) ============
    event TransferByPartition(bytes32 indexed fromPartition, address operator, address indexed from, address indexed to, uint256 value, bytes data, bytes operatorData);
    event AuthorizedOperator(address indexed operator, address indexed tokenHolder);
    event RevokedOperator(address indexed operator, address indexed tokenHolder);
    event AuthorizedOperatorByPartition(bytes32 indexed partition, address indexed operator, address indexed tokenHolder);
    event RevokedOperatorByPartition(bytes32 indexed partition, address indexed operator, address indexed tokenHolder);
    event Issued(address indexed operator, address indexed to, uint256 value, bytes data);
    event Redeemed(address indexed operator, address indexed from, uint256 value, bytes data);
    event IssuedByPartition(bytes32 indexed partition, address indexed operator, address indexed to, uint256 value, bytes data, bytes operatorData);
    event RedeemedByPartition(bytes32 indexed partition, address indexed operator, address indexed from, uint256 value, bytes operatorData);
    event KYCRegistryUpdated(address indexed registry);

    // ============ Constructor ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    // ============ Initializer ============
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory propertyId_,
        uint256 totalSupply_,
        uint256 totalValueUSD_,
        uint256 tokenPriceUSD_,
        address kycRegistry_,
        address owner_
    ) external initializer {
        if (owner_ == address(0) || kycRegistry_ == address(0)) revert ZeroAddress();
        __ERC20_init(name_, symbol_);
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();

        propertyId    = propertyId_;
        totalValueUSD = totalValueUSD_;
        tokenPriceUSD = tokenPriceUSD_;
        kycRegistry   = kycRegistry_;
        issuable      = true;
        maxSupply     = totalSupply_;   // hard cap fixed at deploy time

        // Issue entire supply to owner in unlocked partition
        _issueByPartition(PARTITION_UNLOCKED, owner_, owner_, totalSupply_, "", "");
    }

    // ============ ERC-1400: Token Information ============

    function balanceOfByPartition(bytes32 partition, address holder) external view returns (uint256) {
        return _partitionBalances[partition][holder];
    }

    function partitionsOf(address holder) external view returns (bytes32[] memory) {
        return _holderPartitions[holder];
    }

    // ============ ERC-1400: Transfer Validity ============

    function canTransfer(address to, uint256 value, bytes calldata /*data*/) external view returns (bytes1, bytes32) {
        return _canTransfer(msg.sender, to, value);
    }

    function canTransferFrom(address from, address to, uint256 value, bytes calldata /*data*/) external view returns (bytes1, bytes32) {
        return _canTransfer(from, to, value);
    }

    function canTransferByPartition(address from, address to, bytes32 partition, uint256 value, bytes calldata /*data*/)
        external view returns (bytes1, bytes32, bytes32)
    {
        if (partition != PARTITION_UNLOCKED && partition != PARTITION_LOCKED)
            return (TRANSFER_FAILURE, bytes32("invalid partition"), partition);
        if (partition == PARTITION_LOCKED)
            return (FUNDS_LOCKED, bytes32("partition locked"), partition);
        (bytes1 code, bytes32 reason) = _canTransfer(from, to, value);
        return (code, reason, partition);
    }

    // ============ ERC-1400: Transfers ============

    function transferWithData(address to, uint256 value, bytes calldata data) external {
        _erc1400Transfer(PARTITION_UNLOCKED, msg.sender, msg.sender, to, value, data, "");
    }

    function transferFromWithData(address from, address to, uint256 value, bytes calldata data) external {
        if (!_isOperatorFor(msg.sender, from)) revert NotOperator();
        _erc1400Transfer(PARTITION_UNLOCKED, msg.sender, from, to, value, data, "");
    }

    function transferByPartition(bytes32 partition, address to, uint256 value, bytes calldata data) external returns (bytes32) {
        _erc1400Transfer(partition, msg.sender, msg.sender, to, value, data, "");
        return partition;
    }

    function operatorTransferByPartition(bytes32 partition, address from, address to, uint256 value, bytes calldata data, bytes calldata operatorData) external returns (bytes32) {
        if (!_isOperatorForPartition(partition, msg.sender, from)) revert NotOperator();
        _erc1400Transfer(partition, msg.sender, from, to, value, data, operatorData);
        return partition;
    }

    // ============ ERC-1400: Operators ============

    function authorizeOperator(address operator) external {
        _globalOperators[operator] = true;
        emit AuthorizedOperator(operator, msg.sender);
    }

    function revokeOperator(address operator) external {
        _globalOperators[operator] = false;
        emit RevokedOperator(operator, msg.sender);
    }

    function authorizeOperatorByPartition(bytes32 partition, address operator) external {
        _partitionOperators[partition][operator][msg.sender] = true;
        emit AuthorizedOperatorByPartition(partition, operator, msg.sender);
    }

    function revokeOperatorByPartition(bytes32 partition, address operator) external {
        _partitionOperators[partition][operator][msg.sender] = false;
        emit RevokedOperatorByPartition(partition, operator, msg.sender);
    }

    function isOperator(address operator, address tokenHolder) external view returns (bool) {
        return _isOperatorFor(operator, tokenHolder);
    }

    function isOperatorForPartition(bytes32 partition, address operator, address tokenHolder) external view returns (bool) {
        return _isOperatorForPartition(partition, operator, tokenHolder);
    }

    function isControllable() external pure returns (bool) { return true; }

    // ============ ERC-1400: Issuance ============

    function isIssuable() external view returns (bool) { return issuable; }

    function issue(address to, uint256 value, bytes calldata data) external onlyOwner {
        _issueByPartition(PARTITION_UNLOCKED, msg.sender, to, value, data, "");
    }

    function issueByPartition(bytes32 partition, address to, uint256 value, bytes calldata data) external onlyOwner {
        _issueByPartition(partition, msg.sender, to, value, data, "");
    }

    /// @notice Permanently disable issuance
    function finalizeIssuance() external onlyOwner {
        issuable = false;
    }

    // ============ ERC-1400: Redemption ============

    function redeem(uint256 value, bytes calldata data) external {
        _redeemByPartition(PARTITION_UNLOCKED, msg.sender, msg.sender, value, data, "");
    }

    function redeemFrom(address from, uint256 value, bytes calldata data) external {
        if (!_isOperatorFor(msg.sender, from)) revert NotOperator();
        _redeemByPartition(PARTITION_UNLOCKED, msg.sender, from, value, data, "");
    }

    function redeemByPartition(bytes32 partition, uint256 value, bytes calldata data) external {
        _redeemByPartition(partition, msg.sender, msg.sender, value, data, "");
    }

    function operatorRedeemByPartition(bytes32 partition, address from, uint256 value, bytes calldata operatorData) external {
        if (!_isOperatorForPartition(partition, msg.sender, from)) revert NotOperator();
        _redeemByPartition(partition, msg.sender, from, value, "", operatorData);
    }

    // ============ Admin ============

    function setKYCRegistry(address registry_) external onlyOwner {
        if (registry_ == address(0)) revert ZeroAddress();
        kycRegistry = registry_;
        emit KYCRegistryUpdated(registry_);
    }

    /// @notice Move tokens between partitions (e.g., lock/unlock for vesting)
    function moveByPartition(bytes32 fromPartition, bytes32 toPartition, address holder, uint256 value) external onlyOwner {
        if (_partitionBalances[fromPartition][holder] < value) revert InsufficientPartitionBalance();
        _partitionBalances[fromPartition][holder] -= value;
        _addToPartition(toPartition, holder, value);
        emit ChangedPartition(fromPartition, toPartition, value);
    }

    event ChangedPartition(bytes32 indexed fromPartition, bytes32 indexed toPartition, uint256 value);

    function proxyAdmin() external view returns (address) { return _proxyAdmin; }

    // ============ Internal ============

    function _canTransfer(address from, address to, uint256 value) internal view returns (bytes1, bytes32) {
        if (paused()) return (TRANSFERS_HALTED, bytes32("paused"));
        if (!IKYCRegistry(kycRegistry).isVerified(from)) return (INVALID_SENDER,   bytes32("sender not KYC"));
        if (!IKYCRegistry(kycRegistry).isVerified(to))   return (INVALID_RECEIVER, bytes32("receiver not KYC"));
        if (balanceOf(from) < value)                      return (INSUFFICIENT_BALANCE, bytes32("insufficient balance"));
        return (TRANSFER_SUCCESS, bytes32(0));
    }

    function _erc1400Transfer(bytes32 partition, address operator, address from, address to, uint256 value, bytes memory data, bytes memory operatorData) internal {
        if (partition == PARTITION_LOCKED) revert TransferRestricted(FUNDS_LOCKED);
        if (partition != PARTITION_UNLOCKED) revert InvalidPartition(partition);

        (bytes1 code,) = _canTransfer(from, to, value);
        if (code != TRANSFER_SUCCESS) revert TransferRestricted(code);

        if (_partitionBalances[PARTITION_UNLOCKED][from] < value) revert InsufficientPartitionBalance();
        _partitionBalances[PARTITION_UNLOCKED][from] -= value;
        _addToPartition(PARTITION_UNLOCKED, to, value);

        _transfer(from, to, value);
        emit TransferByPartition(partition, operator, from, to, value, data, operatorData);
    }

    function _issueByPartition(bytes32 partition, address operator, address to, uint256 value, bytes memory data, bytes memory operatorData) internal {
        if (!issuable) revert NotIssuable();
        if (to == address(0)) revert ZeroAddress();
        if (maxSupply > 0 && totalSupply() + value > maxSupply) revert NotIssuable(); // cap enforced
        _addToPartition(partition, to, value);
        _mint(to, value);
        emit IssuedByPartition(partition, operator, to, value, data, operatorData);
        emit Issued(operator, to, value, data);
    }

    function _redeemByPartition(bytes32 partition, address operator, address from, uint256 value, bytes memory data, bytes memory operatorData) internal {
        if (_partitionBalances[partition][from] < value) revert InsufficientPartitionBalance();
        _partitionBalances[partition][from] -= value;
        _burn(from, value);
        emit RedeemedByPartition(partition, operator, from, value, operatorData);
        emit Redeemed(operator, from, value, data);
    }

    function _addToPartition(bytes32 partition, address holder, uint256 value) internal {
        if (_partitionBalances[partition][holder] == 0) {
            _holderPartitions[holder].push(partition);
        }
        _partitionBalances[partition][holder] += value;
    }

    function _isOperatorFor(address operator, address holder) internal view returns (bool) {
        return operator == holder || _globalOperators[operator] || operator == owner();
    }

    function _isOperatorForPartition(bytes32 partition, address operator, address holder) internal view returns (bool) {
        return _isOperatorFor(operator, holder) || _partitionOperators[partition][operator][holder];
    }

    /// @dev Override ERC-20 transfer to enforce KYC — catches direct transfer() calls
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            (bytes1 code,) = _canTransfer(from, to, amount);
            if (code != TRANSFER_SUCCESS) revert TransferRestricted(code);
        }
        super._update(from, to, amount);
    }

    /// @dev Stub — Pausable not inherited to keep contract lean; owner can add if needed
    function paused() internal pure returns (bool) { return false; }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }
}

interface IKYCRegistry {
    function isVerified(address account) external view returns (bool);
}
