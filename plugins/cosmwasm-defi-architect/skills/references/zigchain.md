# ZIGChain — default chain params

Source docs: https://docs.zigchain.com/ , /integration-guides/chain-information, /build/quick-start (note: some older links use /builders/ — docs.zigchain.com has reorganized paths before, if a link 404s try the sitemap/search on the docs site rather than assuming the page is gone), /integration-guides/endpoints. Re-fetch these if user says "refresh chain docs" — docs version banner shows current major.

## Network

| Env | Chain ID | Notes |
|---|---|---|
| Mainnet | `zigchain-1` | confirmed via docs.zigchain.com quick-start and chain-info pages (checked mid-2026) — re-verify against `/integration-guides/chain-information` if it's been a while, chain-ids don't normally change but don't assume permanence |
| Testnet | `zig-test-2` | default deploy target, confirmed via docs |
| Local dev | `zigchain-1` (local genesis) | from `zigchain_local_setup.sh`, distinct keyring from real mainnet despite sharing the same chain-id string locally |

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
- Compile target: `wasm32-unknown-unknown`, requires bulk-memory + reference-types + sign-ext rustflags (see `.cargo/config.toml` snippet below) or the store tx fails with "bulk memory support is not enabled".
- Optimize with `cosmwasm/workspace-optimizer:0.17.0` docker image before deploy — required for reproducible/small builds, not optional in practice.
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
