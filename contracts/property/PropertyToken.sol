// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PropertyToken
 * @notice Fractional property ownership token with KYC transfer restrictions.
 *         One deployed implementation shared by all ERC1967Proxy instances.
 * @dev Hybrid proxy pattern: immutable _proxyAdmin set in constructor, immune to front-running.
 */
contract PropertyToken is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    error ZeroAddress();
    error OnlyProxyAdmin();
    error TransferRestricted(address from, address to);

    address private immutable _proxyAdmin;
    uint256 public constant VERSION = 1;

    /// @notice KYC registry — shared across all property tokens
    address public kycRegistry;

    /// @notice Property metadata
    string public propertyId;
    uint256 public totalValueUSD;   // property valuation in USD cents
    uint256 public tokenPriceUSD;   // price per token in USD cents

    event KYCRegistryUpdated(address indexed registry);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

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
        propertyId = propertyId_;
        totalValueUSD = totalValueUSD_;
        tokenPriceUSD = tokenPriceUSD_;
        kycRegistry = kycRegistry_;
        _mint(owner_, totalSupply_);
    }

    function proxyAdmin() external view returns (address) {
        return _proxyAdmin;
    }

    function setKYCRegistry(address registry_) external onlyOwner {
        if (registry_ == address(0)) revert ZeroAddress();
        kycRegistry = registry_;
        emit KYCRegistryUpdated(registry_);
    }

    /// @dev Transfer restriction hook — checks KYC on both sender and receiver
    function _update(address from, address to, uint256 amount) internal override {
        // Minting (from == 0) and burning (to == 0) bypass KYC
        if (from != address(0) && to != address(0)) {
            if (!IKYCRegistry(kycRegistry).isVerified(from)) revert TransferRestricted(from, to);
            if (!IKYCRegistry(kycRegistry).isVerified(to)) revert TransferRestricted(from, to);
        }
        super._update(from, to, amount);
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }
}

interface IKYCRegistry {
    function isVerified(address account) external view returns (bool);
}
