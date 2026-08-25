# CosmWasm coding standards (enforce in every generated contract)

- Arithmetic: `Uint128`/`Decimal` checked ops only (`checked_add`, `checked_sub`, `checked_mul`, `checked_div`). Never bare `+`/`-`/`*`/`/` on token amounts.
- Errors: custom `ContractError` enum (thiserror), no `unwrap()`/`expect()`/`panic!` on any path reachable from `execute`/`query`/`instantiate`/`migrate`.
- Sender checks: first lines of every privileged `execute` branch, explicit `if info.sender != cfg.admin { return Err(ContractError::Unauthorized {}) }` style — never implicit.
- Funds checks: validate `info.funds` denom+amount explicitly wherever payable; reject unexpected denoms.
- Storage: `cw-storage-plus` `Item`/`Map`, namespaced keys, no raw byte-string collisions across modules.
- Events: `Response::new().add_attribute(...)` on every state change, action name + key params, for indexers/audits.
- Checks-effects-interactions: mutate state before dispatching submessages/bank sends; validate `reply` results before trusting them.
- Pagination: any `Map` iteration exposed via query must support `start_after`/`limit`, capped max limit.
- `migrate`: version-gate (`cw2` `set_contract_version`/`get_contract_version`), validate old-state shape before writing new.
- `Addr` validation: `deps.api.addr_validate(&input)` before storing/using any user-supplied address string.
- Tests live alongside: `#[cfg(test)]` unit tests for pure logic, `tests/integration.rs` cw-multitest for full flows (see `qa-runner.md`).
