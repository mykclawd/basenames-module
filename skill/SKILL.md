---
name: basenames-module
description: "Give any Base smart contract a human-readable .base.eth name using the basenames-module. Covers contract setup, registration, forward/reverse resolution, and rescue flows."
---

# Basenames Module Skill

Use this skill when a user wants their smart contract to own a Basename (`name.base.eth`) on Base. The module is a Solidity abstract contract — contracts inherit it and call internal functions to register and manage their name.

## Module location

GitHub: `mykclawd/basenames-module` (forge install)
Source: `src/BasenameRegistrar.sol`

## Internal functions (inherit, do not call directly)

- `_registerBasename(name, duration)` — payable; registers name, sets reverse record (address → name)
- `_setForwardResolution(name)` — sets forward record (name → address); call separately after registration
- `_setPrimaryBasename(name)` — updates reverse record for a name already owned by the contract
- `getBasenamePrice(name, duration)` — public view; returns cost in wei

## Workflow

### Step 1 — Add the module to a contract

```solidity
import {BasenameRegistrar} from "basenames-module/src/BasenameRegistrar.sol";

contract MyContract is BasenameRegistrar {
    address public owner;
    error NotOwner();
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    constructor(address owner_)
        // Pass (0,0,0) for Base mainnet; pass Sepolia addresses for testnet
        BasenameRegistrar(address(0), address(0), address(0))
    {
        owner = owner_;
    }

    // Step 1 tx — payable, send ETH
    function registerBasename(string memory name, uint256 duration)
        external payable onlyOwner
    {
        _registerBasename(name, duration);
    }

    // Step 2 tx — no ETH needed
    function setForwardResolution(string memory name) external onlyOwner {
        _setForwardResolution(name);
    }
}
```

> **Access control is mandatory.** These are `internal` functions. Any public wrapper must be protected (onlyOwner or equivalent) — an unprotected wrapper lets anyone drain the contract's ETH or overwrite its name.

### Step 2 — Install and build

```bash
forge install mykclawd/basenames-module
forge build
```

### Step 3 — Check price

```bash
cast call <CONTRACT> \
  "getBasenamePrice(string,uint256)(uint256)" "<name>" "31536000" \
  --rpc-url https://mainnet.base.org
```

Returns wei. Send slightly more (excess is refunded).

### Step 4 — Register (tx 1, payable)

```bash
cast send <CONTRACT> \
  "registerBasename(string,uint256)" "<name>" "31536000" \
  --value 0.001ether \
  --rpc-url https://mainnet.base.org \
  --private-key <owner-key>
```

Sets: `address(this)` → `name.base.eth` (reverse / primary name)

### Step 5 — Set forward resolution (tx 2, no ETH)

```bash
cast send <CONTRACT> \
  "setForwardResolution(string)" "<name>" \
  --rpc-url https://mainnet.base.org \
  --private-key <owner-key>
```

Sets: `name.base.eth` → `address(this)` (forward)

After both txs: bidirectional resolution works in wallets and block explorers.

## Why two transactions?

Bundling registration and the resolver write in one tx causes wallet gas estimators to under-estimate gas (they simulate on a contract with 0 ETH, the balance check reverts, MetaMask shows "likely to fail"). Two separate txs each estimate cleanly.

## Rescue — fix stale forward resolution

If a contract already owns a name but the forward addr record is wrong (e.g. inherited from a prior owner):

```solidity
function fixForwardResolution(string memory name) external onlyOwner {
    _setForwardResolution(name); // sets name.base.eth → address(this)
}
```

Call this any time the contract owns the ENS node for that name.

## Testnet (Base Sepolia)

```solidity
constructor() BasenameRegistrar(
    0x49ae3cc2e3aa768b1e5654f5d3c6002144a59581, // RegistrarController
    0x876eF94ce0773052a2f81921E70FF25a5e76841f, // ReverseRegistrar
    0x6533C94869D28fAA8dF77cc63f9e2b2D6Cf77eBA  // L2Resolver
) {}
```

## Verification after registration

```bash
# Forward (name → address)
cast call 0xC6d566A56A1aFf6508b41f6c90ff131615583BCD \
  "addr(bytes32)(address)" <namehash> \
  --rpc-url https://mainnet.base.org

# Reverse (address → name) via ReverseRegistrar
cast call 0x79EA96012eEa67A83431F1701B3dFf7e37F9E282 \
  "node(address)(bytes32)" <contract-address> \
  --rpc-url https://mainnet.base.org
# then call L2Resolver.name(bytes32) on the returned node
```

## Live example

- Contract: `0x2287ECB162bC14d69f336541cEEfFf738f57d676`
- Name: `incrementer.base.eth`
- Basescan: https://basescan.org/address/0x2287ecb162bc14d69f336541ceefff738f57d676

See `references/contracts.md` for all mainnet contract addresses.
