// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title HybridUpgradeableToken
 * @dev ERC20 + UUPS with immutable ProxyAdmin for MEV/CPI-MP protection.
 *      ProxyAdmin is set at deploy time - cannot be changed even if initialize() is front-run.
 */
contract HybridUpgradeableToken is
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    error ZeroAddress();
    error OnlyProxyAdmin();

    /// @dev Immutable - set in constructor, immune to front-running
    address private immutable _proxyAdmin;

    /// @dev Version for upgrade tracking
    uint256 public constant VERSION = 1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialOwner_
    ) external initializer {
        if (initialOwner_ == address(0)) revert ZeroAddress();
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __Ownable_init(initialOwner_);
        __UUPSUpgradeable_init();
    }

    function proxyAdmin() external view returns (address) {
        return _proxyAdmin;
    }

    function _authorizeUpgrade(address) internal override view {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
