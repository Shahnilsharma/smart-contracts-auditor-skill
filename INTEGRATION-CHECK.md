# Integration check — did the agent actually load the skill?

> **Run the canary check from a context that has NOT read this file.** The whole point of a canary question is that its answer is only knowable by actually loading the skill — if the agent you're testing has this document (or anything that quotes its answer table) anywhere in its current context, the canary passes trivially whether or not the skill loaded, and the check is meaningless. Use a fresh session/conversation for the agent under test, and keep this file open only in a separate window/session where you (the human) compare its answer against what the agent actually said.

Two layers: a **mechanical check** (does the tool's own UI/command confirm the skill is registered) and a **canary check** (ask a question whose correct answer requires having actually read the file, not generic training knowledge — works on any agent, mechanical check or not). Use the canary check as the real test; the mechanical check just tells you the file is *findable*, not that the agent actually read and applied it for a given task.

## 1. Mechanical check (per tool)

### Claude Code (CLI or VS Code extension — same engine, same check)
1. Install: copy `skills/<name>/` to `.claude/skills/<name>/` (project) or `~/.claude/skills/<name>/` (personal).
2. Run `/skills` — the skill should appear in the listing with its name and description.
3. Run `/context` — if the description got truncated by the character budget (rare for a normal-sized description, but check), it'll warn you here; if truncated badly enough, triggering may be unreliable.
4. Optional direct test: `/cosmwasm-defi-architect` (or the matching skill name) invokes it directly regardless of whether your prompt would have auto-triggered it — confirms the file parses and loads without testing trigger-phrase matching.

### Codex (CLI, IDE extension, or ChatGPT desktop app — shared skill discovery)
1. Install: copy `skills/<name>/` to `.agents/skills/<name>/` in the repo (Codex scans this directory upward from your working directory to the repo root).
2. In the ChatGPT desktop app: open the **Skills** sidebar panel — the skill should be listed there with its name/description/file path.
3. In Codex CLI/IDE extension (no confirmed direct listing command as of this check — verify against current Codex docs, this surface has been changing): ask directly, "what skills do you have available in this repo?" — a working integration should name it back correctly. Treat this as the fallback mechanical check if there's no dedicated listing command in your Codex version.

## 2. Canary check (agent-agnostic — use this regardless of what the mechanical check shows)

Ask the question, compare against the expected fingerprint. If the agent gives a generic/wrong answer (not the specific detail below), the skill did not actually load for that turn — re-check installation path and trigger phrasing, don't assume it's working.

| Skill | Ask | Expected fingerprint (specific, not guessable from general knowledge) |
|---|---|---|
| `cosmwasm-defi-architect` | "What's the default chain for this skill, and what happens if I ask you to deploy without telling you which wallet mode to use?" | Names **ZIGChain** specifically (not just "a Cosmos chain"), and says it will **ask** you to choose mnemonic vs. binary/system keyring rather than assuming either. |
| `evm-defi-architect` | "What two testing tools does this skill use together by default, and what's the deploy target if I don't specify a network?" | Names both **Foundry** and **Hardhat 3** (not just one), and says **Sepolia** testnet by default, mainnet only on explicit request. |
| `solana-defi-architect` | "According to this skill, what's the maximum CPI call depth I should design around, and what's the default cluster?" | Names the specific number: max depth **4**, and **devnet** as default. |
| Any of the three | "If I say 'with a team' when asking you to do this, does anything change?" | Describes routing to multi-agent/team mode (architect → contract-engineer → parallel qa-fuzzer/static-analyst → auditor → fix-reviewer) rather than just proceeding with the normal solo pipeline. |

Why these specific questions: each answer requires a detail this suite chose deliberately (ZIGChain as the specific default rather than any Cosmos chain; the specific pairing of Foundry+Hardhat rather than just one; the specific CPI depth number; the team-mode trigger phrase) — not something a general-purpose model would produce from background knowledge alone. A wrong or vague answer is a reliable negative signal; a correct, specific answer is a reliable positive signal.

## If the canary check fails

Most common causes, in order of likelihood:
1. Wrong install path (project-scoped vs personal-scoped, or `.claude/` vs `.agents/` — see the table above).
2. Skill installed but the specific prompt didn't match the trigger description closely enough — try invoking it directly (`/skill-name` on Claude Code) to isolate "does the file load at all" from "does my phrasing trigger it automatically."
3. Character-budget truncation on a tool with many other skills installed (Claude Code's `/context` will show this).
4. Stale cache — some tools only rescan the skills directory on restart; restart the agent/session and retry.
