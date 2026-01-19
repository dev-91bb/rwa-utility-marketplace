// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IUUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

/**
 * @title HybridProxyAdmin
 * @notice Sole authority for UUPS upgrades - immune to MEV/CPI-MP attacks
 * @dev Uses Ownable2Step for secure two-step ownership transfer
 */
contract HybridProxyAdmin is Ownable2Step {
    error ZeroAddress();
    error NotContract(address addr);

    event UpgradeExecuted(address indexed proxy, address indexed implementation);

    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    function getPendingOwner() external view returns (address) {
        return pendingOwner();
    }

    function upgrade(address proxy, address newImplementation) external onlyOwner {
        _validateUpgrade(proxy, newImplementation);
        IUUPSUpgradeable(proxy).upgradeToAndCall(newImplementation, "");
        emit UpgradeExecuted(proxy, newImplementation);
    }

    function upgradeAndCall(
        address proxy,
        address newImplementation,
        bytes calldata data
    ) external payable onlyOwner {
        _validateUpgrade(proxy, newImplementation);
        IUUPSUpgradeable(proxy).upgradeToAndCall{value: msg.value}(newImplementation, data);
        emit UpgradeExecuted(proxy, newImplementation);
    }

    function _validateUpgrade(address proxy, address newImplementation) internal view {
        if (proxy == address(0) || newImplementation == address(0)) revert ZeroAddress();
        if (proxy.code.length == 0) revert NotContract(proxy);
        if (newImplementation.code.length == 0) revert NotContract(newImplementation);
    }
}
