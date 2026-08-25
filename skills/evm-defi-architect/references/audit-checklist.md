# EVM / Solidity audit checklist

OWASP Smart Contract Top 10 (2026, current — the 2026 list restructured from 2025: added Business Logic Vulnerabilities and Proxy & Upgradeability as their own top-level categories, and split arithmetic into Arithmetic Errors/rounding-precision vs. Integer Overflow/Underflow as two distinct entries; re-check `scs.owasp.org/sctop10` periodically since this list is refreshed annually)-based + DeFi-specific items. The 2026 list's own stated theme: real incidents are increasingly composed exploit chains (flash loan supplies capital → oracle manipulation skews a price → a business-logic flaw permits an under-collateralized action → an unchecked external call or proxy weakness finalizes extraction) where each step passes review in isolation — this is why Phase 6 of `agency-audit-methodology.md` (economic/game-theoretic review) and invariant testing matter as much as per-category checklist review, not as a substitute for it. Dollar-loss figures cited in industry writeups are directional/aggregate estimates, not exact per-incident facts — treat as "this category is high-impact," don't repeat specific numbers as verified facts without checking the current source. Go through every item against actual code lines — cite the branch checked, not a blanket "looks fine."

## Access control (historically the largest loss category)
- Every privileged function has an explicit sender/role check as its first statement.
- No `tx.origin` used for authorization.
- Admin functions (pause, fee withdrawal, config change, upgrade) can't be called by arbitrary sender.
- Initializer functions can't be called twice or by an unauthorized caller (upgradeable contracts).
- Role-granting functions themselves are access-controlled (no privilege escalation path).

## Logic errors / business logic
- Fee/interest/reward calculations match the spec exactly — trace one worked example by hand against the code.
- Rounding direction always favors the protocol, not the caller, and is documented.
- State transitions match the intended state machine — no way to skip/reorder required steps.

## Reentrancy
- Checks-effects-interactions ordering on every function with an external call.
- `nonReentrant` guard present wherever state-changing external calls occur.
- Cross-function reentrancy considered (not just same-function) — can a reentrant call into a *different* function exploit intermediate state?
- ERC-777/ERC-721/ERC-1155 callback hooks accounted for as reentry points if those token standards are in scope.

## Flash loan / price manipulation
- No single-block/single-tx spot price used for large-value decisions.
- TWAP or equivalent time-weighted/bounded price source for anything liquidation- or collateral-relevant.
- Governance voting power can't be flash-loan-funded within a single transaction (snapshot-based voting, not live balance).

## Input validation
- Zero-address checks where it would brick funds or permanently disable a role.
- Zero-amount checks where a no-op call would still cost meaningful gas/state bloat.
- Array-length-matching checks before parallel-array loops.
- Struct/parameter bounds checked (no unbounded string/array sizes accepted into storage without limits).

## Oracle manipulation
- Price feed staleness check (heartbeat/timestamp bound).
- Oracle failure (zero/stale price) fails closed, not open.
- Single-oracle dependency flagged as a centralization/manipulation risk if no fallback/aggregation.

## Timestamp / block manipulation
- No high-value decision depends solely on `block.timestamp` or `block.number` in a way a block producer/validator could profitably nudge (miners/validators have limited but nonzero influence over timestamp within protocol-allowed drift) — flag single-block-timestamp-gated auctions, lottery/randomness, or "did the window just close" checks as findings; prefer a grace-period buffer or an external, harder-to-manipulate time source for anything security-critical.
- `block.timestamp`/`blockhash`/`block.prevrandao` never used as the sole source of unpredictability for anything of value (see coding-standards.md).

## Governance bypass
- Voting power used in any on-chain vote is snapshotted (e.g. `ERC20Votes`/checkpoint-based) at proposal creation, not read live at execution — otherwise a flash-loan-funded same-transaction balance spike can manufacture voting power a real long-term holder never had.
- Proposal execution re-derives and checks the specific proposal's on-chain state (passed, quorum met, not already executed, not expired/cancelled) rather than trusting a caller-supplied claim.
- Timelock delay between a passed vote and its execution exists and can't be skipped via an alternate "emergency" code path unless that bypass is itself explicitly gated and documented in the key-compromise ladder.

## Unchecked external calls
- Return values of low-level `.call()`/`.delegatecall()`/`.staticcall()` checked, not ignored.
- Token transfers use `SafeERC20`, not raw `.transfer()`/`.transferFrom()` assumed to revert-on-failure.
- Fee-on-transfer / rebasing token behavior considered if arbitrary tokens can be listed.

## Arithmetic errors — rounding & precision (distinct from overflow/underflow below, per current OWASP taxonomy)
- Every division checked for the direction it rounds and who that favors — default should be "rounds in the protocol's favor," stated explicitly at each division site, not assumed globally.
- Precision loss from mismatched token decimals (e.g. combining an 18-decimal and a 6-decimal token in one calculation) is normalized before the operation, not after.
- A calculation that would legitimately round to zero for a small-but-real input either reverts/rejects rather than silently succeeding as a free action, or charges a documented minimum.

## Integer overflow / underflow (version-dependent)
- Solidity ≥0.8: any `unchecked{}` block justified inline with why overflow/underflow is impossible there.
- Pre-0.8 code (if maintaining legacy): SafeMath used consistently, no raw arithmetic on token amounts.

## Permit front-running / nonce DoS
- Any flow using `permit()` (EIP-2612) as one step inside a larger transaction (e.g. permit-then-deposit) has a fallback path that still works if the permit is front-run — an attacker can watch the mempool, submit the victim's permit signature themselves (consuming the nonce) before the victim's own bundled transaction lands, causing the victim's follow-on deposit/stake call to revert with no loss of funds but a real, exploitable denial-of-service on that specific flow. Flag any permit-dependent flow with no fallback (e.g. a separate `approve()` path, or catching a failed permit and continuing) as a finding.

## Denial of service
- No unbounded loop over a user-growable array/mapping in a single external call.
- No pattern where one malicious actor can permanently block a shared function (e.g. a failing forced ETH transfer in a loop).
- Gas griefing on refund/callback patterns considered (attacker-controlled receive() consuming all forwarded gas).

## Front-running / MEV
- Slippage/minimum-out parameters on any swap/trade-like function.
- Signature-based actions (permit, meta-tx) include a nonce and can't be front-run to grief the signer.

## Upgrade / proxy safety
- Storage layout compatibility checked between implementation versions (no reordered/removed state variables).
- Storage gaps present in upgradeable base contracts.
- Upgrade authority is timelocked/multisig, not a single EOA, for anything holding significant value.

## Testing coverage sign-off
- Every external/public function has a Foundry unit test (happy + revert) and, for numeric/address inputs, a fuzz test.
- System-wide invariants (solvency, no-value-creation, access-control invariants) have Foundry invariant tests with a handler exercising realistic call sequences.
- Hardhat role-based scenario runner covers the same flows against a live node with real gas costs.
- Slither run with all findings triaged; Mythril run on core money-handling contracts for release-grade passes.

## Severity output format
`[SEVERITY] Title — file:line/function — scenario — fix`. Severities: Critical (funds loss/lock, no user interaction needed), High (funds loss under specific conditions / privilege escalation), Medium (incorrect accounting, no direct loss, or governance issue), Low (best-practice), Informational (gas/code-quality).

## Coverage traceability — vs. OWASP Smart Contract Top 10 (2026)
State explicit coverage against this list in the audit report's methodology section:

| Code | OWASP 2026 category | Covered by |
|---|---|---|
| SC01 | Access Control Vulnerabilities | Access control (above) |
| SC02 | Business Logic Vulnerabilities | Logic errors / business logic (above) |
| SC03 | Price Oracle Manipulation | Oracle manipulation (above) |
| SC04 | Flash Loan–Facilitated Attacks | Flash loan / price manipulation (above) |
| SC05 | Lack of Input Validation | Input validation (above) |
| SC06 | Unchecked External Calls | Unchecked external calls (above) |
| SC07 | Arithmetic Errors | Arithmetic errors — rounding & precision (above) |
| SC08 | Reentrancy Attacks | Reentrancy (above) |
| SC09 | Integer Overflow and Underflow | Integer overflow / underflow (above) |
| SC10 | Proxy & Upgradeability Vulnerabilities | Upgrade / proxy safety (above) |

All 10 current-year categories mapped. Items beyond this list (timestamp manipulation, governance bypass, permit front-running/nonce DoS, front-running/MEV generally, DoS) are additions from prior-year OWASP lists, the (deprecated but still tool-relevant) SWC Registry, and this suite's own research — call these out separately in a report so a reader can distinguish "covers the current official baseline" from "goes beyond it."
