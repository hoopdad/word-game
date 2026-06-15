#!/usr/bin/env bash
# bootstrap-prereqs-post.sh — One-time setup AFTER infrastructure is deployed.
# Configures GitHub repository variables for the CD workflow.
#
# Prerequisites: infra deployed, az CLI logged in, gh CLI logged in.
# Usage: GITHUB_ORG_REPO=owner/repo ./scripts/bootstrap-prereqs-post.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GITHUB_ORG_REPO="${GITHUB_ORG_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
RG_NAME="${RG_NAME:-rg-wordgame-dev}"
NAME_PREFIX="${NAME_PREFIX:-wordgame}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
WAF_APP_NAME="${WAF_APP_NAME:-ca-waf-${NAME_PREFIX}-${ENVIRONMENT}}"
AZURE_LOCATION_VALUE="${AZURE_LOCATION:-$(az group show --name "${RG_NAME}" --query location -o tsv 2>/dev/null || echo centralus)}"

echo "Fetching deployed infrastructure outputs..."

WAF_FQDN=$(az containerapp show \
  --name "${WAF_APP_NAME}" \
  --resource-group "${RG_NAME}" \
  --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")

ACR_SERVER=$(az acr list \
  --resource-group "${RG_NAME}" \
  --query "[0].loginServer" -o tsv 2>/dev/null || echo "")

echo "── WAF FQDN  : ${WAF_FQDN}"
echo "── ACR Server: ${ACR_SERVER}"
echo "── Location  : ${AZURE_LOCATION_VALUE}"
echo ""

set_var() {
  local NAME="$1"
  local VALUE="$2"
  if [[ -n "${VALUE}" ]]; then
    gh variable set "${NAME}" --body "${VALUE}" --repo "${GITHUB_ORG_REPO}"
    echo "✓ ${NAME} = ${VALUE}"
  else
    echo "⚠  ${NAME} skipped (empty value)"
  fi
}

echo "Setting GitHub repository variables..."
set_var "AZURE_LOCATION" "${AZURE_LOCATION_VALUE}"
set_var "WAF_FQDN" "${WAF_FQDN}"

echo ""
if [[ -n "${WAF_FQDN}" && -n "${SPA_CLIENT_ID:-}" && -n "${API_CLIENT_ID:-}" ]]; then
  echo "Configuring Entra GitHub variables via scripts/setup-github-vars.sh..."
  PUBLIC_APP_URL="https://${WAF_FQDN}" \
    SPA_CLIENT_ID="${SPA_CLIENT_ID}" \
    API_CLIENT_ID="${API_CLIENT_ID}" \
    AZURE_LOCATION="${AZURE_LOCATION_VALUE}" \
    NAME_PREFIX="${NAME_PREFIX}" \
    ENVIRONMENT="${ENVIRONMENT}" \
    "${REPO_ROOT}/scripts/setup-github-vars.sh"
  echo "✓ Entra GitHub variables configured."
else
  echo "Entra External ID configuration still required before rerunning CD."
  echo "Set SPA_CLIENT_ID and API_CLIENT_ID, then run:"
  echo "  PUBLIC_APP_URL=https://${WAF_FQDN} SPA_CLIENT_ID=<spa-client-id> API_CLIENT_ID=<api-client-id> ./scripts/setup-github-vars.sh"
  echo ""
  echo "Variables required by CI/CD:"
  echo "  VITE_ENTRA_CLIENT_ID"
  echo "  VITE_ENTRA_AUTHORITY"
  echo "  VITE_ENTRA_REDIRECT_URI"
  echo "  VITE_ENTRA_POST_LOGOUT_REDIRECT_URI"
  echo "  VITE_ENTRA_SCOPES"
  echo "  ENTRA_JWT_ISSUER"
  echo "  ENTRA_JWT_AUDIENCE"
  echo "  ENTRA_REQUIRED_SCOPE"
  echo "  ENTRA_JWKS_URI"
  echo ""
fi

if [[ -n "${WAF_FQDN}" ]]; then
  echo "⚠  Register the following redirect URI in Entra:"
  echo "   https://${WAF_FQDN}/"
  echo "   https://${WAF_FQDN}/auth/callback"
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "Post-deploy setup complete."
if [[ -n "${WAF_FQDN}" && -n "${SPA_CLIENT_ID:-}" && -n "${API_CLIENT_ID:-}" ]]; then
  echo "Run CI/CD (feature/sprint1 → main) to deploy app images."
else
  echo "Complete Entra GitHub variable setup before rerunning CI/CD."
fi
echo "══════════════════════════════════════════════════════"
