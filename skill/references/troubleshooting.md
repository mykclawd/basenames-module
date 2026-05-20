# Troubleshooting

## "OnlyController()" revert (0x59907813)

**Cause:** Calling `register()` on the deprecated `RegistrarController` (`0x4cCb...`). That contract is no longer approved by `BaseRegistrar`.

**Fix:** Use `UpgradeableRegistrarController` (`0xa7d2...`). The module's `REGISTRAR_CONTROLLER` constant is already set to this.

## "exceeds max transaction gas limit" or "likely to fail"

**Cause 1:** The `_setForwardResolution` call computed the wrong namehash because `BASE_ETH_NODE` was incorrect. The resolver reverted on an unowned node, gas estimation failed.

**Fix:** Ensure you're using the latest module version. The correct `BASE_ETH_NODE` is `0xff1e3c0eb00ec714e34b6114125fbde1dea2f24a72fbf672e7b7fd5690328e10`.

**Cause 2:** `address(this).balance < price` check before the registration call. During gas estimation, the contract has 0 ETH so this check always reverts, giving MetaMask a garbage gas limit.

**Fix:** Remove the balance pre-check. Let the registrar's own `InsufficientValue()` handle underpayment. The module already does this correctly.

## Registration succeeds but forward resolution is wrong

**Cause:** The `data[]` field in `RegisterRequest` was used to call `setAddr` at registration time. The L2Resolver's `isAuthorised()` only allows the address stored in `resolver.registrarController` slot — which is the MigrationController (`0x8d5ef54...`), not the active UpgradeableRegistrarController. The setAddr call was rejected.

**Fix:** Register with `data = []` (empty), then call `_setForwardResolution(name)` as a separate transaction after registration.

## Forward resolution shows a different address

**Cause:** The name was previously owned by a different address, and the addr record was never updated after your contract took ownership.

**Fix:** Call `_setForwardResolution(name)` (or your public wrapper around it). This calls `resolver.setAddr(node, address(this))` — authorised because your contract is now the registry node owner.

## MetaMask shows "99 trillion ETH" in the value field

**Cause:** Basescan's `payableAmount` field takes ETH (not wei). If you paste the wei value from `getBasenamePrice()` into that field, MetaMask displays it as ETH.

**Fix:** Enter `0.001` (ETH) in the payableAmount field. The exact wei price from `getBasenamePrice()` is what gets forwarded; any excess is refunded automatically.

## Name shows as available but registration still reverts

**Cause:** Name was registered on the deprecated controller which is no longer tracked correctly, or the name was in a grace period.

**Fix:** Use `UpgradeableRegistrarController.available(name)` to check availability — this is the authoritative source.
