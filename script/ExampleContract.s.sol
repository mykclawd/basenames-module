// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {BasenameRegistrar} from "../src/BasenameRegistrar.sol";

/**
 * @notice Example contract showing correct usage of BasenameRegistrar.
 * @dev Access control is REQUIRED on any function that calls _registerBasename
 *      or _setPrimaryBasename. Without it, anyone could drain your contract's
 *      ETH or overwrite your primary name.
 *
 *      Pattern A: Ownable (most common)
 */
contract MyNamedContract is BasenameRegistrar {
    address public owner;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() BasenameRegistrar(address(0), address(0), address(0)) {
        owner = msg.sender;
    }

    /**
     * @notice Register a basename for this contract.
     * @dev Only callable by owner. Contract must hold enough ETH.
     *      Query getBasenamePrice() first to know how much to send.
     * @param name The label to register (e.g. "mycontract" → mycontract.base.eth)
     * @param duration Registration duration in seconds (minimum 365 days)
     */
    function initializeBasename(string memory name, uint256 duration)
        external
        payable
        onlyOwner
    {
        _registerBasename(name, duration);
    }

    /**
     * @notice Update the primary name for this contract.
     * @dev Only callable by owner. Name must already be registered and owned
     *      by this contract.
     */
    function updatePrimaryName(string memory newName) external onlyOwner {
        _setPrimaryBasename(newName);
    }
}

contract DeployExample is Script {
    function run() external {
        vm.startBroadcast();

        MyNamedContract myContract = new MyNamedContract();

        // Query price, then fund and register:
        // uint256 price = myContract.getBasenamePrice("mycontract", 365 days);
        // myContract.initializeBasename{value: price}("mycontract", 365 days);

        vm.stopBroadcast();
    }
}
