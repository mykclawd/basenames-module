// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IReverseRegistrar
 * @notice Interface for the ENS ReverseRegistrar used for primary names
 */
interface IReverseRegistrar {
    /**
     * @notice Sets the primary name for the calling address
     */
    function setName(string memory name) external returns (bytes32);

    /**
     * @notice Sets the primary name for a specific address
     * @dev Caller must be authorized (owner or the address itself)
     */
    function setNameForAddr(
        address addr,
        address owner,
        address resolver,
        string memory name
    ) external returns (bytes32);

    /**
     * @notice Claims reverse record ownership
     */
    function claim(address owner) external returns (bytes32);
}
