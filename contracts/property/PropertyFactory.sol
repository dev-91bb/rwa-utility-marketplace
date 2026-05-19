// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

interface IPropertyRegistry {
    function register(string calldata propertyId, address proxy) external;
}

/**
 * @title PropertyFactory
 * @notice Deploys a BeaconProxy per property listing. All proxies share the same
 *         implementation via PropertyBeacon — one beacon upgrade updates all properties.
 */
contract PropertyFactory is Ownable2Step {
    error ZeroAddress();
    error EmptyPropertyId();

    address public immutable beacon;
    address public immutable registry;

    event PropertyDeployed(string indexed propertyId, address indexed proxy);

    constructor(address beacon_, address registry_, address owner_) Ownable(owner_) {
        if (beacon_ == address(0) || registry_ == address(0) || owner_ == address(0))
            revert ZeroAddress();
        beacon   = beacon_;
        registry = registry_;
    }

    /**
     * @notice Deploy a new PropertyToken BeaconProxy and register it.
     * @param name_          ERC20 name
     * @param symbol_        ERC20 symbol
     * @param propertyId_    Unique property identifier
     * @param totalSupply_   Total fractional tokens to mint
     * @param totalValueUSD_ Property valuation in USD cents
     * @param tokenPriceUSD_ Price per token in USD cents
     * @param kycRegistry_   Shared KYC registry address
     * @param tokenOwner_    Address that receives the minted supply
     */
    function deployProperty(
        string calldata name_,
        string calldata symbol_,
        string calldata propertyId_,
        uint256 totalSupply_,
        uint256 totalValueUSD_,
        uint256 tokenPriceUSD_,
        address kycRegistry_,
        address tokenOwner_
    ) external onlyOwner returns (address proxy) {
        if (bytes(propertyId_).length == 0) revert EmptyPropertyId();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string,string,uint256,uint256,uint256,address,address)",
            name_, symbol_, propertyId_, totalSupply_, totalValueUSD_, tokenPriceUSD_,
            kycRegistry_, tokenOwner_
        );

        proxy = address(new BeaconProxy(beacon, initData));
        IPropertyRegistry(registry).register(propertyId_, proxy);
        emit PropertyDeployed(propertyId_, proxy);
    }
}
