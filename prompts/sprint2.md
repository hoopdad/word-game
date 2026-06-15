/fleet You are now in fleet mode. Dispatch sub-agents (via the task tool) in parallel to do the work.

Goals for this sprint:
 - Deliver user-web-ui value with staged orchestration, parallel fan-out, artifact handoffs, gated progression, and bounded remediation loops.
- Success means an application, fully deployed in Azure with all requirements and user flows met.
- Build and deploy the application defined here with fixes described herein.

1. consolidate ./PROMPT.MD, ./sprint1.md, and ./sprint1a.md into docs/requirements.md as a single source of truth of our requirements. Eliminate duplicates and vaguaries, surface unknowns and additional vaguaries in docs/mike-todo.md . Update docs/runbooks/OPERATOR_RUNBOOK.MD to reference docs.requirements.md
2. Our rules make everything private. There is one exception in the requirements to let an ingress be public. The WAF is our ingress and so requires a public endpoint. Red Team and remediate this topic.