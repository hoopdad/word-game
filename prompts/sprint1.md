/fleet You are now in fleet mode. Dispatch sub-agents (via the task tool) in parallel to do the work.

Goals for this sprint:
 - Deliver user-web-ui value with staged orchestration, parallel fan-out, artifact handoffs, gated progression, and bounded remediation loops.
- Success means an application, fully deployed in Azure with all requirements and user flows met.
- Build and deploy the application defined here with fixes described herein.
 
1. It does not appear that a WAF container, based on nginix with OWASP CRS rules blocking the top 10 at least, has been implemented. The container app environment shoudl have private IP addresses only except for the WAF. The WAF can have public- and private-IP addresses. This is a requirement so must be met.
2. The singup process shows the Entra login screen, prompts for permissions, but ends with an error: "Sorry, but we’re having trouble signing you in. AADSTS500113: No reply address is registered for the application." This must be remediated.
3. Make a plan for Terraform migration to use Azure Verified Modules. Use Azure Verified Modules whenever possible going forward, for a more secure and well-architected application. Red Team your plan and iterate until you have a plan with minimal cybersecurity risk.
4.  Let a critic agent review completion of all requirements in PROMPT.MD, nfr.yml,  external-user-pattern.md. Suggest prompt and requirement clarification and consistency improvements to those files into a new file called improvements.md so that we can make this work better for next time.
5. Public Network access must be disabled for all resources except the container app that runs the WAF. Create a VNet and all necessary subnets, with full NSG targeting zero trust network design. This will be a standalone VNet.

Begin versioning each service and web app with 0.1.0 in this iteraiton. Be sure to use the CD process to update the version number so that services and the app return the latest. Display the version number on the web page by the application name. Use semantic versioning and determine whether the changes are breaking (new major version), significant enhancements (new minor version), or any other change (bump patch version).

This ends with a successful run of our CI/CD process where a version of this application meets all requirements and passess tests. Be sure to use the scripts in ./scripts when possible instead of running bespoke commands for the same purpose.
