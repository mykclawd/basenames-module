// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {BasenameRegistrar} from "../src/BasenameRegistrar.sol";

contract MyNamedContract is BasenameRegistrar {
    constructor() BasenameRegistrar(address(0), address(0), address(0)) {}

    function initializeBasename() external payable {
        // Register "mycontract.base.eth" for 1 year
        _registerBasename("mycontract", 365 days);
    }

    function updatePrimaryName(string memory newName) external {
        _setPrimaryBasename(newName);
    }
}

contract DeployExample is Script {
    function run() external {
        vm.startBroadcast();

        MyNamedContract myContract = new MyNamedContract();

        // Fund and register in one go (example)
        // myContract.initializeBasename{value: 0.01 ether}();

        vm.stopBroadcast();
    }
}
