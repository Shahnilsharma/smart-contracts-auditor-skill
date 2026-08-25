# Solana / Anchor audit checklist

Solana's account model makes its vulnerability classes different from EVM's — reentrancy is structurally limited (CPI depth capped at 4, an account can only be mutated by its owner program), but account-validation bugs are the dominant category instead. Go through every item against actual code lines — cite the instruction/account checked, not a blanket "looks fine."

## Missing signer check (critical — most common critical-severity Solana bug class)
- Every account that authorizes an action is typed `Signer<'info>` (Anchor) or has an explicit `is_signer` check (native) — not just a `Pubkey` equality comparison.
- No privileged instruction reachable by supplying an authority's public key without also supplying their signature.

## Missing/incorrect owner check
- Every account whose data is trusted is typed `Account<'info, T>` (Anchor auto-checks program ownership + discriminator) or has an explicit owner check (native) — not a raw `AccountInfo` deserialized without validation.
- No account accepted that could be owned by a different, attacker-controlled program.

## PDA misuse
- Every PDA derived with `seeds = [...], bump` and the canonical bump stored/reused — no user-supplied bump accepted as instruction input.
- No PDA seed scheme shared across different authority domains/roles (a single "pool" PDA used as both a per-user vault and a protocol treasury, for example) without explicit access-control layered on top.
- `find_program_address`/Anchor `seeds` constraint used consistently, not `create_program_address` with an unchecked bump.

## Account type confusion ("cosplay")
- Anchor's automatic 8-byte discriminator check relied on (via `Account<'info, T>`) for every typed account, so a same-byte-layout account of a different logical type can't be substituted in.
- Native programs without Anchor: explicit type/discriminator tag checked on every deserialized account.

## Account data matching (Sealevel Attacks #1 — distinct from the owner check above)
- For any account whose *field values* matter (not just its type/owner), the fields are explicitly checked against the expected values, not just deserialized and trusted — e.g. an SPL token account's `owner`, `mint`, and `amount` fields are each verified to match what the instruction expects, not merely that the account deserializes as *a* token account of the right owner-program. Passing the owner-check (this file's earlier section) proves the account belongs to the right program; it does not prove its *contents* are the ones this instruction actually needs.

## Duplicate mutable accounts (Sealevel Attacks #6)
- Any instruction taking two or more accounts of the *same type* as separate mutable parameters (e.g. a token-swap instruction with a `from` and `to` account of the same account type) explicitly checks that the two account addresses are not identical — passing the same account for both parameters can let a caller trigger unintended aliasing effects (e.g. crediting and debiting the same account in one call in a way that nets out incorrectly, or bypasses a balance check that assumed the two accounts were distinct).

## Arbitrary CPI
- Every CPI target checked against a known, expected program ID (`Program<'info, KnownProgram>` in Anchor, explicit key comparison in native) before invoking.
- No instruction that CPIs into a program ID taken from unchecked instruction data or a user-supplied account.
- If forwarding a user's signer privileges into a CPI, confirm the receiving program is trusted/whitelisted — forwarding a live user signer into an arbitrary CPI target enables wallet-draining.

## CPI depth / call-chain limits
- Any instruction that itself makes a CPI into a program which is known/expected to further CPI onward has its total call depth checked against Solana's hard cap (max depth 4, i.e. up to 4 nested invocations) — an instruction that assumes it can always CPI one level further will fail unpredictably in production once composed with a protocol that already uses part of that budget.
- No design that relies on a deeply nested CPI chain remaining stable across upgrades of a *dependency* program — if the external program's own CPI depth changes, your instruction can start failing even though your code didn't change.
- Cross-program invocations fanning out to many accounts/programs in one instruction are also checked against compute-unit cost, not just call depth (see Compute budget / DoS below).

## Clock / timestamp manipulation
- Every use of `Clock::get()?.unix_timestamp` (or slot) for time-based logic (vesting cliffs, auction end times, cooldowns, TWAP windows, rate-limit windows) accounts for validator clock behavior: Solana's on-chain clock is validator-derived and can drift/jump slightly, and slot-based timing is more manipulation-resistant than raw unix-timestamp comparisons for anything security-critical (e.g. an auction's "is it still open" check).
- No instruction where a leader/validator has a meaningful, profitable ability to shift the effective execution time of a time-gated action by producing a block with a favorably-drifted timestamp — flag any single-block-timestamp-dependent high-value decision (e.g. "did the auction end in this exact block") as a finding, prefer slot-count-based windows or a grace-period buffer.
- Sysvar-sourced `Clock` accessed via Anchor's typed `Sysvar<'info, Clock>` (see Sysvar spoofing above) rather than trusted from an unchecked account.

## Governance bypass
- Every governance-gated action (parameter change, treasury withdrawal, program upgrade, pause/unpause) is checked against the *actual* on-chain vote/quorum state at execution time, not against a snapshot that could be stale or a caller-supplied claim of "the vote passed."
- Voting power/token balance used for a vote is snapshotted at proposal creation (or another fixed point), not read live at execution — otherwise a flash-loan-style same-transaction balance spike can manufacture voting power that was never actually held by a real long-term stakeholder.
- Proposal execution instructions verify the specific proposal account's state (passed, not already executed, not expired/vetoed) rather than trusting a caller-supplied proposal ID/status without re-deriving it from on-chain data.
- Timelock/delay between a passed vote and its execution exists and can't be skipped by an alternate code path (e.g. an "emergency" instruction that bypasses the same checks the normal path enforces) unless that bypass is itself explicitly gated and documented as part of the key-compromise ladder in the threat model.

## Sysvar spoofing
- Sysvars accessed via Anchor's typed `Sysvar<'info, T>` (validates the sysvar's well-known address) or, in native code, the account address explicitly checked against the expected sysvar pubkey — not trusted from an `AccountInfo` without validation.

## Reinitialization / account lifecycle
- `init` (Anchor) used for account creation, not a manual "first-write" check that could be bypassed or raced.
- Account closing uses `close = destination` (zeroes data + drains lamports atomically) — no hand-rolled close that leaves the account revivable within the same transaction by re-crediting lamports before it's garbage-collected.

## Arithmetic
- All value arithmetic (token amounts, lamports, share calculations) uses checked/saturating math — Rust release builds don't panic on overflow by default.
- Rounding direction in any share/exchange-rate calculation documented and favors the protocol, not the caller.

## Rent exemption
- Every long-lived account confirmed to stay above the rent-exempt minimum after any lamport-draining instruction — an account dropping below it can be purged by the runtime.

## Token program correctness
- `transfer_checked` used (validates mint + decimals) rather than plain `transfer` wherever mixing multiple mints or using Token-2022 with extensions.
- Token-2022 extensions in use (transfer fees, transfer hooks, confidential transfers) explicitly accounted for in the money-flow logic — they change effective transferred amounts and can add hook-triggered external calls.

## Compute budget / DoS
- No unbounded loop over a user-growable account list within a single instruction (compute-unit ceiling makes this fail loudly, but design around it rather than hitting it in production).
- CU cost profiled (via Mollusk) for any instruction doing significant looping/math/CPI fan-out.

## Upgrade authority / admin
- Upgrade authority holder documented (single key / multisig / immutable) and appropriate to the value at stake — single-key upgrade authority on a mainnet-beta program holding significant value is itself a finding.
- Admin-only instructions gated the same way as any other privileged instruction (signer + expected-authority check).

## Testing coverage sign-off
- Every instruction has a LiteSVM unit test (happy + revert).
- CU-sensitive/sysvar-dependent instructions have a Mollusk case.
- Real-dependency CPI paths covered by a Surfpool integration test.
- `anchor fuzz` run at minimum; Trident campaign for money-handling/core logic on a release/audit pass, with explicit invariants (balance conservation, no-value-creation) checked after each fuzzed sequence.

## Severity output format
`[SEVERITY] Title — file:line/instruction — scenario — fix`. Severities: Critical (funds loss/lock, no privileged access needed), High (funds loss under specific conditions / privilege escalation), Medium (incorrect accounting, no direct loss), Low (best-practice), Informational (CU/code-quality).

## Coverage traceability — vs. the canonical Sealevel Attacks list (coral-xyz/sealevel-attacks)
State explicit coverage against this list in the audit report's methodology section — a reader should be able to check every category off, not take completeness on faith:

| # | Sealevel Attacks category | Covered by |
|---|---|---|
| 0 | Signer authorization | Missing signer check (above) |
| 1 | Account data matching | Account data matching (above) |
| 2 | Owner checks | Missing/incorrect owner check (above) |
| 3 | Type cosplay | Account type confusion ("cosplay") (above) |
| 4 | Initialization | Reinitialization / account lifecycle (above) |
| 5 | Arbitrary CPI | Arbitrary CPI (above) |
| 6 | Duplicate mutable accounts | Duplicate mutable accounts (above) |
| 7 | Bump seed canonicalization | PDA misuse (above) |
| 8 | PDA sharing | PDA misuse (above) |
| 9 | Closing accounts | Reinitialization / account lifecycle (above) |
| 10 | Sysvar address checking | Sysvar spoofing (above) |

All 11 canonical categories mapped. Items beyond this list (CPI depth, clock/timestamp manipulation, governance bypass, rent exemption, Token-2022 correctness, compute budget/DoS, upgrade-authority centralization) are additions from this suite's own research, not part of the canonical list — call these out separately in a report so a reader can distinguish "covers the known baseline" from "goes beyond it."
