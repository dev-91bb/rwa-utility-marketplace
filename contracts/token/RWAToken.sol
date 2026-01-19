// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RWAToken
 * @notice BEP-20 utility token for RWA Marketplace with Hybrid Proxy pattern
 * @dev Immutable _proxyAdmin set in constructor - immune to front-running
 */
contract RWAToken is
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    error ZeroAddress();
    error OnlyProxyAdmin();

    address private immutable _proxyAdmin;
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
        uint256 initialSupply_,
        address owner_
    ) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        __ERC20_init(name_, symbol_);
        __ERC20Burnable_init();
        __ERC20Permit_init(name_);
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        _mint(owner_, initialSupply_);
    }

    function proxyAdmin() external view returns (address) {
        return _proxyAdmin;
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
