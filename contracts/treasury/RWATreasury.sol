// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RWATreasury
 * @notice Unified fee receiver with configurable distribution splits
 */
contract RWATreasury is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidBps();
    error OnlyProxyAdmin();

    struct Split {
        address recipient;
        uint256 bps;
    }

    address private immutable _proxyAdmin;
    uint256 public constant BPS = 10000;

    Split[] public splits;

    event SplitsUpdated(address[] recipients, uint256[] bps);
    event FundsDistributed(address indexed token, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address[] memory recipients_,
        uint256[] memory bps_
    ) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        
        __Ownable_init(owner_);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _setSplits(recipients_, bps_);
    }

    function distribute(address token) external nonReentrant {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) return;

        for (uint256 i = 0; i < splits.length; i++) {
            uint256 amount = (balance * splits[i].bps) / BPS;
            if (amount > 0) {
                IERC20(token).safeTransfer(splits[i].recipient, amount);
            }
        }

        emit FundsDistributed(token, balance);
    }

    function setSplits(address[] memory recipients_, uint256[] memory bps_) external onlyOwner {
        _setSplits(recipients_, bps_);
    }

    function _setSplits(address[] memory recipients_, uint256[] memory bps_) internal {
        if (recipients_.length != bps_.length || recipients_.length == 0) revert InvalidBps();

        uint256 total;
        delete splits;

        for (uint256 i = 0; i < recipients_.length; i++) {
            if (recipients_[i] == address(0)) revert ZeroAddress();
            splits.push(Split(recipients_[i], bps_[i]));
            total += bps_[i];
        }

        if (total != BPS) revert InvalidBps();

        emit SplitsUpdated(recipients_, bps_);
    }

    function getSplits() external view returns (Split[] memory) {
        return splits;
    }

    function proxyAdmin() external view returns (address) { return _proxyAdmin; }
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }
}
