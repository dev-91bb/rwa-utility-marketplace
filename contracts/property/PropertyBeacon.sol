// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title PropertyBeacon
 * @notice Holds the single implementation address for all PropertyToken proxies.
 *         Upgrading this contract upgrades every PropertyToken on the platform in one tx.
 * @dev Owner should be HybridProxyAdmin for consistent upgrade authority.
 *      UpgradeableBeacon already has Ownable — we wrap with Ownable2Step for safety.
 */
contract PropertyBeacon is Ownable2Step {
    error ZeroAddress();
    error NotContract(address addr);

    UpgradeableBeacon public immutable beacon;

    event BeaconUpgraded(address indexed oldImpl, address indexed newImpl);

    constructor(address implementation_, address owner_) Ownable(owner_) {
        if (implementation_ == address(0)) revert ZeroAddress();
        if (implementation_.code.length == 0) revert NotContract(implementation_);
        // Deploy the beacon — its owner is this contract
        beacon = new UpgradeableBeacon(implementation_, address(this));
    }

    /// @notice Upgrade all PropertyToken proxies to a new implementation
    function upgradeTo(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
        if (newImplementation.code.length == 0) revert NotContract(newImplementation);
        address old = beacon.implementation();
        beacon.upgradeTo(newImplementation);
        emit BeaconUpgraded(old, newImplementation);
    }

    function implementation() external view returns (address) {
        return beacon.implementation();
    }
}
