# Basenames Module

Production-quality Solidity module that lets any smart contract easily register and manage its own Basename (primary `name.base.eth`) on Base mainnet.

## Features

- Register a basename directly from your contract
- Automatically set the primary (reverse) record
- Set forward resolution (`name.base.eth` → contract address)
- Works for both new registrations and existing names
- Supports mainnet + easy testnet overrides
- No external dependencies

## Installation

Add this module to your project:

```bash
forge install mykclawd/basenames-module
```

Or copy the `src/` directory into your project.

## Usage

### 1. Inherit from `BasenameRegistrar`

> ⚠️ **Access control required.** `_registerBasename` and `_setPrimaryBasename` are `internal` functions — they cannot be called directly from outside your contract. However, **any public/external function you write that calls them must be protected by access control** (e.g. `onlyOwner`). Without it:
> - Anyone could call your contract and burn its ETH registering an unwanted name
> - Anyone could overwrite your primary name

```solidity
import {BasenameRegistrar} from "basenames-module/src/BasenameRegistrar.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MyContract is BasenameRegistrar, Ownable {
    constructor() BasenameRegistrar(address(0), address(0), address(0)) Ownable(msg.sender) {}

    /// @notice Register a basename. Only the owner can call this.
    function setupBasename(string memory name) external payable onlyOwner {
        _registerBasename(name, 365 days);
    }

    /// @notice Update primary name. Only the owner can call this.
    function changePrimaryName(string memory newName) external onlyOwner {
        _setPrimaryBasename(newName);
    }
}
```

### 2. Fund the contract and register

```solidity
// Option A: Send ETH when calling
myContract.setupBasename{value: 0.02 ether}();

// Option B: Send ETH to the contract first
payable(address(myContract)).transfer(0.02 ether);
myContract.setupBasename();
```

### 3. After registration

- `myapp.base.eth` will resolve to your contract address
- Your contract address will have primary name `myapp.base.eth`

## How Much ETH Do I Need?

Use `getBasenamePrice(name, duration)` to query the exact cost:

```solidity
uint256 price = myContract.getBasenamePrice("myapp", 365 days);
```

Typical cost for a normal name is between **0.001 – 0.01 ETH** per year (base price + premium).

## Mainnet vs Testnet

By default, the contract uses Base mainnet addresses.

For testnets (Base Sepolia), pass the testnet addresses in the constructor:

```solidity
constructor() BasenameRegistrar(
    0xTestRegistrarController,
    0xTestReverseRegistrar,
    0xTestL2Resolver
) {}
```

## Internal Functions

| Function | Description |
|----------|-------------|
| `_registerBasename(name, duration)` | Registers + sets primary + forward record |
| `_setPrimaryBasename(name)` | Updates primary name (name must already be owned) |
| `getBasenamePrice(name, duration)` | View function for pricing |

## Events

- `BasenameRegistered(string name, address contractAddress, uint256 duration)`
- `PrimaryBasenameSet(string name, address contractAddress)`

## Security Considerations

**Access control is your responsibility.** The internal functions in this module are safe, but you must restrict who can trigger them:

| Risk | Cause | Fix |
|------|-------|-----|
| ETH drained | Unprotected public wrapper around `_registerBasename` | Add `onlyOwner` or equivalent |
| Primary name hijacked | Unprotected public wrapper around `_setPrimaryBasename` | Add `onlyOwner` or equivalent |
| Name squatted before deploy | Front-running on deployment tx | Register name in constructor, or use CREATE2 to predict address first |

**Why can't a random person call `setName` on the ReverseRegistrar for your contract?**
The ReverseRegistrar only accepts calls where `msg.sender == addr` (the address being named), or where the caller is an approved operator. So an attacker cannot externally set a primary name for your contract address — only your contract itself can do that by calling `setName` from within. This means the attack vector is exclusively through an unprotected wrapper you expose.

## Technical Details

- Uses the official Basenames contracts on Base
- Automatically refunds excess ETH after registration
- Implements full ENS namehash in pure Solidity
- Compatible with `Ownable` patterns (ReverseRegistrar checks owner)

## License

MIT
