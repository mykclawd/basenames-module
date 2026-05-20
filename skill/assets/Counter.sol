// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BasenameRegistrar} from "basenames-module/src/BasenameRegistrar.sol";

/// @title Counter
/// @notice Minimal example contract using basenames-module.
///         Anyone can increment. Owner manages the Basename.
contract Counter is BasenameRegistrar {
    address public owner;
    uint256 public count;

    error NotOwner();
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    event CountIncremented(address indexed by, uint256 newCount);

    constructor(address owner_)
        // (0,0,0) = use Base mainnet defaults
        BasenameRegistrar(address(0), address(0), address(0))
    {
        owner = owner_;
    }

    // ── Counter ──────────────────────────────────────────────────

    function increment() external {
        count += 1;
        emit CountIncremented(msg.sender, count);
    }

    function getCount() external view returns (uint256) {
        return count;
    }

    // ── Basename ──────────────────────────────────────────────────

    /// @notice Step 1: Register a Basename. Send ETH with this call.
    /// @param name     e.g. "mycontract" → mycontract.base.eth
    /// @param duration seconds; minimum 31536000 (1 year)
    function registerBasename(string memory name, uint256 duration)
        external payable onlyOwner
    {
        _registerBasename(name, duration);
        // Sets: address(this) → name.base.eth  (reverse / primary)
    }

    /// @notice Step 2: Set forward addr record. No ETH needed.
    /// @param name The same label used in registerBasename
    function setForwardResolution(string memory name) external onlyOwner {
        _setForwardResolution(name);
        // Sets: name.base.eth → address(this)  (forward)
    }

    /// @notice Update the primary name (if the contract already owns it).
    function setPrimaryBasename(string memory name) external onlyOwner {
        _setPrimaryBasename(name);
    }

    // ── Ownership ─────────────────────────────────────────────────

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    receive() external payable override {}
}
