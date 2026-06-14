# Azure Infrastructure (Terraform)

This directory contains Terraform IaC for the baseline Azure platform used by the word game stack.

## What this deploys

- Resource group
- Azure Container Apps managed environment
- Three placeholder container apps:
  - `web`
  - `api`
  - `agent`
- Azure Container Registry (ACR)
- User-assigned managed identity
- RBAC scaffolding:
  - `AcrPull` for the managed identity on ACR
  - `Cosmos DB Account Reader Role` for the managed identity on Cosmos DB account
  - `Cognitive Services OpenAI User` for the managed identity on OpenAI account
- Cosmos DB account + SQL database + SQL container placeholders
- Azure OpenAI account (`azurerm_cognitive_account`)
- Azure AI Foundry project/deployment placeholders (`azapi_resource`)

## Regional defaults and overrides

The default (and required baseline) deployment region is **`centralus`** for ACA, Cosmos DB, Azure OpenAI/Foundry, and other regional services via:

- `variable "location"` default in `variables.tf`
- `terraform.tfvars.example`

Override options:

1. Edit `terraform.tfvars`:
   ```hcl
   location = "eastus2"
   ```
2. Use CLI var:
   ```bash
   terraform plan -var "location=eastus2"
   ```
3. Use env var:
   ```bash
   export TF_VAR_location=eastus2
   ```

## Required inputs and secrets

Copy and edit the example vars file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Populate at least:

- `name_prefix`
- `environment`
- `tags`

No static secrets are committed. Terraform auth should come from Azure CLI or service principal environment variables:

- `az login` (local interactive), or
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Validation commands used for this task

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
```

If `terraform init` or `terraform validate` fails in your environment due to provider download/auth constraints, capture and follow the exact error message shown by Terraform.
