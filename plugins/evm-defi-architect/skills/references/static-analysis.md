# Static / symbolic analysis tools — commands and triage

Run in this order: Slither always -> Mythril for release/audit-grade passes on money-handling contracts -> Echidna to cross-check invariant coverage on complex state machines. No single tool is sufficient alone — use multiple and triage overlaps.

## Optional fast first-pass: a commercial scanner, if available
If the user has access to a commercial detector-engine scanner (e.g. SolidityScan/CredShields — a purpose-built, 700+-detector engine with a real production track record, notably faster and more deterministic than an LLM-driven checklist pass) or its MCP server is connected, run it first as a cheap, fast triage pass before the deeper tools below — it catches common OWASP-Top-10-pattern issues in seconds and frees the slower manual/Mythril/Echidna passes to focus on business-logic and bespoke-protocol issues a generic scanner won't reason about. Don't treat a commercial scanner's clean result as sufficient on its own — it doesn't replace the manual checklist or the threat-model-driven review in `agency-audit-methodology.md`.

## Slither (fast, always run)
```bash
# Foundry project — Slither auto-detects remappings, invokes forge to build
slither .
# or explicit foundry out dir
slither --foundry-out-directory out .
# JSON for CI diffing
slither . --json slither-report.json
```
Built by Trail of Bits, 80+ detector classes, seconds-scale runtime. Foundry now has native config support for it (`foundry.toml` static-analyzer config) — check current Foundry docs for the exact keys since this integration is recent. Every finding needs a triage line: true positive (fix), false positive (state why), or accepted risk (state why, and who accepted it).

## Mythril (deeper, slower — symbolic execution)
```bash
myth analyze contracts/Vault.sol --execution-timeout 300
```
Better at complex reentrancy chains, integer issues in nested logic, timestamp-dependence forensics with concrete attack paths. Minutes not seconds — run on final/near-final code for core contracts, not every iteration.

## Echidna (property-based fuzzing, complementary to Foundry invariants)
Define properties as public functions returning `bool` (Echidna's own convention, similar spirit to Foundry's `invariant_` handlers but a different engine/corpus) — useful as a second, differently-implemented fuzzer to catch what Foundry's invariant campaign might structurally miss (different call-sequence generation strategy).

## Aderyn (Rust-based static scanner, Cyfrin)
Fast complementary scanner, VS Code extension available; treat as a second opinion alongside Slither rather than a replacement.

## Triage discipline
- Never paste raw tool output as the audit report — every finding gets classified and, if true positive, mapped to a checklist item in `audit-checklist.md` with a concrete fix.
- Track false-positive suppressions explicitly (e.g. `slither.config.json` filters) so the reasoning is visible to future reviewers, not silently hidden.
