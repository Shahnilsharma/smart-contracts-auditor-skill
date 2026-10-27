# Team mode (multi-agent) — self-contained version

This file exists because an installed skill (via `.skill` upload, `/mnt/skills/user/`, `.claude/skills/`, or `.agents/skills/`) only contains this skill's own folder — it does **not** include the suite repo's `multi-agent/` directory or `PORTABILITY.md`. If you're working inside the full suite repo (this file's parent directories include a sibling `multi-agent/` folder), use that instead — it has the complete playbook, all 6 subagent definitions, and the framework-agnostic role spec. This file is the compressed, standalone equivalent for when that isn't available.

## Pick the layout first

- **Audit layout** (below): the code already exists, in a repo or deployed, and the job is to audit it. This is the default whenever the request is to audit or review existing code. Work is split by contract, not by phase, and there is no contract-engineer.
- **Build layout** (the roles further down): a new protocol is being designed and written.

The user only has to say "audit this with a team". The lead works out the rest; never ask the user to design the team or write the spawn prompts.

## Audit layout

**Lead** (the session the user is talking to):
1. Phase 0 scope as usual, including "Prepared by" and report format, plus chain, contract addresses and deployed commit if the code is live.
2. List every in-scope contract and write `audit-out/contract-map.md`: who calls whom, who holds funds, the admin/owner/upgrade authority of each contract, shared state.
3. Write one system-wide threat model (Phase 1) over that map.
4. Build the whole workspace once with the release build. If it's deployed, compare each on-chain code hash with that build. A mismatch blocks that contract's audit until the deployed commit is found.
5. Run the fast static tools once over the whole workspace, not once per teammate.
6. Size the team, split the contracts (below), spawn the auditors, keep `audit-out/STATUS.md`.
7. When every auditor has finished, do the cross-group pass (below). Then merge and dedupe: one root cause is one finding, even if two auditors hit it. Make severities consistent across groups, run Phases 6.5 and 6.6, and write the single report.

**Team size:** auditors = min(ceil(contracts / 4), floor(available GB / 6), 4), and at least 2. Read "available" from `free -g`. For example, 13 contracts with 20 GB available gives 3 auditors. Under 5 contracts, a team costs more than it saves: say so and run solo unless the user insists.

**Grouping:** put contracts that call each other or share funds or state with the same auditor, for example a vault, its strategy and its oracle adapter. Balance groups by lines of code, not by count. A contract on the edge between two groups goes into both briefs as "interface only" for the group that doesn't own it.

**Each auditor's spawn prompt** gives the chain skill path, its group, and the paths to `contract-map.md` and the threat model. It tells the auditor to read `SKILL.md`, `references/audit-checklist.md` and `references/agency-audit-methodology.md` first, and to:
- Run the full checklist on its group. List every check it performed, not only the hits.
- Write a proof-of-concept test for every Medium-or-higher finding, following the Phase 4 rules (exact errors, a test that can fail).
- Message the owning auditor when a finding crosses into another group's contract, and the lead when it contradicts the threat model.
- Run one heavy command at a time (build, full test suite, fuzz campaign), under the Phase 0.5 memory cap.
- Write findings to `audit-out/findings/<group>.md` in the report's finding format, and mark each tool it was asked to run as RAN, INCONCLUSIVE or NOT EXECUTED.

**Cross-group pass:** each auditor saw only one side of every boundary. After the groups report, the lead walks only the edges of the contract map: every cross-contract call, reply or callback, and shared-state assumption.

**Use real Agent Teams by default.** Auditors messaging each other about cross-group findings is the point of this layout. Before spawning, check `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. If it isn't `1`, stop and tell the user: add `"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}` to `~/.claude/settings.json` and restart Claude Code, then ask for the team audit again. Fall back to plain subagents (one per group, the lead relaying cross-group findings and doing the cross-group pass itself) only if the user says to go ahead without teams, and say in the report which one ran.

## Build layout — roles

| Role | Does | Depends on |
|---|---|---|
| architect | Scope, threat model, risk matrix, key-compromise resilience rating, architecture doc | (goes first) |
| contract-engineer | Implements the contract against the architecture doc, following `references/coding-standards.md` | architect |
| qa-fuzzer | Unit + fuzz + invariant tests (Foundry) + Hardhat QA runner | contract-engineer |
| static-analyst | Runs and triages Slither/Mythril/Echidna | contract-engineer (runs in parallel with qa-fuzzer) |
| auditor | Manual checklist + economic review + report, severity via impact×likelihood | qa-fuzzer AND static-analyst |
| fix-reviewer | Re-checks patches after findings are addressed | auditor (activates later, not part of the initial pass) |

## Spawn pattern — Claude Code with Agent Teams enabled

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` set in `settings.json` or your shell environment. Current (post-June-15-2026) API spawns teammates directly via the `Agent` tool's `name` parameter — no separate team-creation step:

```
Agent(name="architect")          — scope, threat model, risk matrix, architecture doc
Agent(name="contract-engineer")  — implement once architect's output is ready
Agent(name="qa-fuzzer")          — tests once code exists
Agent(name="static-analyst")     — static analysis, in parallel with qa-fuzzer
Agent(name="auditor")            — report, once qa-fuzzer and static-analyst both finish
```
Each teammate should read this skill's `SKILL.md` and its `references/` directly as its first action — there's no automatic preloading, tell each one explicitly which skill/chain it's working on in the spawn prompt.

## Fallback — no Agent Teams available (chat interface, or an older Claude Code build)

Say so explicitly, then emulate the roles as clearly-labeled sequential sections in one response — `### [architect]`, `### [contract-engineer]`, `### [qa-fuzzer]`, `### [static-analyst]`, `### [auditor]` — each referencing the prior section's actual output. This gets the role-separation discipline without real parallelism or isolated context windows; say plainly that's what's happening rather than implying true concurrent execution occurred.

## Other agent frameworks (CrewAI, LangGraph, AutoGen/AG2, OpenAI Agents SDK, Google ADK)

Not covered in this standalone file — that mapping guide lives in the full suite repo at `multi-agent/portable-role-spec/ADAPTING-OTHER-FRAMEWORKS.md`. If you only have this installed skill and need that, the role table above is enough to hand-translate into any of those frameworks' own agent/task abstractions: one agent per row, edges from the "depends on" column.
