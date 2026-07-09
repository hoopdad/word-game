here are some updates to get the application deployed. 

1. Always maintain a documented flow of ci/cd with documented dependency analysis that will make future work easier. Update skills in all the repos that need to be udpated to enforce consistency.
2. report contradicitons in this project's requirements and any repo's agents, instructions, or skills.
3. Create local mcp tools for each repo that requires external system access.
4. make sure that the use of all tools, skills, and agents is enforced. Update .md files as needed for this.

Infrastructure work:
1. make sure the agent, which has been corrected, always prefers AVM. A conflict in  prior runs was missed but should be corrected in that behavior now.
2. running the terraform results in errors. See the terraform errors in tf-err.txt
3. Split the container app deployment out of word-game-infra 

DevOps work:
Do these steps and update skills and agent instructions as needed to insure consistency going forward.
1. make sure all secrets needed for all repos with ci/cd have been created with `gh secret set` in the repo. Organization levle variables or secrets do not work in this environment.
2. As part of any CD that deploys a container app, create a new container app with a consistent root name and use the SHA to create a unique name. In parallel destroy the existing related container app if it exists and re-create it. Use a version in the name so that can be done in parallel, except for WAF. Use out-of-the-box github actions for this when available.
3. Any Entra ID work should be done from this workstation with the logged in az cli.
