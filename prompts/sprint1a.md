/fleet You are now in fleet mode. Dispatch sub-agents (via the task tool) in parallel to do the work.

Goals for this sprint:
 - Deliver user-web-ui value with staged orchestration, parallel fan-out, artifact handoffs, gated progression, and bounded remediation loops.
- Success means an application, fully deployed in Azure with all requirements and user flows met.
- Build and deploy the application defined here with fixes described herein.

You reported that: The infra/WAF/network   lockdown item is blocked on Azure-side destructive migration and runner coordination, so it is deferred in the open PR   with blocker context.
Remember the fixes you were implmenting in sprint1.md and make sure they are fully resolved as part of this sprint.
Remediate this using az cli commands, gh cli commands, changing any secret or RBAC that is needed. Create a plan which can be destructive in this specific instance. Be careful of GitHub Actions minutes so as to not use them all up. If there is an easier way to destroy the resources, such as local terraform imports  with destroy, please do that instead. Then return to the original CI/CD method for creating resources.
In this sprint create a script or scripts that will enable a person to download this repo and child repos, then run the script to configure prequisites that you have done without scripts, such as setting up OICD for GitHub to Azure auth and any config that is not captured in Terraform. Consider the flow of events so that you can separate predecessor and post-run activites. 