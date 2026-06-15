#!/usr/bin/env bash
# bootstrap-prereqs-pre.sh — One-time setup BEFORE deploying infrastructure.
# Sets up GitHub OIDC federation and required GitHub secrets/variables.
#
# Prerequisites: az CLI logged in, gh CLI logged in, SUBSCRIPTION_ID set.
# Usage: SUBSCRIPTION_ID=<sub-id> GITHUB_ORG_REPO=owner/repo ./scripts/bootstrap-prereqs-pre.sh

set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
TENANT_ID="${TENANT_ID:-$(az account show --query tenantId -o tsv)}"
GITHUB_ORG_REPO="${GITHUB_ORG_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
APP_NAME="${APP_NAME:-sp-wordgame-github-oidc}"
RG_NAME="${RG_NAME:-rg-wordgame-dev}"

echo ""
echo "── Subscription : ${SUBSCRIPTION_ID}"
echo "── Tenant       : ${TENANT_ID}"
echo "── Repo         : ${GITHUB_ORG_REPO}"
echo "── SP name      : ${APP_NAME}"
echo ""

APP_ID=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || true)
if [[ -z "${APP_ID}" ]]; then
  echo "Creating Entra app registration..."
  APP_ID=$(az ad app create --display-name "${APP_NAME}" --query appId -o tsv)
  echo "✓ Created app: ${APP_ID}"
else
  echo "✓ Reusing existing app: ${APP_ID}"
fi

SP_OBJ_ID=$(az ad sp show --id "${APP_ID}" --query id -o tsv 2>/dev/null || true)
if [[ -z "${SP_OBJ_ID}" ]]; then
  echo "Creating service principal..."
  SP_OBJ_ID=$(az ad sp create --id "${APP_ID}" --query id -o tsv)
  echo "✓ Created SP: ${SP_OBJ_ID}"
else
  echo "✓ Reusing existing SP: ${SP_OBJ_ID}"
fi

echo "Assigning Contributor role on subscription ${SUBSCRIPTION_ID}..."
az role assignment create \
  --assignee "${SP_OBJ_ID}" \
  --role Contributor \
  --scope "/subscriptions/${SUBSCRIPTION_ID}" \
  --output none 2>/dev/null || echo "  (role assignment may already exist)"

echo "Assigning User Access Administrator role..."
az role assignment create \
  --assignee "${SP_OBJ_ID}" \
  --role "User Access Administrator" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}" \
  --output none 2>/dev/null || echo "  (role assignment may already exist)"

add_federated_credential() {
  local CRED_NAME="$1"
  local SUBJECT="$2"
  EXISTING=$(az ad app federated-credential list --id "${APP_ID}" --query "[?name=='${CRED_NAME}'].id" -o tsv 2>/dev/null || true)
  if [[ -z "${EXISTING}" ]]; then
    az ad app federated-credential create --id "${APP_ID}" --parameters "{
      \"name\": \"${CRED_NAME}\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"${SUBJECT}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }" --output none
    echo "✓ Federated credential created: ${CRED_NAME}"
  else
    echo "✓ Federated credential exists: ${CRED_NAME}"
  fi
}

REPO="${GITHUB_ORG_REPO}"
add_federated_credential "gh-main-push" "repo:${REPO}:ref:refs/heads/main"
add_federated_credential "gh-pr-main" "repo:${REPO}:pull_request"
add_federated_credential "gh-sprint1-push" "repo:${REPO}:ref:refs/heads/feature/sprint1"

echo "Setting GitHub secrets..."
gh secret set AZURE_CLIENT_ID --body "${APP_ID}" --repo "${GITHUB_ORG_REPO}"
gh secret set AZURE_TENANT_ID --body "${TENANT_ID}" --repo "${GITHUB_ORG_REPO}"
gh secret set AZURE_SUBSCRIPTION_ID --body "${SUBSCRIPTION_ID}" --repo "${GITHUB_ORG_REPO}"
echo "✓ GitHub secrets set."

echo "Registering Azure resource providers..."
for NS in Microsoft.App Microsoft.ContainerRegistry Microsoft.DocumentDB \
  Microsoft.Network Microsoft.KeyVault Microsoft.Storage \
  Microsoft.CognitiveServices; do
  az provider register --namespace "${NS}" --wait &
done
wait
echo "✓ Providers registered."

echo ""
echo "══════════════════════════════════════════════════════"
echo "Pre-deploy setup complete."
echo ""
echo "Next steps:"
echo "  1. Commit and push your infra/ changes to feature/sprint1"
echo "  2. Run scripts/reset-rg.sh to destroy/recreate the Azure RG"
echo "  3. After infra deploys, run scripts/bootstrap-prereqs-post.sh"
echo "══════════════════════════════════════════════════════"
