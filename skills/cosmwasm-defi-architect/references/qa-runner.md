# QA runner pattern (Rust + Node)

## Rust side — `tests/integration.rs` (cw-multitest)

One module per execute variant. Structure:
```rust
#[test]
fn <action>_happy_path() { /* setup App, instantiate, execute, assert state */ }

#[test]
fn <action>_rejects_wrong_sender() { /* assert_err on unauthorized */ }

#[test]
fn <action>_rejects_overflow_amount() { /* Uint128::MAX edge */ }

#[test]
fn full_scenario_invariant() { /* run full sequence, assert contract bank balance == internal ledger sum */ }
```
Run: `cargo test` (aliased `cargo unit-test` / `cargo integration-test` per `.cargo/config.toml`).

## Node side — `qa/runner.mjs` (CosmJS)

Sequential, role-based, real testnet/local node. Shape:

```js
import { getWalletForRole } from "./wallet_loader.js";
import { SigningCosmWasmClient } from "@cosmjs/cosmwasm-stargate";

const ROLES = ["admin", "user1", "user2", "attacker"];
const RPC = process.env.CHAIN_RPC; // from resolved chain config, testnet default
const CONTRACT = process.env.CONTRACT_ADDRESS;

async function run() {
  const results = [];
  for (const role of ROLES) {
    results.push(await scenarioFor(role));
  }
  await finalInvariantCheck(results);
  printReport(results); // pass/fail per case, gas used, tx hash
}

// Mnemonic-mode roles get a real in-process CosmJS client. Keyring-mode roles do NOT —
// see the architecture note at the top of wallet_loader.js for why a system keyring can't
// hand out an in-process signer — so keyring-mode roles execute via execKeyringTx() (CLI
// passthrough to the chain binary) instead of connect(). Branch on WALLET_MODE per call site,
// or keep two code paths in scenarioFor() — don't assume one client type covers both.
async function connect(role) {
  const wallet = await getWalletForRole(role); // mnemonic mode only — throws for keyring, by design
  const client = await SigningCosmWasmClient.connectWithSigner(RPC, wallet);
  const [{ address }] = await wallet.getAccounts();
  return { client, address };
}

run().catch((e) => { console.error(e); process.exit(1); });
```

Each `scenarioFor(role, ...)` runs: happy path -> permission-denied attempt (should fail) -> boundary amount -> replay attempt (should fail/no-op) -> query verify. Log every tx hash and gas used for the audit report.

Test-case sequencing is deliberate and sequential (not parallel) so each role's action can depend on prior on-chain state (e.g. user1 deposits before attacker tries to withdraw user1's funds).

## Wallet resolution — always ask first

Before running the Node runner, ask the user (not assume) — and be aware these two modes use genuinely different execution paths in the runner, not just a different key source:
1. **Mnemonic per role** — env vars, e.g. `ADMIN_MNEMONIC`, `USER1_MNEMONIC`, `ATTACKER_MNEMONIC`. Load via `.env`, never echoed or committed. `wallet_loader.js`'s `getWalletForRole(role)` returns a real in-process CosmJS `OfflineSigner` for this mode — use `connect()`/`SigningCosmWasmClient` as shown above.
2. **Binary/system keyring** — existing `zigchaind keys` entries. A system keyring does not export private key material to an in-process signer (that's its whole security property), so this mode does **not** go through `getWalletForRole()` — calling it in keyring mode throws intentionally, with a message pointing at the right function. Use `wallet_loader.js`'s `execKeyringTx(role, txArgs)` instead: it shells out to `zigchaind tx ...` directly via `execFileSync` (argument array, not a shell string — not vulnerable to shell injection through a role name or message content) for every keyring-mode transaction, same pattern `scripts/deploy.sh` already uses.

If the QA runner needs to support both modes side by side (e.g. `admin` via keyring, `attacker` via mnemonic), branch per-role on `WALLET_MODE` — or better, on a per-role mode map if roles can mix modes — rather than assuming the whole run uses one mode.

## Report

Emit `qa/report.md`: table of role x scenario x result x tx hash x gas, plus the final invariant check outcome. This feeds directly into the audit report's "tested" evidence.
