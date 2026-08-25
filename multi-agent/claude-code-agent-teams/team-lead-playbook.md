# Team-mode playbook — Claude Code Agent Teams

This maps the 11-phase pipeline in each chain skill's `SKILL.md` (and `references/agency-audit-methodology.md`) onto Anthropic's **Agent Teams** feature in Claude Code — real, currently-experimental multi-agent coordination, not a simulation. Verify current status/syntax against `code.claude.com/docs/en/agent-teams` before relying on exact flag names, this feature is actively evolving.

**Currency note (checked July 2026)**: Agent Teams shipped as a research preview in Claude Code v2.1.32 (Feb 5, 2026). On **June 15, 2026** the internal API had a breaking change: the `TeamCreate`/`TeamDelete` lifecycle tools were removed entirely. There is no team object to create or destroy anymore — every session is implicitly a team the moment you spawn a teammate. The spawn pattern below reflects the *current* (post-June-15) API; if you're on an older Claude Code build, `TeamCreate`-based orchestration may still be what's documented for you — check `claude --version` and the current docs rather than assuming.

## What this is / isn't

- **Is**: a real feature where one Claude Code session (Team Lead) spawns independent teammate sessions, each with its own context window and full tool access, coordinating through a shared task list and a peer-to-peer mailbox (`SendMessage`).
- **Isn't** available in every Claude surface: this requires **Claude Code** (CLI/desktop), not the claude.ai chat interface — chat-interface Claude cannot spawn real parallel teammates. If a user invokes team-mode phrasing outside Claude Code, fall back to the sequential emulation described at the bottom of this file and say so explicitly, don't silently pretend to parallelize.
- Is currently **experimental** — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` set in `settings.json` or the shell environment (no separate lifecycle setup needed as of the June 15, 2026 change — see Setup below). Tell the user this if they haven't enabled it.
- Costs meaningfully more tokens than a solo run (roughly 3-7x reported for plan-mode teams) — mention this tradeoff before spinning up a team for a small/simple contract where the solo pipeline is likely sufficient.

## Setup (current, post-June-15-2026 pattern)

```bash
# .env or shell profile
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```
No `TeamCreate` call, no `team_name`, no teardown — just spawn teammates directly and the session becomes the implicit team. If you see orchestration examples elsewhere using `TeamCreate(team_name=...)`, that's the pre-June-15 pattern and will error on a current build.

## Trigger phrasing

In addition to each chain skill's normal triggers, treat these as **team-mode** requests: "with a team", "multiagent", "multi-agent", "agent team", "as a team", "use N agents", or an explicit `--team` flag. Examples:
- "use the solana auditing skill with a team" → Solana skill, team mode.
- "audit this EVM protocol multiagent" → EVM skill, team mode.
- "use cosmwasm skill" (no team language) → solo mode, follow that skill's `SKILL.md` directly, no Agent Teams involved.

## Roles → teammates

One teammate per role below. **Preloading mechanism, stated accurately**: the subagent `skills` frontmatter field (Claude Code's static per-teammate preload) is not used here and deliberately left out of `agents/*.md` — it can't correctly preload "the relevant chain skill" because the chain (CosmWasm/EVM/Solana) is chosen per engagement, not fixed per role, so a static field on a reusable role definition can't point at one of three different skills. The mechanism that actually works: the **Team Lead tells each teammate which chain directory to read at spawn time**, in the spawn prompt itself (see the Spawn pattern below) — each teammate then reads `skills/<chain>-defi-architect/SKILL.md` directly as its first action. Chain-specific reference files (`audit-checklist.md`, the testing reference(s) — filename varies by chain, see the note in `../portable-role-spec/roles.yaml` — `coding-standards*.md`) live under that same `skills/<chain>-defi-architect/references/` directory; this suite's `agency-audit-methodology.md` is identical across all three chains, so any copy works.

| Teammate | Maps to pipeline phase(s) | Primary output |
|---|---|---|
| `architect` | Phase 0-1 (scope, threat model, risk matrix) + Phase 2/3 (architecture) | Scope doc, threat model, risk matrix, architecture doc |
| `contract-engineer` | Code-writing step | Contract/program source following the chain's coding-standards.md |
| `qa-fuzzer` | QA/testing phase | Unit + fuzz/invariant test suites, QA runner results |
| `static-analyst` | Static analysis phase | Triaged tool output (Slither/Mythril/Echidna for EVM; cw-multitest+clippy+cargo-audit for CosmWasm; LiteSVM/Mollusk/Trident for Solana) |
| `auditor` | Manual checklist + economic review + report | Audit report with impact×likelihood severity |
| `fix-reviewer` | Fix-review/re-audit cycle (runs after patches land) | Per-finding resolution status |

## Dependency graph (what can run in parallel)

```
architect (must go first — everything downstream depends on the threat model + architecture)
   │
   ├──► contract-engineer (writes code against the architecture doc)
   │        │
   │        ├──► qa-fuzzer        ─┐
   │        └──► static-analyst   ─┤  these two run IN PARALLEL once code exists
   │                                │
   │                                ▼
   │                           auditor (needs QA results + static-analysis findings + the
   │                                     architect's threat model/risk matrix — waits on all three)
   │
   └──► (after user patches findings) fix-reviewer
```
Set this up as the shared task list with `qa-fuzzer` and `static-analyst` as sibling tasks with no dependency on each other but both depending on `contract-engineer`'s task, and `auditor` depending on both. (The task-list storage path documented in Feb 2026 was `~/.claude/tasks/{team-name}/`; with the June-15 implicit-team change, confirm the current path/mechanism against `code.claude.com/docs/en/agent-teams` rather than assuming it's unchanged.)

## Spawn pattern (Team Lead prompt)

Current (post-June-15-2026) API — spawn directly via the Agent tool's `name` parameter, no `TeamCreate` step:
```
Use a team to audit this <chain> DeFi protocol end to end.
Read skills/<chain>-defi-architect/SKILL.md and references/agency-audit-methodology.md first.

Spawn (Agent tool, name param — implicit team, no setup call needed):
  Agent(name="architect")          — scope, threat model, risk matrix, architecture doc.
  Agent(name="contract-engineer")  — implement against architect's output once ready.
  Agent(name="qa-fuzzer")          — unit+fuzz+invariant tests once code exists.
  Agent(name="static-analyst")     — run and triage static analysis tools, in parallel with qa-fuzzer.
  Agent(name="auditor")            — manual checklist + economic review + report, once qa-fuzzer and
                                      static-analyst both finish.

Each teammate should read the corresponding definition in multi-agent/claude-code-agent-teams/agents/
and then read skills/<chain>-defi-architect/SKILL.md directly (substitute the actual chain) as its first
action — that's what resolves the chain-specific reference files, not a static frontmatter field.

Have auditor message architect directly (via SendMessage) if a threat-model assumption needs revisiting
mid-review rather than silently guessing. Synthesize all outputs into the final deliverable set.
```
If your Claude Code build still exposes the pre-June-15 `TeamCreate`/`team_name` lifecycle (older version), wrap the same role list in that pattern instead — the roles and dependency graph don't change, only the spawn mechanics do.

## Mailbox usage patterns worth calling out explicitly

- `auditor` → `architect`: "the risk matrix rated oracle staleness as Medium likelihood — I found the staleness check is actually missing entirely, re-rate?"
- `static-analyst` → `qa-fuzzer`: "Slither flagged a reentrancy path in `withdraw()` — can you add a fuzz/invariant case targeting that specific call sequence?"
- `contract-engineer` → `architect`: "the spec says rounding should favor the protocol but doesn't specify direction on the fee split — which way?"

## Fallback: sequential emulation (no real Agent Teams available)

If the user asks for "team mode" in a context without Claude Code Agent Teams (e.g. claude.ai chat, or Agent Teams not enabled), say so, then emulate it as clearly-labeled sequential sections in one response/session — `### [architect]`, `### [contract-engineer]`, `### [qa-fuzzer]`, `### [static-analyst]`, `### [auditor]` — each written as if that role, in order, referencing the prior role's actual output rather than working independently. This gets the structure/rigor benefit (explicit role separation, someone whose only job is the threat model, someone else's only job is fix-review) without genuine parallelism or isolated context windows — be upfront that it's an emulation, not real Agent Teams.

## Alternative: Native Workflows (if inter-agent messaging isn't actually needed)

Claude Code also has (as of mid-2026) a **Native Workflows** feature — fans out subagents from a scripted plan with guaranteed execution order, no peer-to-peer mailbox. This pipeline's roles genuinely benefit from mailbox messaging (auditor↔architect re-rating a risk, static-analyst→qa-fuzzer requesting a targeted test), so Agent Teams is the better default fit here. But if a user wants a cheaper, simpler run and is fine with each role only reporting back to the lead (no direct peer messaging, no mid-review re-negotiation), plain subagents or Native Workflows are a legitimate lighter-weight option — mention this as an alternative if token cost is a stated concern, rather than defaulting everyone into full Agent Teams. Verify current Native Workflows syntax against Claude Code's docs before recommending specifics, this is a newer feature.
