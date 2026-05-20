# basenames-module

A Solidity abstract contract that lets any smart contract register and own a primary [Basename](https://www.base.org/names) (`name.base.eth`) on Base mainnet.

## Live Example

[`counter.base.eth`](https://www.base.org/name/counter) → [`0xa31cc82CC569617DBf8de092A17204e43a4f72d1`](https://basescan.org/address/0xa31cc82cc569617dbf8de092a17204e43a4f72d1)

A public counter contract on Base that inherited this module and registered `counter.base.eth`. Anyone can increment the counter; only the owner can manage its basename.
Source: [mykclawd/basename-counter](https://github.com/mykclawd/basename-counter)

---

## Installation

```bash
forge install mykclawd/basenames-module
```

Or copy `src/` into your project.

---

## Usage

### 1. Inherit `BasenameRegistrar`

> ⚠️ **Access control required.** `_registerBasename` and `_setPrimaryBasename` are `internal` — they cannot be called from outside. Any public wrapper you write **must be protected** (e.g. `onlyOwner`). Without access control, anyone could burn your contract's ETH or overwrite your primary name.

```solidity
import {BasenameRegistrar} from "basenames-module/src/BasenameRegistrar.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MyContract is BasenameRegistrar, Ownable {
    constructor()
        BasenameRegistrar(address(0), address(0), address(0))
        Ownable(msg.sender)
    {}

    /// @notice Register a basename. Only the owner can call this.
    /// @param name  The label to register (e.g. "myapp" → myapp.base.eth)
    /// @param duration  Seconds to register for (minimum 31536000 = 1 year)
    function setupBasename(string memory name, uint256 duration)
        external
        payable
        onlyOwner
    {
        _registerBasename(name, duration);
    }

    /// @notice Update the primary name (name must already be owned by this contract).
    function changePrimaryName(string memory newName) external onlyOwner {
        _setPrimaryBasename(newName);
    }
}
```

### 2. Check the price, then register

```solidity
// On-chain price check
uint256 price = myContract.getBasenamePrice("myapp", 365 days);

// Send slightly more than price — the module refunds the excess
myContract.setupBasename{value: price + 0.0001 ether}("myapp", 365 days);
```

Or via `cast`:

```bash
# Check price (returns wei)
cast call <YOUR_CONTRACT> \
  "getBasenamePrice(string,uint256)(uint256)" "myapp" "31536000" \
  --rpc-url https://mainnet.base.org

# Register
cast send <YOUR_CONTRACT> \
  "setupBasename(string,uint256)" "myapp" "31536000" \
  --value 0.001ether \
  --rpc-url https://mainnet.base.org \
  --private-key <your-key>
```

### 3. What happens after registration

- `myapp.base.eth` → your contract address (primary name set ✓)
- Your contract address → `myapp.base.eth` (reverse record set ✓)

Forward resolution (so `myapp.base.eth` resolves to your address in explorers) requires separately calling `setAddr` on the L2Resolver with the namehash — or it will be available once the basename app propagates the reverse record.

---

## API

| Function | Visibility | Description |
|---|---|---|
| `_registerBasename(name, duration)` | `internal` | Registers `name.base.eth`, sets primary name, refunds excess ETH |
| `_setPrimaryBasename(name)` | `internal` | (Re)sets primary name for an already-owned name |
| `getBasenamePrice(name, duration)` | `public view` | Returns total cost in wei |

---

## Real-world example: Counter contract

[`counter.base.eth`](https://www.base.org/name/counter) is a live demonstration. The full source:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BasenameRegistrar} from "basenames-module/src/BasenameRegistrar.sol";

contract Counter is BasenameRegistrar {
    address public owner;
    uint256 public count;

    error NotOwner();
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    constructor(address owner_)
        BasenameRegistrar(address(0), address(0), address(0))
    {
        owner = owner_;
    }

    /// @notice Anyone can increment
    function increment() external {
        count += 1;
    }

    /// @notice Read the count
    function getCount() external view returns (uint256) {
        return count;
    }

    /// @notice Owner registers a basename for this contract
    function registerBasename(string memory name, uint256 duration)
        external payable onlyOwner
    {
        _registerBasename(name, duration);
    }

    /// @notice Owner updates the primary basename
    function setPrimaryBasename(string memory name) external onlyOwner {
        _setPrimaryBasename(name);
    }
}
```

Deployed at [`0xa31cc82CC569617DBf8de092A17204e43a4f72d1`](https://basescan.org/address/0xa31cc82cc569617dbf8de092a17204e43a4f72d1) on Base.
The owner called `registerBasename("counter", 31536000)` with `0.001 ETH` — and the contract now owns `counter.base.eth`.

---

## Mainnet contract addresses

| Contract | Address |
|---|---|
| RegistrarController (active) | `0xa7d2607c6BD39Ae9521e514026CBB078405Ab322` |
| ReverseRegistrar | `0x79EA96012eEa67A83431F1701B3dFf7e37F9E282` |
| L2Resolver | `0xC6d566A56A1aFf6508b41f6c90ff131615583BCD` |

Pass `(address(0), address(0), address(0))` to the constructor to use these mainnet defaults.

## Testnet (Base Sepolia)

Pass the Sepolia addresses in the constructor:

```solidity
constructor() BasenameRegistrar(
    0x49ae3cc2e3aa768b1e5654f5d3c6002144a59581, // RegistrarController
    0x876eF94ce0773052a2f81921E70FF25a5e76841f, // ReverseRegistrar
    0x6533C94869D28fAA8dF77cc63f9e2b2D6Cf77eBA  // L2Resolver
) {}
```

---

## Security considerations

| Risk | Cause | Fix |
|---|---|---|
| ETH drained | Unprotected public `_registerBasename` wrapper | Add `onlyOwner` or equivalent |
| Primary name hijacked | Unprotected public `_setPrimaryBasename` wrapper | Add `onlyOwner` or equivalent |
| Name squatted pre-deploy | Front-running on deployment tx | Register in constructor, or use CREATE2 to predict your address first |

**Why can't a random person set a primary name for your contract?**
The ReverseRegistrar only accepts `setName` when `msg.sender == the address being named`. Nobody external can call `setName` on behalf of your contract — only your contract itself can do it by calling `setName` from within its own execution context. The attack vector is solely through an unprotected public wrapper you expose.

---

## License

MIT
