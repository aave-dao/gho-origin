# GSM Upgrades

Before upgrading a GSM proxy, check that the storage layout of the new implementation is compatible with the deployed one. `Gsm` and `Gsm4626` proxies deployed before [#41](https://github.com/aave-dao/gho-origin/pull/41) fail this check and cannot be upgraded in place.

To move an existing GSM to a new implementation, deploy a new GSM and migrate to it in one governance payload:

1. Deploy a new proxy with the new implementation and initialize it.
2. Configure the new GSM like the old one: exposure cap, fee strategy, `SWAP_FREEZER_ROLE` for the oracle swap freezer and `CONFIGURATOR_ROLE` for the GSM steward. Add it to `GhoReserve` as an entity with a limit, and to `GsmRegistry`.
3. On the old GSM, call `distributeFeesToTreasury`, grant `LIQUIDATOR_ROLE` to the executor and call `seize()`. This sends its underlying to the treasury and disables swaps permanently.
4. Sell the seized underlying into the new GSM, and use the GHO to `burnAfterSeize` the old GSM's used GHO. Cover any shortfall from the Collector.
5. Retire the old GSM: set its `GhoReserve` limit to 0 and call `removeEntity`, remove it from `GsmRegistry`, revoke its roles and cancel its swap freezer keeper.

[`AaveV3Ethereum_GSMMigration_20251113`](https://github.com/aave-dao/aave-proposals-v3/blob/549ea8de0f75f94af1d5961ad6c9d98577c225f9/src/20251113_AaveV3Ethereum_GSMMigration/AaveV3Ethereum_GSMMigration_20251113.sol) is a worked example. It migrated the mainnet GSMs from GHO facilitators to `GhoReserve` entities, so it removes the old GSMs as facilitators rather than as entities.
