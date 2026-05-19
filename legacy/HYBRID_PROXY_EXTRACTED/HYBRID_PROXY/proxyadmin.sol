// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title ProxyAdmin
 * @dev Admin contract for UUPS proxies. Only owner can trigger upgrades.
 */
contract ProxyAdmin is Ownable {
    constructor(address owner_) Ownable(owner_) {}

    function upgrade(address proxy, address implementation) external onlyOwner {
        UUPSUpgradeable(proxy).upgradeToAndCall(implementation, "");
    }

    function upgradeAndCall(
        address proxy,
        address implementation,
        bytes calldata data
    ) external payable onlyOwner {
        UUPSUpgradeable(proxy).upgradeToAndCall{value: msg.value}(implementation, data);
    }
}
