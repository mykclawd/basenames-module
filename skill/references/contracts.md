# Basenames Contract Addresses

## Base Mainnet

| Contract | Address | Notes |
|---|---|---|
| RegistrarController (active) | `0xa7d2607c6BD39Ae9521e514026CBB078405Ab322` | UpgradeableRegistrarController proxy — use this, NOT 0x4cCb... |
| RegistrarController (deprecated) | `0x4cCb0BB02FCABA27e82a56646E81d8c5bC4119a5` | No longer approved by BaseRegistrar — do not use |
| BaseRegistrar (ERC721) | `0x03c4738ee98ae44591e1a4a4f3cab6641d95dd9a` | Holds name ownership tokens |
| Registry | `0xb94704422c2a1e396835a571837aa5ae53285a95` | ENS-style registry |
| ReverseRegistrar | `0x79EA96012eEa67A83431F1701B3dFf7e37F9E282` | Sets address → name reverse record |
| L2Resolver | `0xC6d566A56A1aFf6508b41f6c90ff131615583BCD` | Stores addr, name, and text records |

## Base Sepolia (testnet)

| Contract | Address |
|---|---|
| RegistrarController | `0x49ae3cc2e3aa768b1e5654f5d3c6002144a59581` |
| BaseRegistrar | `0xa0c70ec36c010b55e3c434d6c6ebeec50c705794` |
| Registry | `0x1493b2567056c2181630115660963E13A8E32735` |
| ReverseRegistrar | `0x876eF94ce0773052a2f81921E70FF25a5e76841f` |
| L2Resolver | `0x6533C94869D28fAA8dF77cc63f9e2b2D6Cf77eBA` |

## Key constants

- `BASE_ETH_NODE` (namehash of `base.eth`): `0xff1e3c0eb00ec714e34b6114125fbde1dea2f24a72fbf672e7b7fd5690328e10`
- Minimum registration duration: `31536000` seconds (365 days)
- ETH cointype (for setAddr): `60`

## Known gotchas

- The deprecated RegistrarController (`0x4cCb...`) is no longer approved by BaseRegistrar — calling `register()` on it reverts with `OnlyController()`
- The upgraded controller has a different `RegisterRequest` struct with 3 extra fields: `coinTypes (uint256[])`, `referralExpiry (uint256)`, `referralData (bytes)` — pass empty/zero values for standard registrations
- The L2Resolver's `registrarController` slot points to the MigrationController (`0x8d5ef54...`), not the active controller — so `setAddr` in the registration `data[]` array will revert; set forward resolution separately via `_setForwardResolution()`
- Checking `address(this).balance` before registration breaks gas estimation — the registrar handles insufficient payment itself
