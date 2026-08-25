# Multi-agent team mode

Two layers, pick based on where you're running:

- **`claude-code-agent-teams/`** — if you're in Claude Code with Agent Teams enabled (experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, requires v2.1.32+): real parallel teammates, own context windows, mailbox messaging. Start with `team-lead-playbook.md`, subagent definitions are in `agents/`.
- **`portable-role-spec/`** — if you're on a different agent framework (CrewAI, LangGraph, AutoGen/AG2, OpenAI Agents SDK, Google ADK/A2A) or no framework at all: `roles.yaml` is the framework-agnostic role/dependency spec, `ADAPTING-OTHER-FRAMEWORKS.md` shows how to wire it into each.

Both encode the same five-to-six-role pipeline (architect → contract-engineer → {qa-fuzzer, static-analyst in parallel} → auditor → fix-reviewer), which mirrors the 11-phase methodology in each chain skill's `references/agency-audit-methodology.md`. Team mode doesn't change *what* gets checked — it changes how the work is parallelized and who has ownership of which phase, so a reviewer questioning a specific finding knows exactly which "agent" is accountable for it.

## Is it worth it?

Team/multi-agent mode costs meaningfully more tokens (Agent Teams: roughly 3-7x a solo session) for the benefit of parallelism and role-isolation (each agent's context stays focused on its own phase instead of one long session juggling all of them). Worth it for a real protocol with non-trivial surface area; probably not worth it for a small single-file contract where the solo pipeline in the chain skill's `SKILL.md` finishes in one pass anyway. If unsure, default to solo mode and offer team mode as an option for anything past prototype scale.
