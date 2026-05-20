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

```solidity
import {BasenameRegistrar} from "basenames-module/src/BasenameRegistrar.sol";

contract MyContract is BasenameRegistrar {
    constructor() BasenameRegistrar(address(0), address(0), address(0)) {}

    function setupBasename() external payable {
        // Register "myapp.base.eth" for 1 year
        _registerBasename("myapp", 365 days);
    }

    function changePrimaryName(string memory newName) external {
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

## Technical Details

- Uses the official Basenames contracts on Base
- Automatically refunds excess ETH after registration
- Implements full ENS namehash in pure Solidity
- Compatible with `Ownable` patterns (ReverseRegistrar checks owner)

## License

MIT
