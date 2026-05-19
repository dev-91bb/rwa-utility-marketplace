// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title PropertyRegistry
 * @notice Source of truth mapping propertyId → proxy address and listing status.
 * @dev Only the authorized factory can register new properties.
 *      Owner can update the factory address (e.g., after a factory upgrade).
 */
contract PropertyRegistry is Ownable2Step {
    error ZeroAddress();
    error EmptyPropertyId();
    error AlreadyRegistered(string propertyId);
    error NotRegistered(string propertyId);
    error OnlyFactory();

    enum Status { Active, Delisted, Sold }

    struct Property {
        address proxy;
        Status status;
        uint256 registeredAt;
    }

    address public factory;

    mapping(string => Property) private _properties;
    string[] private _propertyIds;

    event PropertyRegistered(string indexed propertyId, address indexed proxy);
    event StatusUpdated(string indexed propertyId, Status status);
    event FactoryUpdated(address indexed factory);

    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactory();
        _;
    }

    constructor(address owner_) Ownable(owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
    }

    function setFactory(address factory_) external onlyOwner {
        if (factory_ == address(0)) revert ZeroAddress();
        factory = factory_;
        emit FactoryUpdated(factory_);
    }

    function register(string calldata propertyId_, address proxy_) external onlyFactory {
        if (bytes(propertyId_).length == 0) revert EmptyPropertyId();
        if (_properties[propertyId_].proxy != address(0)) revert AlreadyRegistered(propertyId_);
        _properties[propertyId_] = Property(proxy_, Status.Active, block.timestamp);
        _propertyIds.push(propertyId_);
        emit PropertyRegistered(propertyId_, proxy_);
    }

    function setStatus(string calldata propertyId_, Status status_) external onlyOwner {
        if (_properties[propertyId_].proxy == address(0)) revert NotRegistered(propertyId_);
        _properties[propertyId_].status = status_;
        emit StatusUpdated(propertyId_, status_);
    }

    function getProperty(string calldata propertyId_) external view returns (Property memory) {
        if (_properties[propertyId_].proxy == address(0)) revert NotRegistered(propertyId_);
        return _properties[propertyId_];
    }

    /// @notice Returns all proxy addresses for batch operations (e.g., batchUpgrade)
    function getAllProxies() external view returns (address[] memory proxies) {
        proxies = new address[](_propertyIds.length);
        for (uint256 i = 0; i < _propertyIds.length; i++) {
            proxies[i] = _properties[_propertyIds[i]].proxy;
        }
    }

    function totalProperties() external view returns (uint256) {
        return _propertyIds.length;
    }
}
