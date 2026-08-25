# CosmWasm / DeFi audit checklist

Go through every item against actual code lines — cite the branch checked, not a blanket "looks fine".

## Access control
- Every `ExecuteMsg` branch checks `info.sender` against expected role (admin/owner/user) explicitly.
- Admin-only actions (pause, upgrade config, withdraw fees) can't be called by arbitrary sender.
- `MigrateMsg` guarded — only current admin/gov can trigger migration, old state shape validated on migrate.
- No unauthenticated funds-moving message.

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

## Funds handling
- `info.funds` validated against expected denom + amount on every payable entry point.
- No entry point that silently accepts and strands unexpected denoms.
- Contract balance invariant: sum of internal ledger == actual bank balance, tested explicitly.
- Withdraw/claim paths can't be called twice for same accrued amount (idempotency / replay guard).

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
- `MigrateMsg` and any "emergency"/bypass code path are checked against the same authority requirements as the normal governance path, or the bypass is explicitly documented as part of the key-compromise ladder in the threat model rather than a silent shortcut.

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

Items beyond both anchors (timestamp/block manipulation specific to `env.block.time`, WriteFlat-style gas blowup) are additions from this suite's own research — call these out separately in a report.
