# CosmWasm / DeFi audit checklist

Go through every item against actual code lines — cite the branch checked, not a blanket "looks fine".

## Access control
- Every `ExecuteMsg` branch checks `info.sender` against expected role (admin/owner/user) explicitly.
- Admin-only actions (pause, upgrade config, withdraw fees) can't be called by arbitrary sender.
- `MigrateMsg` guarded — only current admin/gov can trigger migration, old state shape validated on migrate.
- No unauthenticated funds-moving message.
- Rotating the admin/owner (cw-ownable or custom) revokes the old one everywhere it's stored, including in child contracts the factory instantiated before and after the rotation, and the contract's wasmd admin (the address allowed to migrate) is rotated too. Test it as the old key after rotation.

## Chain / VM version
- The target chain runs a wasmvm with the 2025 VM fixes (CWA-2025-001 chain crash and CWA-2025-002 block slowdown, patched in 1.5.8, 2.0.6, 2.1.5 and 2.2.2) and CosmWasm ≥ 2.2.0 (CVE-2025-25500, contracts deployable without capability enforcement). These are chain-level issues, but a protocol launching on an unpatched chain inherits them — check and state the versions in the report.
- `cosmwasm-std` itself is on a release patched for CWA-2024-002 (wrapping `Uint256/512::pow` and `Int256/512::neg`; patched in 1.4.4, 1.5.4 and 2.0.2).
- Read the chain's real wasmd/wasmvm/ibc-go versions from a node (`tooling-and-versions.md` section 1) and check them against the full advisory table there, through CWA-2026-006 (sandbox escape) and ASA-2024-007 (ibc-hooks reentrancy). Check mainnet and testnet separately.
- The contract's `cosmwasm_*` capability features exist on the target chain, `cosmwasm-check` passes on the exact artifact being deployed, and the test suite uses the cw-multi-test major that matches `cosmwasm-std`.
- On `cosmwasm-std` 3, `Coin::amount` is `Uint256`: every conversion to `Uint128` is a checked `try_into`, never a truncating cast, and contracts migrated from 2.x to 3 are re-reviewed for this.

## Arithmetic
- All token-amount math uses `Uint128`/`Decimal` **checked** ops (`checked_add/sub/mul/div`) — no raw operator on user-influenced values.
- Division/rounding direction always favors the protocol/pool, not the caller (documented explicitly).
- No silent truncation that lets a user round a fee to zero via small amounts — if a fee calculation truncates to zero for a legitimate-sized input, charge a minimum of 1 unit rather than letting it pass free (a disclosed pattern from real CosmWasm audits: `Decimal`-based fee math can truncate to exactly zero even for non-trivial amounts when decimals differ across assets — always normalize decimal places across assets being compared/combined before the calculation, not after).

## Storage writes
- Every value loaded from storage, changed and meant to persist is saved back. A struct mutated in memory and never written back is a common real finding (Oak Security spotlight #1, "unsaved storage changes"). Trace every `load` to its `save` or `update`, especially across early returns.
- `may_load` on missing data doesn't silently fall back to a default that resets a user's position or a global counter.

## Lists of IDs and duplicates
- Any message that takes a list (position IDs, order IDs, denoms, recipients, validator addresses) rejects duplicates or is idempotent per element. Mirror Protocol (Terra, 2021–22, about $90M) let one position ID be passed hundreds of times in a single unlock call.
- Per-element limits apply to the total too: a cap checked per item but not per message can be bypassed by splitting.

## Balance accounting
- Accounting uses an internal ledger, not the contract's bank balance. Anyone can send funds directly to a contract: Mirror's attacker inflated a position's locked amount with a direct transfer. In vaults, a direct transfer is the first-depositor share-inflation attack.
- Vault and LP share math has a minimum initial deposit, dead shares or a virtual offset, so the first depositor can't round later depositors down to zero shares.

## IBC / cross-module query DoS
- Any query that enumerates a contract's IBC channels, connections, or other cross-module state (e.g. a `ListChannels`-style query) filters to the calling contract's own scope rather than returning global chain state — an unfiltered enumeration query becomes more expensive (and eventually fails/DoSes) as the chain accumulates more channels/connections over time, independent of anything the contract itself did wrong. This is a disclosed, real pattern from a published CosmWasm core audit (Oak Security, 2022) — the general lesson applies to any contract exposing a similarly unbounded cross-module enumeration.
- Any operation performing decompression/deserialization of externally-supplied data (e.g. contract code on `store`/`migrate`, or a compressed payload in a message) charges gas proportional to the *pre-expansion* cost even when the operation later fails, so a cheap malformed-input attempt can't be used to grief validators for free — verify the chain/module in scope already enforces this at the base layer rather than assuming the contract needs to reimplement it, but flag if a contract does its own decompression of user input without an equivalent safeguard.

## Migration / restricted code-ID bypass
- If the chain supports code-ID access-control/instantiate-permission restrictions (whitelisting), the `migrate` entry point is checked to ensure it can't be used to move a contract onto a *restricted* code ID that the contract wouldn't have been allowed to instantiate against directly — a disclosed real-world CosmWasm pattern where migration bypassed an instantiate-permission restriction.

## Reentrancy / submessages
- State updated *before* triggering external calls or submessages ("checks-effects-interactions").
- `reply` handlers validate `msg.result` and don't trust unchecked external contract state.
- No pattern where a submessage callback can re-enter and double-spend before the first call's state write lands.

## Submessage / reply semantics
- `ReplyOn` mode chosen deliberately: with `ReplyOn::Error` or `ReplyOn::Always`, a failed submessage's error is caught and the parent execution *continues* — the submessage's own state changes are reverted, but the parent's earlier writes persist. The reply handler either returns an error or correctly unwinds the parent's accounting (e.g. a deposit recorded before a transfer that then failed).
- `reply` dispatches on `msg.id` and returns an error for unknown ids, not a silent `Ok`.
- Data extracted in `reply` (e.g. a newly instantiated contract's address) comes from the response data (`msg_responses` in cosmwasm-std 2.x, or `cw_utils::parse_instantiate_response_data`) or from module-emitted events (e.g. `instantiate`) — never from attributes in `wasm` events, which the called (possibly untrusted) contract writes itself.

## CW20 `Receive` hook
- The `ExecuteMsg::Receive(Cw20ReceiveMsg)` handler checks `info.sender` against the expected/whitelisted CW20 token contract — inside `Receive`, `info.sender` is the token contract and `cw20_msg.sender` is the original user. Without this check anyone can call `Receive` directly with a made-up `amount` and be credited for tokens they never sent.
- When several CW20s are accepted, the token is identified by `info.sender`, never by a field in the inner message.
- Native denoms, CW20 contract addresses and token-factory denoms can't be confused in internal accounting (an `AssetInfo`-style enum, not a bare string that could be either).

## Funds handling
- `info.funds` validated against expected denom + amount on every payable entry point.
- No entry point that silently accepts and strands unexpected denoms.
- Contract balance invariant: sum of internal ledger == actual bank balance, tested explicitly.
- Withdraw/claim paths can't be called twice for same accrued amount (idempotency / replay guard).
- Mints, withdrawals or prices approved by an off-chain signer (a backend key, a bot, a relayer) are bounded on-chain: per-message and per-period caps, backing checks, and a signer that isn't a single key (Resolv, Mar 2026, EVM: one key could approve any mint amount; ~80M unbacked stablecoins minted).
- Hand-rolled math (custom fixed-point, `Uint256`/`Uint512` mul-div helpers) is differentially fuzzed against `cosmwasm-std`'s own checked operations or another reference, and rounding is tested under repetition: many minimal-size operations in one transaction must not move a pool invariant or share price in the caller's favour (Balancer and Bunni, 2025, on EVM).

## Oracle / price
- Price source has a staleness check (block height/time bound).
- No single-block/single-tx price used for large-value decisions without TWAP or bounds check.
- Oracle failure mode (missing/zero price) fails closed, not open.
- The staleness check uses the time the price was published, not when it was pushed to the contract. Trading pauses while prices are stale instead of filling at the last price. Levana (Osmosis, Dec 2023, about $1.1M) lost money when a congestion attack kept Pyth updates from landing and traders opened positions against stale prices. Check the confidence interval too (Pyth `conf`).
- A native AMM pool's spot price (Osmosis, Astroport, the ZigChain DEX module) moves within one transaction and is never used as an oracle.

## Timestamp / block manipulation
- No high-value decision depends solely on `env.block.time`/`env.block.height` in a way a validator/proposer could profitably nudge — flag single-block-time-gated auctions, vesting-cliff edges, or "did the window just close" checks as findings; prefer a grace-period buffer for anything security-critical.
- No randomness-dependent logic derived from `env.block.time`/`env.block.height`/tx hash alone where the value at stake would make manipulation worthwhile.

## Governance bypass
- If the contract is gated by a DAO/governance module (cw3 multisig, cw4 group, chain-level x/gov, or a custom voting contract), every governance-gated `ExecuteMsg` branch re-checks the *current* on-chain proposal/vote state at execution time, not a caller-supplied claim that a vote passed.
- Voting power is snapshotted at proposal creation (not read live at execution) wherever token-weighted voting is used, to prevent same-block/same-tx balance manipulation from manufacturing voting power.
- Quorum and pass thresholds are sized against how much voting power can be bought on the open market. If buying enough votes costs less than what one proposal can move, add a veto/guardian path during the timelock and cap what a single proposal can transfer (BonkDAO on Solana, Jul 2026: ~$4M of tokens bought, ~$20M drained by a malicious proposal).
- Adding a new collateral asset, market or oracle source is timelocked and new assets start with conservative caps (Drift on Solana, Apr 2026: a captured admin listed a worthless token, inflated its oracle price and borrowed real assets against it).
- `MigrateMsg` and any "emergency"/bypass code path are checked against the same authority requirements as the normal governance path, or the bypass is explicitly documented as part of the key-compromise ladder in the threat model rather than a silent shortcut.

## IBC packet lifecycle
- `ibc_packet_ack` handles error acknowledgements and `ibc_packet_timeout` handles timeouts by refunding/unlocking whatever the send path escrowed — a missing refund path permanently strands funds on every failed or timed-out packet.
- Check how the target chain's wasmd version treats an `Err` from `ibc_packet_receive` (aborted transaction vs. converted to an error acknowledgement), and confirm both outcomes leave the sending side able to refund.
- `ibc_channel_open`/`ibc_channel_connect` validate the channel version string, ordering and counterparty port — accepting any channel lets anyone connect a malicious counterparty.
- Amounts minted or released per packet and per time window are rate-limited (an IBC rate-limit module or contract-level caps), so one forged or replayed message can't empty an escrow — the 2026 KelpDAO bridge loss (~$292M, EVM) came from one forged message.
- Ack and timeout handling is idempotent and follows checks-effects-interactions: a second ack or timeout for the same packet can't refund twice. ASA-2024-007 (ibc-go, Apr 2024) let a contract re-run an ICS-20 timeout from inside an ibc-hooks callback, which could have drained escrow on chains with permissionless upload.
- IBC callbacks (`ibc_source_callback`, `ibc_destination_callback`, CosmWasm 2.1+): anyone can trigger a destination callback by sending an ICS-20 transfer with a memo. Treat the sender, denom and amount as untrusted, and check the funds against the contract's real bank balance change. A source callback is trusted only for packets this contract sent.
- IBC v2 entry points (`ibc2_packet_receive/ack/timeout/send`, CosmWasm 3.0): validate the source client and port. Check whether the chain is affected by CWA-2026-002 (wasmd 0.61.x with IBC v2).
- With IBC hooks (`ibc-hooks` middleware), the `info.sender` of a hook-triggered execute is an address derived from the channel and the remote sender, not the user's own address on this chain — never grant it that user's privileges or balances.

## Storage key collisions
- Every `Item`/`Map`/`IndexedMap` uses a unique namespace string — two storage items declared with the same key (the same `Map::new("balances")` in two modules, or an `Item` key equal to a `Map` prefix) silently read and write the same bytes.
- Namespace strings stay unchanged across migrations unless the `migrate` handler explicitly moves the data.
- Composite keys use `cw-storage-plus` tuple/`PrimaryKey` types, not ad-hoc string concatenation (`format!("{}{}", a, b)` collides the same way `abi.encodePacked` does).

## Other entry points
- `sudo` (callable only by chain modules — gov, scheduler modules, chain-specific callbacks) handles every `SudoMsg` variant defensively; confirm which modules on the target chain can actually invoke it.
- `instantiate2` (predictable addresses): if a factory lets callers choose the salt, a front-runner can claim the salt/address another user expected — derive the salt from the caller's address. Funds sent to a predicted address before instantiation are only safe because the code checksum is part of the address; confirm the expected checksum is the one used.

## Native module messages and queries
- `CosmosMsg::Any` and `CosmosMsg::Stargate` messages are built by the contract from validated fields. A contract that forwards a user-supplied `type_url` and bytes executes arbitrary module messages with the contract's own authority (its funds, its token-factory admin rights, its authz grants).
- Stargate and gRPC queries are on the chain's allowlist and are deterministic. A non-deterministic module query can halt the chain (CWA-2024-006).
- Token-factory denoms accepted as collateral or pool assets: check who holds bank admin, the minting cap and whether it can change, and authz grants. A denom whose admin can mint without limit is worth only the admin's honesty. If the contract is itself a denom admin, the role-transfer and authz paths are access-controlled like any admin key.

## Instances and code IDs
- When upload or instantiate is permissionless (`instantiate_default_permission: Everybody`), anyone can create their own instance of the protocol's code with their own admin. Registries, factories, routers and front ends trust specific contract addresses, not "any contract with code ID N" or matching checksum, unless the code itself enforces all the config that matters.
- `instantiate` can't be front-run to take ownership of a predicted address or to initialize a shared resource first.

## Untrusted recipients and payouts
- Payouts to user-supplied addresses use bank sends, not `WasmMsg::Execute` into the recipient. A recipient contract that always errors would otherwise revert liquidations, withdrawal queues or batch settlements for everyone.
- Calls into untrusted contracts that must not block the protocol use `SubMsg` with a gas limit and `ReplyOn::Error`, with the reply handling the failure.
- Batched payouts don't fail entirely because one recipient is a blocked module account or an invalid address. Skip and record the failure, or make each claim pull-based.

## Slippage / front-running
- Swap, liquidity and liquidation entry points take a caller-supplied minimum-out or max-spread (Astroport-style `max_spread`/`belief_price`) and enforce it.
- Anything where seeing a pending transaction gives an edge uses commit-reveal or batching — Cosmos mempools are public and block proposers choose transaction order.

## DoS / gas
- No unbounded iteration over user-growable storage in a single tx (pagination or bounded maps used).
- WriteFlat-style gas blowup considered for write-heavy executes — gas estimate has safety margin, or execute is split.

## Upgrade / admin key
- Admin key rotation path exists and is tested.
- Emergency pause exists for fund-moving contracts, and pause doesn't lock user withdrawals of already-owned funds.

## Input validation
- Every function that changes something's status (approve/revoke, add/remove, open/close, cancel, claim, pause/unpause) first checks the current status: the item exists and isn't already in the target state. Events fire only on a real change, because indexers, monitors and dashboards trust them. Sibling functions on the same item check the same things; if `reassign` checks existence and `revoke` doesn't, that difference is the bug.
- No `unwrap()`/`expect()`/`panic!` reachable from user input — all fallible ops return `ContractError`.
- String/Addr inputs validated (`deps.api.addr_validate`) before storage or use as key, and the returned `Addr` is what's stored and compared, never the raw string. The same address in different letter case or prefix must map to one key: Halborn's disclosure covering 20+ CosmWasm chains (fixed in the host's `addr_validate`) showed upper-case Bech32 strings bypassing blocklists, creating duplicate pools and permanently locking CW20s sent to them. Oak Security spotlight #3 covers the same class. Check the chain's host is patched, and don't assume lower case in contract code.
- Boundary values tested: 0, 1, max `Uint128`, empty vecs/strings.

## Protocol-type checks
Run the block that matches the protocol, in addition to everything above.
- **AMM / DEX (constant product, stableswap, concentrated liquidity):**
  - Invariant holds after every swap, deposit and withdrawal, including fees and rounding.
  - The first LP can't manipulate the initial price or share supply.
  - Stableswap amplification changes are ramped, not instant.
  - Concentrated-liquidity tick crossing and fee growth are tested at range edges.
  - Every swap path takes a minimum output.
- **Lending / CDP:**
  - Collateral factors and liquidation thresholds per asset; the liquidation bonus can't exceed the collateral.
  - Bad debt has a defined path (insurance fund, socialization) rather than silently breaking solvency.
  - Interest accrues before every balance change.
  - Borrow and supply caps on new or thin-liquidity assets.
  - Liquidations still work when the oracle is stale or the user's position is dust.
- **Vaults / yield:**
  - Share inflation (see Balance accounting).
  - Strategy and harvest calls are access-controlled.
  - Reported vs. actual assets, after losses in an underlying protocol.
  - The withdrawal queue can't be blocked by one user (see Untrusted recipients).
- **Liquid staking** (contract stakes via `StakingMsg` / `DistributionMsg`):
  - The exchange rate accounts for slashing, pending unbonding and the 21-day-style unbonding period.
  - Redelegation limits are respected.
  - Rewards are withdrawn before the delegation changes, and the withdraw address can't be changed by an unauthorized caller.
  - The validator set update is access-controlled.
  - Unbonding batches can't be claimed twice.
- **Perps / derivatives:**
  - Oracle freshness at execution (Levana).
  - Funding and borrow fees accrue before position changes.
  - Max leverage and open-interest caps.
  - LP pool can't go insolvent from one market.
  - Keeper and liquidation incentives cover gas under congestion.
- **Launchpad / vesting / airdrop:**
  - Merkle leaves include the claimer address, amount and stage, and claimed status is tracked per stage.
  - Vesting schedules can't be changed retroactively by the admin without being stated as a trust assumption.
  - Unclaimed funds have a defined end state.
- **NFT (cw721) and marketplaces:**
  - Approvals are cleared on transfer.
  - Royalties are enforced the way the threat model assumes.
  - Escrowed NFTs and bids can be withdrawn when listings are cancelled.
  - Collection contracts are pinned by address.
- **Bridges / IBC apps:** packet lifecycle, idempotent acks, rate limits and callbacks (see IBC sections), and a single forged message can't release more than the rate limit.
- **DAO / governance:** see Governance bypass. Proposal execution runs arbitrary messages with the DAO's authority, so module and proposal-type allowlists matter.
- **Interchain accounts / interchain queries (Neutron-style):**
  - An ICA on an ordered channel closes on timeout, and the contract must handle the channel being gone.
  - Transaction queries prove inclusion, not completeness: a relayer can skip transactions.
  - Key-value query results carry the height they were proven at, and the contract rejects stale results.
  - Relayer fees and query deposits can't be drained by a third party.

## Testing coverage sign-off
- Every execute branch has a Rust `cw-multitest` case (happy + at least one adversarial).
- Node QA runner exercises the same flows against a live node with real gas/tx costs.
- Final invariant check run after full scenario sequence, not just after each isolated test.

## Severity output format
For each finding: `[SEVERITY] Title — file:line/branch — scenario — fix`. Severities: Critical (funds loss/lock), High (privilege escalation/DoS), Medium (incorrect accounting no direct loss), Low (best-practice), Informational.

## Coverage traceability
No formal numbered vulnerability registry exists specifically for CosmWasm as of this research (unlike EVM's OWASP Top 10 or Solana's canonical Sealevel Attacks list — this is itself a real market gap, see `LIMITATIONS-AND-COMPARISON.md`). State coverage against the two best available anchors instead:

| Chain-agnostic OWASP SC Top 10 (2026) category | Covered by |
|---|---|
| SC01 Access Control | Access control (above) |
| SC02 Business Logic | Governance bypass, Funds handling (above) |
| SC03 Price Oracle Manipulation | Oracle / price (above) |
| SC04 Flash Loan–Facilitated Attacks | Governance bypass — same-block voting-power manipulation (above) |
| SC05 Lack of Input Validation | Input validation (above) |
| SC06 Unchecked External Calls | Reentrancy / submessages — `reply` handler trust (above) |
| SC07 Arithmetic Errors (rounding/precision) | Arithmetic (above) |
| SC08 Reentrancy | Reentrancy / submessages (above) |
| SC09 Integer Overflow/Underflow | Arithmetic — checked `Uint128`/`Decimal` ops (above) |
| SC10 Proxy & Upgradeability | Upgrade / admin key (above) |

| Real disclosed CosmWasm/wasmd finding (Oak Security) | Covered by |
|---|---|
| Unbounded IBC channel-enumeration query DoS | IBC / cross-module query DoS (above) |
| Migration bypassing instantiate-permission restrictions | Migration / restricted code-ID bypass (above) |
| Decimal-mismatched fee math truncating to zero | Arithmetic (above) |

| Real Cosmos incident or disclosure | Covered by |
|---|---|
| Mirror Protocol duplicate position IDs (Terra, 2021–22, ~$90M) | Lists of IDs and duplicates; Balance accounting (above) |
| Levana stale-oracle trading during congestion (Osmosis, Dec 2023, ~$1.1M) | Oracle / price (above) |
| Halborn Bech32 address normalization (20+ chains) | Input validation (above) |
| ASA-2024-007 ibc-hooks timeout reentrancy (Apr 2024) | IBC packet lifecycle (above) |
| CWA-2024-006 non-deterministic module query | Native module messages and queries (above) |

Items beyond both anchors (timestamp/block manipulation specific to `env.block.time`, WriteFlat-style gas blowup, submessage/reply semantics, CW20 `Receive` hook spoofing, IBC packet lifecycle and IBC hooks, storage key collisions, `sudo`/`instantiate2` entry points, slippage/front-running, admin rotation, chain/VM version advisories, off-chain-authorized actions, custom-math differential fuzzing and rounding under repetition, governance vote buying, collateral listing timelocks, IBC rate limits, unsaved storage changes, duplicate IDs in lists, internal-ledger accounting, IBC callbacks and IBC v2, `CosmosMsg::Any`/Stargate forwarding, token-factory denom trust, code-ID-based trust, untrusted payout recipients, `Coin::amount` as `Uint256`, protocol-type checks) are additions from this suite's own research — call these out separately in a report.
