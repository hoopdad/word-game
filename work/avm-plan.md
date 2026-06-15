# AVM migration plan

## Goal
Move the Terraform stack toward Azure Verified Modules (AVM) without changing the app behavior or widening the security surface.

## Principles
- Prefer AVM for stable, well-supported core resources first.
- Keep bespoke Terraform only where AVM coverage is missing or preview-only.
- Do not mix the migration with functional app changes unless the app depends on the resource shape.

## Suggested order
1. Replace foundational resources that have stable AVM coverage:
   - resource group
   - Key Vault
   - Storage
   - Cosmos DB
2. Migrate networking support where a stable AVM module exists:
   - virtual network
   - private DNS zones
   - private endpoints
3. Migrate compute only after the network shape is stable:
   - Container Apps environment
   - Container Apps workloads
4. Keep preview or unsupported pieces bespoke until the AVM surface is mature:
   - WAF proxy container app
   - Entra-specific integration wiring

## Red-team review
- AVM modules can hide defaults; every resource needs explicit review of public access, identity, diagnostics, and locks.
- Preview modules should not become a hard dependency for the first migration pass.
- If a module cannot express a required zero-trust setting, keep that resource bespoke rather than weakening policy.
- Private networking must remain the source of truth; do not “temporarily” reopen public access to make deployment easier.

## Acceptance criteria
- Each migrated resource has an equivalent output and rollback path.
- Security defaults are explicit in code, not assumed from module defaults.
- The migration can be rolled out in phases without breaking the current app.
