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

## Halmos (symbolic testing of `check_*` functions)
Run each `check_` function on its own, under the memory cap and ledger from `agency-audit-methodology.md` Phase 0.5. A timeout or an out-of-memory kill is `INCONCLUSIVE`, not a pass.

## Certora
Needs a Certora API key (paid). Without one, record it as `NOT EXECUTED` with the reason; don't substitute another tool and call it Certora.

## Install and run notes (from real engagements)
- **Python tools on PEP 668 systems** (`pip install` refused): run them through `uvx` without touching system Python — `uvx --from slither-analyzer slither .`, `uvx halmos`.
- **Mythril:** `uvx --from mythril --with "setuptools<81" myth analyze ...` (newer setuptools breaks its `pkg_resources` import). Pass remappings with `--solc-json`, and point it at the project's exact solc version. Mythril analyzes the contract as deployed by its constructor, so code that only becomes reachable after initialization — EIP-1167 clones, initializer-gated templates — is mostly out of its reach; say so in the report and cover those paths with invariant tests instead.
- **Echidna:** use the release binary; it needs `crytic-compile` on `PATH` (`uvx --from crytic-compile crytic-compile` behind a small wrapper script works).
- **Halmos:**
  - Run `forge clean` before Halmos if you built manually; it needs the AST output from its own build.
  - Anchor test selection with `^` (`--match-test '^check_mulDiv$'`), otherwise nothing may match.
  - Set `PYTHONUNBUFFERED=1` when redirecting to a log, or the log stays empty until the end.
  - Full 256-bit multiplication and 512-bit intermediate math often exhaust the solver. Split the property into smaller lemmas (e.g. one per concrete shift amount) instead of raising memory or timeouts.

## Triage discipline
- Never paste raw tool output as the audit report — every finding gets classified and, if true positive, mapped to a checklist item in `audit-checklist.md` with a concrete fix.
- Track false-positive suppressions explicitly (e.g. `slither.config.json` filters) so the reasoning is visible to future reviewers, not silently hidden.
