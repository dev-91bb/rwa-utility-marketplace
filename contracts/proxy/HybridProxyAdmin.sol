// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IUUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

interface IPropertyBeacon {
    function upgradeTo(address newImplementation) external;
}

/**
 * @title HybridProxyAdmin
 * @notice Shared upgrade authority for all UUPS proxies - MEV/CPI-MP protected
 * @dev Uses Ownable2Step for secure two-step ownership transfer
 */
contract HybridProxyAdmin is Ownable2Step {
    error ZeroAddress();
    error NotContract(address addr);

    event UpgradeExecuted(address indexed proxy, address indexed implementation);
    event BeaconUpgradeExecuted(address indexed beacon, address indexed implementation);

    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    // ============ UUPS Proxy Upgrades ============

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

    function batchUpgrade(address[] calldata proxies, address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
        if (newImplementation.code.length == 0) revert NotContract(newImplementation);
        for (uint256 i = 0; i < proxies.length; i++) {
            if (proxies[i] == address(0)) revert ZeroAddress();
            if (proxies[i].code.length == 0) revert NotContract(proxies[i]);
            IUUPSUpgradeable(proxies[i]).upgradeToAndCall(newImplementation, "");
            emit UpgradeExecuted(proxies[i], newImplementation);
        }
    }

    // ============ Beacon Upgrade (upgrades all PropertyToken proxies at once) ============

    /// @notice Upgrade all PropertyToken BeaconProxies by updating the beacon implementation.
    ///         One call upgrades every property on the platform simultaneously.
    function upgradeBeacon(address beacon, address newImplementation) external onlyOwner {
        if (beacon == address(0) || newImplementation == address(0)) revert ZeroAddress();
        if (beacon.code.length == 0) revert NotContract(beacon);
        if (newImplementation.code.length == 0) revert NotContract(newImplementation);
        IPropertyBeacon(beacon).upgradeTo(newImplementation);
        emit BeaconUpgradeExecuted(beacon, newImplementation);
    }

    function _validateUpgrade(address proxy, address newImplementation) internal view {
        if (proxy == address(0) || newImplementation == address(0)) revert ZeroAddress();
        if (proxy.code.length == 0) revert NotContract(proxy);
        if (newImplementation.code.length == 0) revert NotContract(newImplementation);
    }
}
