# CosmWasm tooling and version compatibility

Read this in step 0 (resolve the chain) and again before QA and static analysis. CosmWasm chains differ in VM version, enabled features, upload rules and native modules, so a tool or contract feature that works on one chain can fail, or silently mean something else, on another. Facts below were checked in October 2026; re-check anything version-specific against the linked source if it's been a while.

## 1. Read the target chain's real versions (don't trust docs pages)

Any public node reports its build dependencies. This is read-only and needs no wallet:
```bash
curl -s "$LCD/cosmos/base/tendermint/v1beta1/node_info" | python3 -c 'import json,sys; d=json.load(sys.stdin); a=d["application_version"]; print(d["default_node_info"]["network"], a["version"]); [print(x["path"], x["version"]) for x in a["build_deps"] if any(k in x["path"] for k in ("wasmd","wasmvm","cosmos-sdk","ibc-go","ibc-apps","ibc-hooks","tokenfactory"))]'
curl -s "$LCD/cosmwasm/wasm/v1/codes/params"     # who may upload code, and default instantiate permission
```
Record in the report: chain version, wasmd, wasmvm, Cosmos SDK, ibc-go, and which IBC middlewares are present (ibc-hooks, callbacks, packet-forward, rate-limiting). Check mainnet and testnet separately: they often run different versions (ZigChain in Oct 2026: mainnet v5.1.2, testnet v6.0.0), so a test that passes on testnet doesn't prove mainnet behaviour.

## 2. Version lines and what they change

| CosmWasm / wasmvm | Notes for auditors |
|---|---|
| 1.x | End of life. `cosmwasm-std` 1.3.0–1.5.3 has the CWA-2024-002 overflow bug. |
| 2.0–2.2 | 2.0 added `CosmosMsg::Any`, `GrpcQuery`, `msg_responses` in `reply`, and `payload` on `SubMsg`. 2.1 added IBC callbacks (`ibc_source_callback`, `ibc_destination_callback`). 2.2.x support ended 2026-05-31. |
| 2.3 | Supported until 2026-12-31. Mostly fixes, plus deprecation of IBC fee types (removed from ibc-go v10). ZigChain mainnet runs wasmvm 2.3.5. |
| 3.0 (wasmd 0.61+, released Jun 2025) | Supported until 2026-12-31. IBC v2 entry points (`ibc2_packet_receive/ack/timeout/send`, `Ibc2Msg`). **`Coin::amount` is now `Uint256`**, so every conversion to `Uint128` must be checked. `BankQuery::AllBalances` and `IbcQuery::ListChannels` are removed. `serde_json` replaces `serde-json-wasm`. Partial reference-types support in the VM. |

- **Capabilities:** a contract built with a `cosmwasm_X_Y` feature (or `stargate`, `staking`, `iterator`, or a chain-specific capability) can only be uploaded to a chain whose VM advertises that capability. Without those features, a contract built with 3.0 still runs on 1.x/2.x chains. Check the `[features]` of `cosmwasm-std` in `Cargo.toml` against the chain.
- **cw-multi-test** must match the major version of `cosmwasm-std` (2.x with 2.x, 3.x with 3.x), with the same capability features enabled. Otherwise tests exercise a different API from the deployed contract.

## 3. Advisories to check against the chain's versions

These are chain-level, but a protocol launched on an unpatched chain inherits them. State the chain's status in the report. Source: github.com/CosmWasm/advisories.

| Advisory | Issue | Patched in |
|---|---|---|
| CWA-2024-002 | Wrapping overflow in `Uint256/512::pow`, `Int256/512::neg` (cosmwasm-std) | std 1.4.4, 1.5.4, 2.0.2 |
| CWA-2024-004, -007, -008 | Gas mispricing, incorrect metering, panic slowing blocks | wasmvm 1.5.5, 2.0.4, 2.1.3 |
| CWA-2024-006 | Non-deterministic `module_query_safe` query | wasmd 0.53.0 |
| CWA-2025-001 / -002 | Contract can crash the chain / slow block production | wasmvm 1.5.8, 2.0.6, 2.1.5, 2.2.2 |
| CWA-2025-003 | Consensus failure for some nodes | wasmvm 1.5.9, 2.1.6, 2.2.3 |
| CWA-2025-004 / -005 / -006 | Sub-context gas not charged; missing IBC entry-point setup cost; IBC channel opens despite contract error | wasmd 0.53.3, 0.54.1, 0.55.1, 0.60.1 |
| CWA-2025-007 | Unbounded `reply` recursion overflowing the stack | wasmd 0.54.3, 0.60.2, 0.61.6 |
| CVE-2025-25500 | Capability restrictions not enforced | CosmWasm 2.2.0 |
| CWA-2026-001 | Node memory saturation | wasmvm 2.2.6, 2.3.2, 3.0.3; wasmd 0.54.6, 0.60.5, 0.61.8 |
| CWA-2026-002 | Malicious balance operations (IBC v2 chains on wasmd 0.61.x) | wasmd 0.61.9 |
| CWA-2026-003 | Delayed block production | wasmd 0.54.7, 0.60.6, 0.61.10 (the advisory's affected and patched ranges overlap; re-check it) |
| CWA-2026-004 | Chained overflows bypass gas limits | cosmwasm-vm 2.2.8, 2.3.3, 3.0.6 |
| CWA-2026-005 | Many Wasm locals stall the chain | cosmwasm 2.2.9, 2.3.4, 3.0.8 |
| CWA-2026-006 | **Sandbox escape** in Wasmer Singlepass | wasmvm 2.2.9, 2.3.5, 3.0.8; wasmd 0.54.10, 0.60.9, 0.61.15, 0.70.4 |
| ASA-2024-007 (ibc-go) | Reentrancy through ibc-hooks timeout callbacks, which could drain ICS-20 escrow | ibc-go 4.6.0, 5.4.0, 6.3.0, 7.4.0, 8.2.0 |

## 4. Building: Rust toolchain, Wasm features, optimizer

- **Rust 1.87 and later** emit `bulk-memory` instructions for `wasm32-unknown-unknown` by default. As of Feb 2026, CosmWasm VMs reject them at upload with "bulk memory support is not enabled" (tracked in CosmWasm/cosmwasm#2485). Pin the toolchain for raw builds: put `rust-toolchain.toml` with `channel = "1.86"` in the repo, or build only through the optimizer.
- **`cosmwasm/optimizer`** is the image to use; `workspace-optimizer` and `rust-optimizer` are deprecated aliases since 0.15.
  - **0.17.0** builds with Rust 1.86. Its changelog says the output requires CosmWasm 3.0+ on chain.
  - **0.16.1** builds with Rust 1.81, for chains below 3.0.
  - Before mainnet, confirm with `cosmwasm-check --available-capabilities <chain's list> artifacts/*.wasm` and a `store` on the chain's testnet.
- **Reproducibility:** the x86_64 image and the `-arm64` image produce different checksums for the same source. Verify a deployed checksum with the same image name, version and architecture that produced it (normally x86_64), from the committed `Cargo.lock`.
- **No floats:** the VM rejects float instructions at upload, and `cosmwasm-check` catches them.

## 5. Tools by testing type

| Testing type | Tool | Use it for | Limits |
|---|---|---|---|
| Unit | `cargo test` with `cosmwasm_std::testing` mocks | Pure logic, every error branch | Mocks don't model other contracts or modules |
| Integration | `cw-multi-test` (Sylvia's generated helpers if the project uses Sylvia) | Multi-contract flows, submessages and replies, bank sends | No IBC, no real chain modules (token factory, native DEX, Stargate/Any), **no gas metering** |
| Real chain modules | `test-tube` family: osmosis-test-tube, neutron-test-tube, injective-test-tube | Contracts that call that chain's modules | Only exists for those chains; needs Go and clang |
| Same tests on multitest, local node, testnet | `cw-orchestrator` (cw-orch) | One script reused from unit tests to live deployment | Learning curve; check version support for the project's std |
| Live node | CosmJS runner (`references/qa-runner.md`), chain local-node script | Real gas, real modules, wallet roles | Slow; testnet may differ from mainnet (section 1) |
| Property-based | `proptest` | Math, share pricing, rounding properties | Pure functions only, unless driving cw-multi-test |
| Coverage-guided fuzz + invariants | CosmFuzz (SRLabs, Mar 2026, `cargo install --git https://github.com/srlabs/cosmfuzz cosmfuzz`) | Stateful fuzzing over cw-multi-test with invariants (supply = sum of balances, solvency) | New tool: multi-contract support basic, native modules not modelled |
| Low-level fuzz | `cargo-fuzz` | Parsers, custom (de)serialization, hand-rolled math | Needs nightly |
| Coverage | `cargo llvm-cov --html` | Find untested branches in money paths | Native build, not the Wasm binary |
| Mutation testing | `cargo mutants` | Shows tests that can't fail: a surviving mutant in a money path is a missing assertion | Slow on big crates; scope with `--file` |
| Bounded proofs | Kani | Prove properties of pure math helpers (no overflow, rounding direction) | Pure Rust only; bounded |
| Model-based | Quint with Informal's `cosmwasm-to-quint` | Model and check protocol state machines | Experimental, last updated 2024 |
| IBC end-to-end | `interchaintest` (Go, Docker), Starship (Kubernetes), cw-orch-interchain | Packet lifecycle, acks, timeouts, relayer behaviour | Heavy; run once per IBC flow, under the Phase 0.5 memory cap |
| Static | `cargo clippy` (with `-W clippy::arithmetic_side_effects -W clippy::unwrap_used -W clippy::expect_used -W clippy::panic -W clippy::indexing_slicing`), `cargo audit`, `cargo deny check` | Panics, unchecked math, vulnerable or duplicate dependencies | Doesn't know CosmWasm semantics |
| Wasm validation | `cosmwasm-check` | Upload-ability, capabilities, floats, size, exports | Only checks the binary |
| CosmWasm-aware second opinion | Trail of Bits `cosmos-vulnerability-scanner` skill (github.com/trailofbits/skills, plugin `building-secure-contracts`) | Overflow on old std, non-deterministic queries, IBC reentrancy, plus Cosmos SDK modules | Pattern-based; triage every hit |
| Practice targets | Oak Security `cosmwasm-ctf` | Calibrate a reviewer on real audit bug classes | Training only |

Ask before installing any of these (SKILL.md step 0.5). Mark each one RAN, INCONCLUSIVE or NOT EXECUTED in `audit-out/STATUS.md`.

## 6. What differs per chain (resolve in step 0)

- **Upload permission:**
  - Permissionless upload widens the attack surface. ASA-2024-007 needed permissionless upload.
  - With whitelisted upload (`AnyOfAddresses`, e.g. ZigChain) or governance-only upload, plan the deployment timeline around it.
- **Default instantiate permission:**
  - If it's `Everybody`, anyone can create their own instance of your stored code with their own admin and config.
  - Integrators and front ends must pin contract addresses, not code IDs.
  - A registry that trusts any contract "with code ID N" trusts attacker-configured copies.
- **Stargate / gRPC query allowlist and `CosmosMsg::Any` support:** what a contract can query or send to native modules differs per chain.
- **IBC stack:**
  - ibc-go version, and whether IBC v2 is enabled.
  - Middlewares: ibc-hooks (contract executes from IBC memos), callbacks, packet-forward, rate-limiting.
- **Native modules contracts interact with:**
  - Token factory variants, each with different admin and mint semantics.
  - Native DEXes.
  - Custom bindings: Neutron ICA/ICQ/cron, Injective exchange, Osmosis poolmanager.
- **Forks with different semantics:** Secret Network has encrypted state and its own threat model (viewing keys, permits, gas side channels). Treat it as out of scope unless the user names it, and say so.
