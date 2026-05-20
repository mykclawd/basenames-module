// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IRegistrarController
 * @notice Interface for the Basenames RegistrarController contract
 */
interface IRegistrarController {
    struct Price {
        uint256 base;
        uint256 premium;
    }

    struct RegisterRequest {
        string name;
        address owner;
        uint256 duration;
        address resolver;
        bytes[] data;
        bool reverseRecord;
    }

    /**
     * @notice Returns the rent price for a name
     */
    function rentPrice(
        string memory name,
        uint256 duration
    ) external view returns (Price memory);

    /**
     * @notice Registers a new basename
     */
    function register(RegisterRequest calldata request) external payable;

    /**
     * @notice Returns the minimum registration duration
     */
    function minRegistrationDuration() external view returns (uint256);
}
