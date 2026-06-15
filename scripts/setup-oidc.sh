#!/usr/bin/env bash
# Phase 2 — run after bootstrap-prereqs.sh, before the first CD pipeline run.
#
# Creates (or reuses) an Azure AD app registration + service principal,
# adds GitHub OIDC federated credentials for the main branch and pull
# requests, grants Contributor on the target subscription, and writes the
# three required secrets to the GitHub repository.
#
# Idempotent: re-running when the resources already exist is safe.
#
# Required:
#   az login && az account set --subscription <id>   (or set AZURE_SUBSCRIPTION_ID)
#   gh auth login
#
# Optional env overrides:
#   AZURE_SUBSCRIPTION_ID  — defaults to the active az account
#   AZURE_TENANT_ID        — defaults to the active az account tenant
#   OIDC_APP_NAME          — display name for the Azure AD app  (default: wordgame-github-oidc)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "[setup-oidc] $*"; }
ok()    { echo "[setup-oidc] ✓ $*"; }
die()   { echo "[setup-oidc] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
info "checking az and gh auth"

if ! az account show >/dev/null 2>&1; then
  die "not logged in to Azure; run: az login"
fi

if ! gh auth status >/dev/null 2>&1; then
  die "not logged in to GitHub; run: gh auth login"
fi

# ---------------------------------------------------------------------------
# Resolve subscription, tenant, and repo slug
# ---------------------------------------------------------------------------
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-$(az account show --query tenantId -o tsv)}"
OIDC_APP_NAME="${OIDC_APP_NAME:-wordgame-github-oidc}"
GITHUB_REPO="$(gh repo view --json nameWithOwner -q '.nameWithOwner')"

info "subscription : $AZURE_SUBSCRIPTION_ID"
info "tenant       : $AZURE_TENANT_ID"
info "GitHub repo  : $GITHUB_REPO"
info "app name     : $OIDC_APP_NAME"

# ---------------------------------------------------------------------------
# App registration (idempotent)
# ---------------------------------------------------------------------------
info "resolving app registration"
APP_ID="$(az ad app list --display-name "$OIDC_APP_NAME" --query '[0].appId' -o tsv 2>/dev/null || true)"

if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$OIDC_APP_NAME" --query appId -o tsv)"
  ok "created app registration (appId=$APP_ID)"
else
  ok "found existing app registration (appId=$APP_ID)"
fi

# ---------------------------------------------------------------------------
# Service principal (idempotent)
# ---------------------------------------------------------------------------
info "resolving service principal"
SP_OBJECT_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv 2>/dev/null || true)"

if [[ -z "$SP_OBJECT_ID" ]]; then
  az ad sp create --id "$APP_ID" >/dev/null
  SP_OBJECT_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv)"
  ok "created service principal (objectId=$SP_OBJECT_ID)"
else
  ok "found existing service principal (objectId=$SP_OBJECT_ID)"
fi

# ---------------------------------------------------------------------------
# Federated credentials
# ---------------------------------------------------------------------------
# Helper: add a federated credential if one with the given name doesn't exist.
add_federated_credential() {
  local cred_name="$1"
  local subject="$2"
  local existing
  existing="$(az ad app federated-credential list --id "$APP_ID" \
    --query "[?name=='${cred_name}'].id" -o tsv 2>/dev/null || true)"
  if [[ -z "$existing" ]]; then
    az ad app federated-credential create --id "$APP_ID" --parameters "$(
      printf '{"name":"%s","issuer":"https://token.actions.githubusercontent.com","subject":"%s","audiences":["api://AzureADTokenExchange"]}' \
        "$cred_name" "$subject"
    )" >/dev/null
    ok "created federated credential: $cred_name"
  else
    ok "federated credential already exists: $cred_name"
  fi
}

info "configuring federated credentials"
# CD workflow — push to main
add_federated_credential "github-oidc-main" \
  "repo:${GITHUB_REPO}:ref:refs/heads/main"
# CI/CD workflows — pull requests (forward-looking)
add_federated_credential "github-oidc-pr" \
  "repo:${GITHUB_REPO}:pull_request"

# ---------------------------------------------------------------------------
# Role assignment — Contributor on the subscription (idempotent)
# ---------------------------------------------------------------------------
info "checking Contributor role on subscription"
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}"
EXISTING_ROLE="$(az role assignment list \
  --assignee "$SP_OBJECT_ID" \
  --role Contributor \
  --scope "$SCOPE" \
  --query '[0].id' -o tsv 2>/dev/null || true)"

if [[ -z "$EXISTING_ROLE" ]]; then
  az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role Contributor \
    --scope "$SCOPE" >/dev/null
  ok "assigned Contributor on $SCOPE"
else
  ok "Contributor role already assigned"
fi

# ---------------------------------------------------------------------------
# GitHub secrets
# ---------------------------------------------------------------------------
info "writing GitHub secrets"
gh secret set AZURE_CLIENT_ID       --body "$APP_ID"
gh secret set AZURE_TENANT_ID       --body "$AZURE_TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$AZURE_SUBSCRIPTION_ID"
ok "secrets written: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
info "done — OIDC identity is ready"
echo ""
echo "  App registration : $OIDC_APP_NAME ($APP_ID)"
echo "  GitHub repo      : $GITHUB_REPO"
echo ""
echo "Next step: push to main (or run workflow_dispatch) to trigger the first CD run."
echo "After infrastructure is deployed, run scripts/setup-github-vars.sh"
echo "to configure the Entra app variables."
