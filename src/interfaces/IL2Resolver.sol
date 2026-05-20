// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IL2Resolver
 * @notice Minimal interface for the L2Resolver used by Basenames
 */
interface IL2Resolver {
    /**
     * @notice Sets the address record for a name on a specific coin type
     * @param node The namehash of the name
     * @param coinType The coin type (60 for ETH/Base)
     * @param a The address to set
     */
    function setAddr(
        bytes32 node,
        uint256 coinType,
        address a
    ) external;

    /**
     * @notice Gets the address record
     */
    function addr(
        bytes32 node,
        uint256 coinType
    ) external view returns (address);
}
