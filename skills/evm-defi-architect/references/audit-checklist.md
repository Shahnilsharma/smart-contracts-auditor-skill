# EVM / Solidity audit checklist

OWASP Smart Contract Top 10 (2026, current — the 2026 list restructured from 2025: added Business Logic Vulnerabilities and Proxy & Upgradeability as their own top-level categories, and split arithmetic into Arithmetic Errors/rounding-precision vs. Integer Overflow/Underflow as two distinct entries; re-check `scs.owasp.org/sctop10` periodically since this list is refreshed annually)-based + DeFi-specific items. The 2026 list's own stated theme: real incidents are increasingly composed exploit chains (flash loan supplies capital → oracle manipulation skews a price → a business-logic flaw permits an under-collateralized action → an unchecked external call or proxy weakness finalizes extraction) where each step passes review in isolation — this is why Phase 6 of `agency-audit-methodology.md` (economic/game-theoretic review) and invariant testing matter as much as per-category checklist review, not as a substitute for it. Dollar-loss figures cited in industry writeups are directional/aggregate estimates, not exact per-incident facts — treat as "this category is high-impact," don't repeat specific numbers as verified facts without checking the current source. Go through every item against actual code lines — cite the branch checked, not a blanket "looks fine."

## Access control (historically the largest loss category)
- Every privileged function has an explicit sender/role check as its first statement.
- No `tx.origin` used for authorization.
- Admin functions (pause, fee withdrawal, config change, upgrade) can't be called by arbitrary sender.
- Initializer functions can't be called twice or by an unauthorized caller (upgradeable contracts).
- Role-granting functions themselves are access-controlled (no privilege escalation path).
- Rotating an owner, admin or role holder revokes the old holder everywhere — every role, ownership of existing *and* later-created child contracts, cached addresses. Test it as the old key after rotation; otherwise the obvious incident response doesn't contain a compromise.
- Fund-moving contracts have an emergency pause over deposits, borrows and drawdowns that still lets users withdraw what they already own. Contracts that can't be upgraded (EIP-1167 clones, immutable deployments) need it most, since a bug in them can't be patched.

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
- Listing a new collateral asset or market, or changing an oracle source or collateral weight, is timelocked, and new assets start with conservative caps — with admin rights, an attacker listed a worthless token, inflated its oracle price and borrowed real assets against it (Drift, Apr 2026).

## Timestamp / block manipulation
- No high-value decision depends solely on `block.timestamp` or `block.number` in a way a block producer/validator could profitably nudge (miners/validators have limited but nonzero influence over timestamp within protocol-allowed drift) — flag single-block-timestamp-gated auctions, lottery/randomness, or "did the window just close" checks as findings; prefer a grace-period buffer or an external, harder-to-manipulate time source for anything security-critical.
- `block.timestamp`/`blockhash`/`block.prevrandao` never used as the sole source of unpredictability for anything of value (see coding-standards.md).

## Governance bypass
- Voting power used in any on-chain vote is snapshotted (e.g. `ERC20Votes`/checkpoint-based) at proposal creation, not read live at execution — otherwise a flash-loan-funded same-transaction balance spike can manufacture voting power a real long-term holder never had.
- Proposal execution re-derives and checks the specific proposal's on-chain state (passed, quorum met, not already executed, not expired/cancelled) rather than trusting a caller-supplied claim.
- Timelock delay between a passed vote and its execution exists and can't be skipped via an alternate "emergency" code path unless that bypass is itself explicitly gated and documented in the key-compromise ladder.
- Quorum and pass thresholds are sized against how much voting power can be bought on the open market. If buying enough votes costs less than what one proposal can move, add a veto/guardian path during the timelock and cap what a single proposal can transfer (BonkDAO, Jul 2026: ~$4M of tokens bought, ~$20M drained by a malicious proposal).

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
- Pre-0.8 code (if maintaining legacy): SafeMath used consistently, no raw arithmetic on token amounts. Old unverified contracts still holding value count — Truebit (Jan 2026, ~$26M) was a pre-0.8 pricing function whose overflow made a mint cost zero.
- Hand-rolled math libraries (custom `mulDiv`, fixed-point, bit-shift overflow checks) are differentially fuzzed against a well-audited reference (OZ `Math.mulDiv`, Solady) across the full input range, including 512-bit intermediate cases — Cetus (May 2025, ~$223M) was a flawed custom overflow check.

## Rounding amplified by repetition
- Rounding that loses at most 1 wei per operation is still exploitable when the attacker can repeat the operation many times in one transaction or batch (many tiny swaps, withdrawals or exchange-rate updates). Balancer v2 (Nov 2025, ~$120M) and Bunni (Sep 2025) were both drained this way. Test loops of minimal-size operations and assert the pool invariant or share price can't move in the attacker's favour.

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
- Implementation contracts call `_disableInitializers()` in their constructor — an uninitialized implementation can be initialized by anyone, and for UUPS that means the attacker becomes the implementation's upgrade authority.
- UUPS `_authorizeUpgrade` override carries an access-control check — an empty override lets anyone upgrade every proxy.
- Custom (non-OZ) proxies checked for function-selector clashes between proxy admin functions and implementation functions — the transparent-proxy pattern exists to prevent exactly this.
- No per-proxy configuration set via `constructor` or `immutable` in an upgradeable implementation (it lives in the implementation's bytecode, not proxy storage).

## Deployability & toolchain parity
- Every deployed contract is under the EIP-170 limit (24,576 bytes of runtime code) *with the compiler settings the deploy script actually uses* — check with `forge build --sizes` or the deploy toolchain's equivalent. Flag anything within ~1 KB of the limit, since most fixes will push it over.
- The test and deploy toolchains use the same solc version, `evm_version`, optimizer runs and `via_ir` setting. A Foundry suite passing on one compiler says little about bytecode Hardhat builds on another.

## Uniswap v4 hooks
- Every hook callback (`beforeSwap`, `afterSwap`, `beforeAddLiquidity`, …) checks `msg.sender == poolManager` — Cork (May 2025, ~$11M) left `beforeSwap` callable by anyone while the PoolManager was unlocked.
- Hook state is keyed per pool, and the hook rejects or safely handles pools it didn't expect: anyone can initialize a pool that points at a public hook.
- Hook delta and accounting math rounds against the caller (see "Rounding amplified by repetition").
- Hook code copied from periphery contracts (`BaseHook` etc.) is checked against upstream for security fixes made after the copy — Cork's copy predated an upstream authorization check.

## Transient storage (EIP-1153)
- A transient value lives for the whole transaction, across every call frame — a value set in one call is still visible to a later callback in the same transaction. Clear transient slots after use, and never treat a transient value as authorization (e.g. "the expected callback caller") unless it's cleared before any external call that could reach the same slot.

## Cross-chain messaging & bridges
- Message receivers check the source chain ID and the sending contract's address before acting (`lzReceive`, `_ccipReceive`, Wormhole VAA emitter checks).
- The messaging layer's security configuration is in scope: a LayerZero OApp needs more than one independent required DVN (KelpDAO, Apr 2026: a 1-of-1 DVN verified a forged message and released ~$292M of rsETH). Review CCIP/Wormhole/Hyperlane setups the same way.
- Amounts minted or released per message and per time window are rate-limited, so one forged message can't empty the escrow.

## Off-chain-authorized actions
- Mints, withdrawals or prices approved by an off-chain signer are bounded on-chain: per-transaction and per-period caps, collateral/backing checks, and a signer that is a multisig or HSM rather than one EOA (Resolv, Mar 2026: one key could approve any mint amount; ~80M unbacked USR minted).

## Vault share inflation (ERC-4626 first-depositor / donation attack)
- Empty or near-empty vault: an attacker mints 1 wei of shares, donates assets directly to the vault to inflate the share price, and the next depositor's mint rounds down to 0 (or close to it), so the attacker redeems the victim's deposit. Check for a mitigation: virtual shares/assets offset (OZ ERC4626 `_decimalsOffset()`), dead shares burned on first deposit, or internal accounting that ignores direct transfers.
- Any share price, collateral value or reward-per-token derived from `balanceOf(address(this))` flagged as donation-sensitive — not just ERC-4626 vaults.
- Deposit/mint reverts when it would mint 0 shares, and user-facing deposit paths accept a minimum-shares-out parameter.

## Signature verification & replay
- Signed messages use EIP-712 with a domain separator that includes `chainId` and `verifyingContract`; a domain separator cached at deploy is recomputed if `block.chainid` changes (chain fork) — OZ `EIP712` does this.
- Nonce or used-digest mapping prevents replaying the same signature; deadline/expiry enforced.
- Raw `ecrecover` result checked `!= address(0)` — an invalid signature returns zero, which matches any unset signer variable. Prefer OZ `ECDSA.recover`, which reverts on invalid signatures and rejects malleable high-`s` values.
- The signature bytes are never used as a uniqueness/replay key (malleable) — key on the nonce or the message digest.
- Where contract wallets must be able to sign, ERC-1271 is supported (OZ `SignatureChecker`).

## EOA assumptions after EIP-7702 (Pectra, May 2025)
- No security check treats `tx.origin == msg.sender`, `msg.sender.code.length == 0` or `extcodesize == 0` as proof that the caller can't run code — under EIP-7702 an EOA can delegate to contract code, execute arbitrary logic and reenter while still being `tx.origin`. Flag reentrancy guards, flash-loan guards and anti-bot checks built on these.
- Any ETH or token sent to an EOA can trigger code (a delegated EOA runs its delegate code on calls), so "EOA recipient = no callback" is no longer a safe assumption in CEI reasoning.

## Arbitrary external calls & approval abuse
- No function executes `target.call(data)` where both `target` and `data` come from the caller without an allowlist — a router/multicall/zap that holds standing user approvals can be made to call `token.transferFrom(victim, attacker, amount)` for every user who approved it.
- Contracts that hold user approvals never expose arbitrary-call paths; if external calls must be generic, they run from a separate executor contract that holds no approvals and no funds between transactions.
- `delegatecall` only to immutable/trusted targets — never to a caller-supplied address.

## Read-only reentrancy
- View functions other protocols consume as prices (share price, LP price, `totalAssets`-style getters) can't return inconsistent values mid-execution — e.g. while ETH is sent out during a withdrawal, before balances/supply update. Either update all state before the external call, or make the view revert while the reentrancy lock is held (OZ `_reentrancyGuardEntered()`).
- When *consuming* another protocol's view (Curve/Balancer pool prices, LP-token pricing), check whether that protocol exposes a reentrancy-lock check and call it before trusting the value.

## Chainlink feed edge cases (extends Oracle manipulation above)
- `latestRoundData()` answer checked `> 0`, and `updatedAt` checked against that specific feed's documented heartbeat — not one global constant for all feeds.
- On L2s (Arbitrum, Optimism, Base, etc.), the Chainlink L2 Sequencer Uptime Feed is checked, plus a grace period after the sequencer comes back, before trusting any price — otherwise stale prices during downtime enable unfair liquidations.
- Feeds whose aggregator still enforces `minAnswer`/`maxAnswer`: if the real price crashes below `minAnswer` the feed keeps reporting `minAnswer`. The contract applies its own sanity bounds and fails closed instead of pricing a collapsed asset at the floor. Check the specific feed — most current feeds have these bounds effectively disabled.
- Feed decimals read from `decimals()`, not assumed to be 8.

## Solidity footguns
- `msg.value` never read inside a loop or in a function reachable through a `delegatecall`-based `multicall` — every iteration/sub-call sees the same `msg.value`, so a user pays once and is credited many times.
- `abi.encodePacked` never used with two or more dynamic-type arguments for a hash used as a key, signature payload or commitment (`("a","bc")` and `("ab","c")` collide) — use `abi.encode`.
- Payout and liquidation paths account for tokens with blocklists (USDC, USDT): one blocklisted recipient makes a push-transfer revert, which can DoS a batch payout or block a liquidation — prefer pull-based withdrawals.
- `approve` calls work with USDT-style tokens that require resetting allowance to 0 first and return no bool — use `SafeERC20.forceApprove`.

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

All 10 current-year categories mapped. Items beyond this list (timestamp manipulation, governance bypass, permit front-running/nonce DoS, front-running/MEV generally, DoS, vault share inflation, signature replay, EIP-7702 EOA assumptions, arbitrary-call approval abuse, read-only reentrancy, Chainlink feed edge cases, Solidity footguns, rotation/pause controls, rounding amplified by repetition, custom-math differential fuzzing, deployability/toolchain parity, Uniswap v4 hooks, transient storage, cross-chain messaging, off-chain-authorized actions, governance vote buying) are additions from prior-year OWASP lists, the (deprecated but still tool-relevant) SWC Registry, and this suite's own research — call these out separately in a report so a reader can distinguish "covers the current official baseline" from "goes beyond it."
