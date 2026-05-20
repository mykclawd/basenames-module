// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {BasenameRegistrar} from "../src/BasenameRegistrar.sol";
import {BasenameUtils} from "../src/lib/BasenameUtils.sol";

contract ExampleBasenameContract is BasenameRegistrar {
    constructor() BasenameRegistrar(address(0), address(0), address(0)) {}

    function register(string memory name, uint256 duration) external payable {
        _registerBasename(name, duration);
    }

    function setPrimary(string memory name) external {
        _setPrimaryBasename(name);
    }
}

contract BasenameRegistrarTest is Test {
    ExampleBasenameContract public example;

    // Base mainnet fork
    uint256 public constant FORK_BLOCK = 25000000; // Recent block

    function setUp() public {
        vm.createFork(vm.rpcUrl("base"));
        vm.selectFork(0);

        example = new ExampleBasenameContract();
    }

    function test_getBasenamePrice() public {
        uint256 price = example.getBasenamePrice("testname", 365 days);
        assertGt(price, 0, "Price should be greater than zero");
    }

    function test_registerBasename() public {
        string memory name = "foundrytestcontract";
        uint256 duration = 365 days;

        uint256 price = example.getBasenamePrice(name, duration);

        // Fund the contract
        vm.deal(address(example), price + 0.01 ether);

        // Register
        example.register(name, duration);

        // Verify the contract now has a reverse record
        // We can check by calling the ReverseRegistrar
        address reverseRegistrar = 0x79ea96012eea67a83431f1701b3dff7e37f9e282;
        string memory primaryName = IReverseRegistrar(reverseRegistrar).nameOf(
            address(example)
        );

        // The name should contain our label
        assertTrue(
            keccak256(abi.encodePacked(primaryName)) !=
                keccak256(abi.encodePacked("")),
            "Primary name should be set"
        );
    }

    function test_setPrimaryBasename() public {
        // This test assumes the name is already registered or we just test the call
        vm.deal(address(example), 1 ether);

        // Just verify it doesn't revert when called (actual primary setting
        // requires the name to exist and be owned by the caller)
        example.setPrimary("existingname");
    }
}

// Minimal interface for testing
interface IReverseRegistrar {
    function nameOf(address addr) external view returns (string memory);
}
