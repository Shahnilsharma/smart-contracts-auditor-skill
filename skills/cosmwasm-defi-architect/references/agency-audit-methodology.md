# Agency-grade audit methodology

Modeled on how real firms operate (Trail of Bits, OpenZeppelin, Spearbit/Cantina, Certora, and the Code4rena/Sherlock contest-judging standard), not just a vulnerability checklist. Sources synthesized from public methodology pages and audit reports as of mid-2026 — practices evolve, re-check a firm's current published methodology if precision matters for a real engagement. This file is chain-agnostic; pair it with the chain-specific `audit-checklist.md`, `testing-*.md`, and `static-analysis.md` in this skill for the technical detail.

A checklist alone is not an audit. The gap between "ran a linter" and "agency-grade" is mostly these phases, done in this order, with things written down at each step.

## Phase 0 — Scoping & rules of engagement

Before any code review:
- **Define scope explicitly**: which files/contracts/programs are in scope, which commit hash, which are out of scope (e.g. third-party libraries, non-standard/weird tokens unless the protocol explicitly declares support for them — Code4rena's convention: exclude weird-ERC20 findings unless the token is named in scope, except USDT which is always treated as in-scope due to its ubiquity and known non-standard behavior).
- **Define assets at risk**: funds, governance power, protocol-owned data, user data/privacy, availability.
- **Define trust assumptions**: which roles are trusted by design (e.g. "the admin multisig is assumed honest, findings about a malicious admin are informational/centralization-risk, not a vulnerability, unless the architecture claims trustlessness").
- Write this down as a short scope document before touching code — ambiguity here is the single biggest cause of wasted audit time and disputed findings later.

## Phase 1 — Threat modeling (before line-by-line review, before bytecode)

Trail of Bits' stated principle: **audit the architecture before the bytecode**. Inspect upgrade paths, access control, oracle integration, governance, and cross-chain/cross-program message flow first — most catastrophic real-world failures live in these layers, not in isolated function bugs. Concretely:
- Diagram actors, roles, and trust boundaries (who can call what, who can upgrade what, who controls funds custody).
- Diagram money/value flow end to end, including every external dependency (oracles, bridges, other protocols composed with).
- Build a **risk matrix**: for each identified threat, rate **likelihood** (how easy to trigger, does it need a privileged position, a specific market condition, a race) and **impact** (funds lost/locked, governance capture, denial of service, data/privacy loss), then derive severity from the combination — not impact alone. This mirrors the Code4rena/Sherlock judging convention (impact × likelihood → severity), which keeps severity ratings consistent and defensible rather than argued case-by-case.
- **Key-compromise resilience** (Trail of Bits' 2025 point — private key/EOA compromise is one of the largest real-world loss categories and traditional line-by-line audits often don't flag it as a formal finding): explicitly rate where the system sits on this maturity ladder and treat anything below "timelocked multisig" as a finding on any contract holding meaningful value, not just a nice-to-have:
  1. Single EOA controls critical functions — lowest resilience.
  2. Multisig controls critical functions.
  3. Multisig + timelock (delay gives users/monitors a chance to react/exit before a malicious or buggy change lands).
  4. Radical immutability / no privileged control path at all — highest resilience, but least operational flexibility.
- Output of this phase: a written threat model + risk matrix, reviewed with the team *before* deep code review starts, so review time is spent where the actual risk is.

## Phase 2 — Automated analysis (baseline, not the finish line)

Run every applicable static/dynamic tool from this skill's `static-analysis.md`/`testing-*.md` across the full in-scope codebase. Trail of Bits' own published stat from 246 aggregated findings: roughly 78% of the most severe-and-easy-to-exploit flaws were, in principle, catchable by automated static/dynamic tools. Practical implication: **automated tooling is the floor, not the ceiling** — run it first and get it to a clean or fully-triaged state before spending expensive manual-review time on things a tool would have caught in seconds. The remaining ~22% (and essentially all of the subtle, high-severity ones) require manual review of business logic, economic assumptions, and cross-component composition that tools structurally can't reason about.

## Phase 3 — Manual line-by-line review

Use the chain-specific `audit-checklist.md` in this skill. Every item needs a stated check, not a blanket pass. Pay particular attention to the categories tools are weak at:
- Business/economic logic correctness (does the code actually implement the spec, not just "does it compile and not obviously revert").
- Cross-contract/cross-program/cross-chain composability (a function safe in isolation can be unsafe combined with another protocol's callback, hook, or a bridge message).
- Governance and upgrade-path safety (who can change what, how fast, with what checks).
- Rounding/precision direction and who it favors.

## Phase 4 — Dynamic testing (fuzzing / invariant testing)

Use this skill's testing reference for the chain-specific tools (Foundry fuzz+invariant / Hardhat scenarios for EVM; cw-multitest + Node QA runner for CosmWasm; LiteSVM/Mollusk/Surfpool + Trident/anchor-fuzz for Solana). Property/invariant tests should encode the same properties identified in Phase 1's risk matrix (solvency, no-value-creation, access-control invariants, single-method DoS, "user can't get more than entitled") — dynamic testing is most valuable when it's targeted at the specific risks already identified, not just generic fuzzing for its own sake.

## Phase 5 — Formal verification (targeted, for high-value protocols/critical invariants)

Not needed for every engagement, but standard practice at the top end (Certora, Halmos, KEVM, Solidity's built-in SMTChecker for a fast first pass) for a small number of properties that must be provably true — typically solvency/conservation invariants in lending, AMM, or vault-style protocols where a single broken invariant means fund loss at scale. Formal verification complements manual audit; it does not replace it — it proves the specified properties hold, it doesn't validate that the specification itself matches the intended economic design. Recommend this phase explicitly when: TVL/value-at-risk is large, the protocol has a small number of clearly-statable core invariants, and the team can afford the days-to-weeks setup cost. Certora Prover in particular supports EVM chains, Solana, Sui, and Stellar (Solidity/Vyper/Rust/Move/Soroban) as of its current published scope — check current support before assuming coverage for a given chain.

## Phase 6 — Economic / game-theoretic review

Distinct from code correctness: does the *incentive design* hold up under adversarial, profit-maximizing behavior? Cover:
- **Composed exploit chains, not just single-vector findings.** OWASP's current (2026) Smart Contract Top 10 explicitly names this as the dominant real-incident pattern: a flash loan supplies adversarial capital → oracle manipulation skews a price reference → a business-logic flaw permits an under-collateralized action → an unchecked external call or proxy weakness finalizes extraction. Each step can individually pass a category-by-category checklist review while the composition still violates an invariant nobody explicitly declared. The same chain-composition risk applies beyond EVM — e.g. a CosmWasm contract composed with an IBC message from an untrusted chain, or a Solana program CPI-chained through several protocols — so explicitly trace at least one plausible multi-step attack chain across the protocol's actual external dependencies, not just per-function analysis in isolation.
- MEV exposure (frontrunning/sandwiching/backrunning) on every price-sensitive or ordering-sensitive action.
- Flash-loan-funded attacks on any function that reads a live balance/price/voting-power within a single transaction.
- Cost-of-attack vs. value-at-risk: can an adversary profitably manipulate governance, an oracle, or a liquidation path given realistic capital costs (flash loan fees, gas, slippage)? If cost-of-attack < potential extractable value, that's a finding regardless of whether the code has a "bug" in the traditional sense.
- Centralization/collusion risk among privileged roles, rated separately from code vulnerabilities (per Phase 1's key-compromise maturity ladder) rather than folded into a generic severity score.

## Phase 6.5 — Finding validation gate (Discover → Validate, don't skip this)

Well-corroborated finding across 2026 industry data: AI-only vulnerability scanning has a real false-positive/false-negative problem serious enough that the share of security teams relying solely on automated AI testing fell from 29% to 9% in one year, and 78% of organizations report that fully-automated AI scanning misses critical vulnerabilities outright. The state-of-the-art response, used by both academic frameworks (Veritas' Discover→Validate pipeline, MOSAIC-Bench's hand-verification oracle) and production tools (the POCO pattern: describe a vulnerability, generate an executable PoC, only report it if the PoC actually drains funds against a real deployment), is a hard validation gate between "found a candidate issue" and "reported as a confirmed finding."

Apply this before writing any Critical or High severity finding into the report:
1. **Discover**: the manual-checklist/static-analysis/fuzzing passes (Phases 2-4) surface a candidate issue.
2. **Validate**: before it goes in the report as Critical/High, write and run an actual test (Foundry `forge test`, `cw-multitest`, LiteSVM/Mollusk, whichever the chain skill uses) that demonstrates the exploit against the real code — the test should fail/revert-unexpectedly on the vulnerable code and pass/behave-correctly once notionally fixed. If you can't get an executable test to actually demonstrate it, downgrade the finding to a lower severity with an explicit note ("could not construct an executable PoC — flagged as suspected rather than confirmed") rather than reporting it as Critical/High on reasoning alone.
3. Medium/Low/Informational findings don't require this gate — the cost only makes sense where a false positive would waste significant remediation effort or a false negative would be catastrophic.

This directly targets a documented failure mode: LLM-generated "proof of concepts" that look plausible but reference non-existent functions, wrong parameters, or exploit paths that don't actually execute — publishing one of those as a Critical finding is worse than not finding it, since it burns remediation time on something that isn't real and can erode trust in the rest of the report.

## Phase 7 — Report

Structure: scope & methodology recap, executive summary, findings (each: title, **severity from the Phase-1-style impact×likelihood matrix**, location, description, proof-of-concept/exploit scenario where applicable, recommended fix), then a scope/assumptions section stating what was explicitly excluded (per Phase 0) so readers don't mistake "not found" for "checked and safe" on out-of-scope material. Never assign severity from impact alone — state the likelihood reasoning too, so a reader can disagree with a specific input rather than the whole rating.

## Phase 8 — Fix review / re-audit cycle

Real audits are not one-shot. After the team patches findings: re-review every patched line specifically for (a) whether the fix actually closes the reported issue, and (b) whether the fix itself introduced a new issue (very common — patches written under time pressure are a disproportionate source of new bugs). This mirrors Code4rena/Sherlock's standard "mitigation review" round and every major firm's stated re-test step. Track status per finding: Unresolved / Acknowledged-won't-fix / Partially resolved / Resolved / Resolved-but-introduced-new-issue.

## Phase 9 — Deployment verification

Before calling the engagement done: verify the actually-deployed bytecode/program binary matches the audited source exactly — commit hash, compiler/toolchain version, and constructor/init arguments all recorded and checked. "Post-audit drift" (deploying a different build than what was reviewed, even unintentionally via a different compiler flag or a last-minute patch) silently invalidates the audit and is a real, recurring failure mode firms now explicitly check for.

## Phase 10 — Post-deployment: monitoring & incident response

An audit reduces risk, it doesn't eliminate it — treat the following as a required deliverable alongside the audit report, not an optional extra, for anything holding meaningful value:
- **Threat-informed monitoring**: alert thresholds derived directly from Phase 1's risk matrix (e.g. large single-tx withdrawals, oracle price deviation beyond X%, unexpected admin-function calls) — generic monitoring without threat-model grounding tends to alert on the wrong things.
- **Incident response plan**: documented roles/responsibilities during an active incident, decision trees for common scenarios (pause the protocol? which key/multisig can do that, how fast?), and a communication plan — written and rehearsed *before* an incident, not improvised during one.
- **Key-compromise response**: since Phase 1 already rated key-compromise resilience, this should map directly to "if the admin key is compromised, here's exactly what happens and what we do" rather than being a fresh question in a crisis.

## How this maps to the rest of this skill

- Phase 0/1 (scope, threat model, risk matrix, key-compromise ladder) → do this explicitly before/alongside SKILL.md's "architecture pass" step; it's not extra work, it's what that step should already contain.
- Phase 2/3/4 → this skill's `static-analysis.md` + `audit-checklist.md` + `testing-*.md`.
- Phase 5 → mention as a recommendation for high-value protocols; don't attempt to run Certora/Halmos yourself unless tooling is available and the user asks for it specifically — it's a specialist, slow, iterative process.
- Phase 6 → fold into the architecture pass's edge-case list and the audit checklist's oracle/flash-loan/governance items, but call it out as its own explicit review pass in the final report, not buried inside code-level findings.
- Phase 7 → the audit report format described in SKILL.md's audit step should follow this structure, including the explicit scope/assumptions section.
- Phase 8/9/10 → new, and should be added as explicit follow-up offers after the initial audit report: "want me to do a fix-review pass once you've patched these?", "want deployment-verification steps to confirm the deployed build matches?", "want a monitoring/incident-response starter doc based on the risk matrix?"
