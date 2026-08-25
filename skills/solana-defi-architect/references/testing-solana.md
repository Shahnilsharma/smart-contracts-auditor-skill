# Solana testing pyramid — LiteSVM / Mollusk / Surfpool / fuzzing

Use all tiers that apply; they cover different things and aren't substitutes for each other.

## LiteSVM — fast in-process unit tests
A lightweight SVM that runs directly inside the test process (no separate validator). Fastest tier, use for the bulk of instruction-logic unit tests.

Rust:
```rust
// cargo add --dev litesvm
use litesvm::LiteSVM;
let mut svm = LiteSVM::new();
svm.add_program_from_file(program_id, "target/deploy/program.so")?;
// build + sign + svm.send_transaction(tx)
```
TypeScript:
```ts
import { LiteSVM } from "litesvm";
const svm = new LiteSVM();
svm.addProgramFromFile(programId, "target/deploy/program.so");
const sim = svm.simulateTransaction(tx); // optional pre-check
const result = svm.sendTransaction(tx);
```
Useful controls: `svm.warpToSlot(slot)`, `svm.setSysvar(...)` (clock, rent, etc.), `svm.withSigverify(false)` for isolating logic from signature-verification overhead during iteration, and reading `result.computeUnitsConsumed` for CU accounting.

## Mollusk — isolated single-instruction checks
Precise control over compute budget and feature set for one instruction at a time — good for CU-accounting and edge-case sysvar states.
```rust
// cargo add --dev mollusk-svm
// cargo add --dev mollusk-svm-programs-token   # SPL token helpers
mollusk.set_compute_budget(200_000);
mollusk.set_feature_set(FeatureSet::all_enabled());
mollusk.sysvars.clock = Clock { slot: 1000, epoch: 5, unix_timestamp: 1_700_000_000, ..Default::default() };
```

## Surfpool (Surfnet) — integration tests with realistic cluster state
Drop-in replacement for `solana-test-validator`, but can fetch real mainnet accounts/programs on demand — use when your program CPIs into a real deployed dependency (e.g. an SPL Token program, Jupiter, an oracle program with dozens of accounts) that would be impractical to redeploy locally.
```bash
cargo install surfpool
NO_DNA=1 surfpool start   # NO_DNA=1 when driven by an agent/non-interactive
```
This is the tier to run the role-based sequential QA scenario against (see SKILL.md step 4) — it's the closest to real cluster behavior short of an actual devnet deploy.

## Fuzzing — `anchor fuzz` (fast default) and Trident (release-grade)

`anchor fuzz` (built into the Anchor CLI, Crucible-based coverage-guided fuzzing):
```bash
anchor fuzz init <program_name>
anchor fuzz run <program_name> <test_name> --release
```
Good first-pass fuzzing with minimal setup.

**Trident** (Ackee Blockchain, Solana-Foundation-backed) — the tool used in professional Solana audits, IDL-driven, supports manually-guided fuzzing (target specific tricky code paths deliberately, not just random search), flow-based multi-instruction sequences, and before/after account-state property comparison:
```bash
cargo install trident-cli
trident init
trident fuzz run-debug fuzz_0 trident-tests/fuzz_tests/fuzzing/hfuzz_workspace/fuzz_0/<crash-file>.fuzz   # replay a found crash
```
Requires the program be built with a reasonably current Anchor (0.29.0+ historically — verify current minimum). For a release/audit-grade pass on money-handling instructions, define invariants explicitly (e.g. total token balance conserved across a flow) and let Trident search for sequences that violate them — this is the closest Solana analogue to Foundry's invariant-testing handler pattern in the EVM skill.

## What to run when
- Every instruction: LiteSVM unit test (happy + revert paths).
- CU-sensitive or sysvar-dependent instructions: add a Mollusk case.
- Anything CPI-ing into a real external program: Surfpool integration test.
- Before calling a contract audit-ready: an `anchor fuzz` pass at minimum, a Trident campaign for money-handling/core logic.
