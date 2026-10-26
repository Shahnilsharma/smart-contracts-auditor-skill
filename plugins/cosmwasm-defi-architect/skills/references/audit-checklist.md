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
- `cosmwasm-std` itself is on a release patched for CWA-2024-002 (integer overflow in its math types; fixed in 2.0.2 for the 2.x line) — check the advisory for the patched release on the major version in use.

## Arithmetic
- All token-amount math uses `Uint128`/`Decimal` **checked** ops (`checked_add/sub/mul/div`) — no raw operator on user-influenced values.
- Division/rounding direction always favors the protocol/pool, not the caller (documented explicitly).
- No silent truncation that lets a user round a fee to zero via small amounts — if a fee calculation truncates to zero for a legitimate-sized input, charge a minimum of 1 unit rather than letting it pass free (a disclosed pattern from real CosmWasm audits: `Decimal`-based fee math can truncate to exactly zero even for non-trivial amounts when decimals differ across assets — always normalize decimal places across assets being compared/combined before the calculation, not after).

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
- With IBC hooks (`ibc-hooks` middleware), the `info.sender` of a hook-triggered execute is an address derived from the channel and the remote sender, not the user's own address on this chain — never grant it that user's privileges or balances.

## Storage key collisions
- Every `Item`/`Map`/`IndexedMap` uses a unique namespace string — two storage items declared with the same key (the same `Map::new("balances")` in two modules, or an `Item` key equal to a `Map` prefix) silently read and write the same bytes.
- Namespace strings stay unchanged across migrations unless the `migrate` handler explicitly moves the data.
- Composite keys use `cw-storage-plus` tuple/`PrimaryKey` types, not ad-hoc string concatenation (`format!("{}{}", a, b)` collides the same way `abi.encodePacked` does).

## Other entry points
- `sudo` (callable only by chain modules — gov, scheduler modules, chain-specific callbacks) handles every `SudoMsg` variant defensively; confirm which modules on the target chain can actually invoke it.
- `instantiate2` (predictable addresses): if a factory lets callers choose the salt, a front-runner can claim the salt/address another user expected — derive the salt from the caller's address. Funds sent to a predicted address before instantiation are only safe because the code checksum is part of the address; confirm the expected checksum is the one used.

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
- No `unwrap()`/`expect()`/`panic!` reachable from user input — all fallible ops return `ContractError`.
- String/Addr inputs validated (`deps.api.addr_validate`) before storage or use as key.
- Boundary values tested: 0, 1, max `Uint128`, empty vecs/strings.

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

Items beyond both anchors (timestamp/block manipulation specific to `env.block.time`, WriteFlat-style gas blowup, submessage/reply semantics, CW20 `Receive` hook spoofing, IBC packet lifecycle and IBC hooks, storage key collisions, `sudo`/`instantiate2` entry points, slippage/front-running, admin rotation, chain/VM version advisories, off-chain-authorized actions, custom-math differential fuzzing and rounding under repetition, governance vote buying, collateral listing timelocks, IBC rate limits) are additions from this suite's own research — call these out separately in a report.
