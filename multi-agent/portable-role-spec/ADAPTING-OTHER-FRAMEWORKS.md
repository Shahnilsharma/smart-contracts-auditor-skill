# Adapting `roles.yaml` to other multi-agent frameworks

`roles.yaml` is a plain description, not a runnable adapter — every framework below has a genuinely different coordination model, so this is a mapping guide, not a drop-in library. Verify current APIs against each framework's own docs before shipping; this space moves fast (as of mid-2026, several of these frameworks had major version changes in the prior 12 months).

## Claude Code Agent Teams (native fit — see `../claude-code-agent-teams/`)
Already built out as real subagent files + a team-lead playbook in this repo. Use that directly if you're on Claude Code.

## CrewAI — role-based crews
Closest conceptual match: `roles.yaml` entries map ~1:1 to CrewAI `Agent` + `Task` objects, and the `depends_on`/`parallel_with` fields map to CrewAI's task `context` (which tasks' outputs feed into this one) and `Process.sequential` vs a manually-parallelized sub-crew.
```python
from crewai import Agent, Task, Crew, Process

architect = Agent(role="architect", goal="Scope, threat-model, architect the contract",
                   backstory="Reads {chain}-defi-architect skill and methodology doc first.")
contract_engineer = Agent(role="contract_engineer", goal="Implement against architecture doc", ...)
# ... one Agent per role in roles.yaml

architect_task = Task(description="...", agent=architect, expected_output="architecture_doc")
engineer_task = Task(description="...", agent=contract_engineer, context=[architect_task], ...)
# qa_task and static_task both context=[engineer_task]; audit_task context=[qa_task, static_task]

crew = Crew(agents=[...], tasks=[architect_task, engineer_task, qa_task, static_task, audit_task],
            process=Process.sequential)  # CrewAI doesn't natively fan out parallel tasks the way
                                          # Agent Teams does — run qa_task/static_task as two
                                          # separate crews/threads if true parallelism matters,
                                          # or accept sequential execution for simplicity.
```

## LangGraph — directed graph
Model each role as a graph node; edges encode `depends_on`. `parallel_with` pairs become two nodes with a common predecessor and a common successor (a fan-out/fan-in in the graph) — this is LangGraph's actual strength, more natural here than in CrewAI.
```python
from langgraph.graph import StateGraph, END

graph = StateGraph(AuditState)
graph.add_node("architect", architect_node)
graph.add_node("contract_engineer", engineer_node)
graph.add_node("qa_fuzzer", qa_node)
graph.add_node("static_analyst", static_node)
graph.add_node("auditor", auditor_node)
graph.add_edge("architect", "contract_engineer")
graph.add_edge("contract_engineer", "qa_fuzzer")
graph.add_edge("contract_engineer", "static_analyst")   # fan-out: both run after engineer
graph.add_edge("qa_fuzzer", "auditor")
graph.add_edge("static_analyst", "auditor")              # fan-in: auditor waits for both
```
Use LangGraph's checkpointing if you want resumability across a long audit run — genuinely useful here given how long a real audit takes.

## OpenAI Agents SDK — explicit handoffs
Handoff-based, so model this as a chain of handoffs rather than a shared graph: `architect` hands off to `contract_engineer`, which hands off to a small parallel dispatch (two separate runs for `qa_fuzzer`/`static_analyst`, whose results you then feed into a final `auditor` agent call). This SDK doesn't have native fan-in the way LangGraph does — you'll orchestrate the "wait for both, then call auditor" step in your own code around two SDK runs.

## AutoGen / AG2 — conversational GroupChat
Put all five roles in one `GroupChat` with a `GroupChatManager`; encode `depends_on` as instructions in each agent's system message ("don't produce your output until architect has posted the architecture doc") rather than as hard structural dependencies — GroupChat is conversational/turn-based, not graph-based, so enforcement is soft (prompt-level) unless you add custom speaker-selection logic that checks a shared state object for prerequisite outputs before allowing a given agent to speak.

## Google ADK / A2A-compatible systems
ADK's hierarchical agent tree plus the Agent2Agent (A2A) protocol is the right fit if you need cross-framework interoperability (e.g. an ADK-orchestrated auditor agent invoking a LangGraph-built qa_fuzzer agent via A2A's standardized task interface) — relevant if your team already has agents built in different frameworks and needs them to talk to each other rather than rebuilding everything in one framework. Model each `roles.yaml` entry as an A2A-exposed task-capable agent; the dependency graph becomes the calling agent's own orchestration logic (ADK's agent tree), not something A2A itself enforces.

## Custom/no framework
`roles.yaml`'s `depends_on`/`produces` fields are already a minimal enough spec to drive a plain script: topologically sort the roles, call your model of choice once per role with that role's `goal` + the outputs it `reads`, and store `produces` in a dict keyed by name for the next role to consume. This is a legitimate option — per the 2026 framework-comparison research, several teams running production multi-agent systems have concluded the framework choice matters less than getting the dependency/state-passing logic right, which a five-role linear-ish pipeline like this one doesn't really need a heavyweight framework for.
