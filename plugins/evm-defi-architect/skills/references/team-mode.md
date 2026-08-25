# Team mode (multi-agent) — self-contained version

This file exists because an installed skill (via `.skill` upload, `/mnt/skills/user/`, `.claude/skills/`, or `.agents/skills/`) only contains this skill's own folder — it does **not** include the suite repo's `multi-agent/` directory or `PORTABILITY.md`. If you're working inside the full suite repo (this file's parent directories include a sibling `multi-agent/` folder), use that instead — it has the complete playbook, all 6 subagent definitions, and the framework-agnostic role spec. This file is the compressed, standalone equivalent for when that isn't available.

## Roles

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
