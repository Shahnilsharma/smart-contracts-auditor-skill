# ZIGChain — default chain params

Source docs: https://docs.zigchain.com/ , /integration-guides/chain-information, /build/quick-start (note: some older links use /builders/ — docs.zigchain.com has reorganized paths before, if a link 404s try the sitemap/search on the docs site rather than assuming the page is gone), /integration-guides/endpoints. Re-fetch these if user says "refresh chain docs" — docs version banner shows current major.

## Network

| Env | Chain ID | Notes |
|---|---|---|
| Mainnet | `zigchain-1` | confirmed via docs.zigchain.com quick-start and chain-info pages (checked mid-2026) — re-verify against `/integration-guides/chain-information` if it's been a while, chain-ids don't normally change but don't assume permanence |
| Testnet | `zig-test-2` | default deploy target, confirmed via docs |
| Local dev | `zigchain-1` (local genesis) | from `zigchain_local_setup.sh`, distinct keyring from real mainnet despite sharing the same chain-id string locally |

## Versions (read from public nodes, 2026-10-27; re-read with the command in `tooling-and-versions.md` section 1)

| | Mainnet `zigchain-1` | Testnet `zig-test-2` |
|---|---|---|
| zigchaind | v5.1.2 | v6.0.0 |
| wasmd / wasmvm | v0.60.9 / v2.3.5 (CosmWasm 2.3) | v0.60.9 / v2.3.5 |
| Cosmos SDK / ibc-go | v0.53.8 / v10.5.0 | v0.53.8 / v10.5.0 |
| IBC middleware | packet-forward v10, rate-limiting v10.1.0, 08-wasm light client; no ibc-hooks | |

- **Advisories:** wasmvm 2.3.5 and wasmd 0.60.9 are the patched releases for CWA-2026-006 (sandbox escape), and both are at or above the patched versions of every earlier CWA in `tooling-and-versions.md`.
- **Testnet is a major version ahead of mainnet.** Behaviour proven on testnet must be re-checked against mainnet's version before it's cited in a report.
- **Contracts that need CosmWasm 3.0 features don't work here.** That means `Ibc2Msg` and the IBC v2 entry points. Building with `cosmwasm-std` 3 is fine as long as no `cosmwasm_3_0` feature is enabled.

## Upload and instantiate permissions (from `/cosmwasm/wasm/v1/codes/params`)

- `code_upload_access`: `AnyOfAddresses`, 15 addresses on mainnet in Oct 2026.
  - Mainnet whitelisting goes through a governance proposal; the docs have a proposal-generator script.
  - Testnet whitelisting is by request on Discord or Telegram.
- `instantiate_default_permission`: `Everybody`. Anyone can instantiate any stored code ID with their own admin and config. Pin contract addresses (not code IDs) in front ends, registries and integrations, and check that no contract trusts another just because of its code ID.

## Native modules contracts interact with

- **Factory (token factory):**
  - Denoms look like `coin.{creator_address}.{subdenom}`.
  - The creator becomes bank admin and metadata admin. The bank admin can mint to any account up to `minting_cap`, and can raise the cap if `can_change_minting_cap` is true.
  - Admin transfer is two-step (`ProposeDenomAdmin` / `ClaimDenomAdmin`), `DisableBankAdmin` is permanent, and admins can delegate through authz.
  - Audit both directions: a contract that accepts a factory denom as collateral or as a pool asset must check its admin, cap and authz exposure. A contract that is a denom admin must protect that role like any admin key.
- **DEX:**
  - Native constant-product (`x*y=k`) pools, one pool per pair.
  - Swaps take a minimum output and an optional receiver.
  - The pool's spot price moves within one transaction, so it is never an oracle. Contracts that route swaps through it must pass a real minimum output, not zero.
- **Token wrapper:**
  - Bridges Axelar ZIG (from ERC-20 ZIG) to native `uzig` through IBC, scaling 18 decimals to 6 and rounding down. Amounts under 10^12 base units are rejected.
  - An operator can change `decimal_difference`, the channel and the denoms, and pausers can disable the module.
  - Contracts that depend on bridged ZIG inherit that operator trust. Note it in the threat model.

## Endpoints (public dev endpoints, not for production load)

- RPC: `https://public-zigchain-rpc.numia.xyz`
- LCD/API: `https://public-zigchain-lcd.numia.xyz`
- Faucet (testnet): `https://faucet.zigchain.com`
- Full endpoint list / persistent peers: `https://docs.zigchain.com/integration-guides/endpoints`

## Token / gas

- Denom: `uzig` (ZIG, 6 decimals typical Cosmos convention — confirm decimals in registry)
- Gas price: `0.0025uzig` standard; `--gas auto --gas-adjustment 1.3` default, bump to 1.5–2.5 or set explicit `--gas` for write-heavy contracts (WriteFlat gas errors are common — see troubleshooting below)

## CosmWasm specifics

- Contract `store` (upload) is **whitelist-gated** — address must be whitelisted before deploying. Check `/builders/cosmwasm-whitelisting` and remind user to confirm whitelisting before Step 7 (deploy).
- Compile target: `wasm32-unknown-unknown`. ZigChain's docs recommend the bulk-memory, reference-types and sign-ext rustflags in the `.cargo/config.toml` below, and the `cosmwasm/workspace-optimizer:0.17.0` image (a deprecated alias of `cosmwasm/optimizer:0.17.0`). Treat that as the chain's guidance, not a proof:
  - Upstream CosmWasm VMs reject bulk-memory (CosmWasm/cosmwasm#2485).
  - Optimizer 0.17.0's changelog says its output needs CosmWasm 3.0+, while ZigChain mainnet runs 2.3.

  Before relying on a build, run `cosmwasm-check` on the artifact and do a `store` on testnet. If a raw build fails with "bulk memory support is not enabled", build through the optimizer, or pin Rust 1.86 in `rust-toolchain.toml`. See `tooling-and-versions.md` section 4.
- Build with the optimizer before deploy, for reproducible, small builds. For checksum verification, use the same image name, version and architecture as the deployment (the x86_64 and `-arm64` images give different checksums).
- Ledger hardware wallets **cannot** sign `store` txs (payload too large, APDU 0x6988) — only `instantiate`/`execute` with `--sign-mode amino-json`. Use a software key or CI signer for `store`.

`.cargo/config.toml`:
```toml
[alias]
wasm = "build --release --lib --target wasm32-unknown-unknown"
unit-test = "test --lib"
schema = "run --bin schema"
integration-test = "test --lib integration_tests"

[target.wasm32-unknown-unknown]
rustflags = [
  "-C", "link-arg=-s",
  "-C", "target-feature=+bulk-memory",
  "-C", "target-feature=+reference-types",
  "-C", "target-feature=+sign-ext",
]
```

## CLI reference (zigchaind)

```bash
# store
zigchaind tx wasm store artifacts/<name>.wasm --from $WALLET_ID \
  --gas auto --gas-adjustment 1.3 --gas-prices 0.0025uzig \
  --chain-id <chain-id> --node <rpc> --yes

# instantiate
zigchaind tx wasm instantiate $CODE_ID '<init-json>' --label "<label>" \
  --from $WALLET_ID --admin $WALLET_ADDRESS \
  --gas auto --gas-adjustment 1.3 --gas-prices 0.0025uzig \
  --chain-id <chain-id> --node <rpc> --yes

# execute
zigchaind tx wasm execute $CONTRACT_ADDRESS '<msg-json>' --from $WALLET_ID \
  --gas auto --gas-adjustment 1.3 --gas-prices 0.0025uzig \
  --chain-id <chain-id> --node <rpc> --yes

# query
zigchaind query wasm contract-state smart $CONTRACT_ADDRESS '<query-json>' \
  --chain-id <chain-id> --node <rpc>
```

## Local dev test accounts (LOCAL ONLY, chain-id zigchain-1 — publicly known, never use on testnet/mainnet)

valuser1, zuser1..zuser5 — created by `zigchain_local_setup.sh`. Do not reuse these mnemonics for real funds.

## Custom chain override

If user supplies a different chain (URL or .md), replace this whole file's fields (chain-id, RPC/LCD, denom, gas price, whitelisting rules, CLI binary name) with the fetched values, keep this file as the ZIGChain fallback under `references/zigchain.md` and write the new one alongside it.
