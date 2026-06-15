#!/usr/bin/env bash
# Phase 3 — run after infrastructure is deployed (after the first successful CD run).
#
# Sets GitHub repository variables used by the CD workflow for Entra auth
# configuration and deployment settings.  Secrets (AZURE_CLIENT_ID etc.) are
# handled by setup-oidc.sh; this script covers the non-secret variables.
#
# Idempotent: re-running overwrites variables with the same or new values.
#
# Required:
#   gh auth login
#   az login  (only if PUBLIC_APP_URL or AZURE_TENANT_ID are auto-detected)
#
# Required inputs (env vars or interactive prompts):
#   SPA_CLIENT_ID    — Entra app registration client ID for the web SPA
#   API_CLIENT_ID    — Entra app registration client ID for the API
#
# Optional env overrides (auto-detected when possible):
#   AZURE_TENANT_ID                    — from active az account if not set
#   AZURE_LOCATION                     — default: centralus
#   PUBLIC_APP_URL                     — detected from the deployed WAF Container App
#   VITE_ENTRA_SCOPES                  — default: openid,profile,email
#   ENTRA_REQUIRED_SCOPE               — default: access_as_user
#   NAME_PREFIX                        — Terraform name_prefix var (default: wordgame)
#   ENVIRONMENT                        — Terraform environment var  (default: dev)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "[setup-github-vars] $*"; }
ok()    { echo "[setup-github-vars] ✓ $*"; }
die()   { echo "[setup-github-vars] ERROR: $*" >&2; exit 1; }

# Prompt for a variable when not already set and stdin is a tty.
# Exits with an error if the value is still empty in non-interactive mode.
prompt_var() {
  local varname="$1" label="$2"
  if [[ -n "${!varname:-}" ]]; then return; fi
  if [[ -t 0 ]]; then
    read -rp "  ${label}: " "${varname?}"
  fi
  if [[ -z "${!varname:-}" ]]; then
    die "${varname} is required; export it before running or provide it interactively"
  fi
}

# Write a GitHub variable (always overwrites — idempotent).
set_var() {
  local name="$1" value="$2"
  gh variable set "$name" --body "$value"
  ok "$name"
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
info "checking gh auth"
if ! gh auth status >/dev/null 2>&1; then
  die "not logged in to GitHub; run: gh auth login"
fi

# ---------------------------------------------------------------------------
# Resolve AZURE_TENANT_ID
# ---------------------------------------------------------------------------
if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
  if az account show >/dev/null 2>&1; then
    AZURE_TENANT_ID="$(az account show --query tenantId -o tsv)"
    info "auto-detected AZURE_TENANT_ID=$AZURE_TENANT_ID"
  else
    prompt_var AZURE_TENANT_ID "Azure tenant ID"
  fi
fi

# ---------------------------------------------------------------------------
# Resolve SPA and API client IDs
# ---------------------------------------------------------------------------
prompt_var SPA_CLIENT_ID \
  "Entra app registration client ID for the web SPA (VITE_ENTRA_CLIENT_ID)"
prompt_var API_CLIENT_ID \
  "Entra app registration client ID for the API (used in ENTRA_JWT_AUDIENCE)"

# ---------------------------------------------------------------------------
# Resolve public app URL (needed for redirect URIs)
# ---------------------------------------------------------------------------
if [[ -z "${PUBLIC_APP_URL:-}" ]]; then
  _name_prefix="${NAME_PREFIX:-wordgame}"
  _env="${ENVIRONMENT:-dev}"
  _rg="rg-${_name_prefix}-${_env}"
  _app="ca-waf-${_name_prefix}-${_env}"

  info "attempting to auto-detect PUBLIC_APP_URL from az (rg=$_rg app=$_app)"
  if _fqdn="$(az containerapp show \
      --name "$_app" \
      --resource-group "$_rg" \
      --query "properties.configuration.ingress.fqdn" \
      -o tsv 2>/dev/null)"; then
    PUBLIC_APP_URL="https://${_fqdn}"
    info "auto-detected PUBLIC_APP_URL=$PUBLIC_APP_URL"
  else
    info "auto-detect failed (infrastructure may not be deployed yet)"
    prompt_var PUBLIC_APP_URL \
      "Public app URL (e.g. https://ca-waf-wordgame-dev.<id>.<region>.azurecontainerapps.io)"
  fi
fi
# Normalize: strip trailing slash
PUBLIC_APP_URL="${PUBLIC_APP_URL%/}/"

# ---------------------------------------------------------------------------
# Derive remaining values
# ---------------------------------------------------------------------------
AZURE_LOCATION="${AZURE_LOCATION:-centralus}"
VITE_ENTRA_CLIENT_ID="${VITE_ENTRA_CLIENT_ID:-$SPA_CLIENT_ID}"
VITE_ENTRA_AUTHORITY="${VITE_ENTRA_AUTHORITY:-https://login.microsoftonline.com/${AZURE_TENANT_ID}}"
VITE_ENTRA_REDIRECT_URI="${VITE_ENTRA_REDIRECT_URI:-${PUBLIC_APP_URL}}"
VITE_ENTRA_POST_LOGOUT_REDIRECT_URI="${VITE_ENTRA_POST_LOGOUT_REDIRECT_URI:-${PUBLIC_APP_URL}}"
VITE_ENTRA_SCOPES="${VITE_ENTRA_SCOPES:-openid,profile,email}"
ENTRA_JWT_ISSUER="${ENTRA_JWT_ISSUER:-https://login.microsoftonline.com/${AZURE_TENANT_ID}/v2.0}"
ENTRA_JWT_AUDIENCE="${ENTRA_JWT_AUDIENCE:-api://${API_CLIENT_ID}}"
ENTRA_REQUIRED_SCOPE="${ENTRA_REQUIRED_SCOPE:-access_as_user}"
ENTRA_JWKS_URI="${ENTRA_JWKS_URI:-https://login.microsoftonline.com/${AZURE_TENANT_ID}/discovery/v2.0/keys}"

# ---------------------------------------------------------------------------
# Summary before writing
# ---------------------------------------------------------------------------
echo ""
info "variables to set:"
echo "  AZURE_LOCATION                       = $AZURE_LOCATION"
echo "  VITE_ENTRA_CLIENT_ID                 = $VITE_ENTRA_CLIENT_ID"
echo "  VITE_ENTRA_AUTHORITY                 = $VITE_ENTRA_AUTHORITY"
echo "  VITE_ENTRA_REDIRECT_URI              = $VITE_ENTRA_REDIRECT_URI"
echo "  VITE_ENTRA_POST_LOGOUT_REDIRECT_URI  = $VITE_ENTRA_POST_LOGOUT_REDIRECT_URI"
echo "  VITE_ENTRA_SCOPES                    = $VITE_ENTRA_SCOPES"
echo "  ENTRA_JWT_ISSUER                     = $ENTRA_JWT_ISSUER"
echo "  ENTRA_JWT_AUDIENCE                   = $ENTRA_JWT_AUDIENCE"
echo "  ENTRA_REQUIRED_SCOPE                 = $ENTRA_REQUIRED_SCOPE"
echo "  ENTRA_JWKS_URI                       = $ENTRA_JWKS_URI"
echo ""

# ---------------------------------------------------------------------------
# Write GitHub variables
# ---------------------------------------------------------------------------
info "writing GitHub variables"
set_var AZURE_LOCATION                       "$AZURE_LOCATION"
set_var VITE_ENTRA_CLIENT_ID                 "$VITE_ENTRA_CLIENT_ID"
set_var VITE_ENTRA_AUTHORITY                 "$VITE_ENTRA_AUTHORITY"
set_var VITE_ENTRA_REDIRECT_URI              "$VITE_ENTRA_REDIRECT_URI"
set_var VITE_ENTRA_POST_LOGOUT_REDIRECT_URI  "$VITE_ENTRA_POST_LOGOUT_REDIRECT_URI"
set_var VITE_ENTRA_SCOPES                    "$VITE_ENTRA_SCOPES"
set_var ENTRA_JWT_ISSUER                     "$ENTRA_JWT_ISSUER"
set_var ENTRA_JWT_AUDIENCE                   "$ENTRA_JWT_AUDIENCE"
set_var ENTRA_REQUIRED_SCOPE                 "$ENTRA_REQUIRED_SCOPE"
set_var ENTRA_JWKS_URI                       "$ENTRA_JWKS_URI"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
info "done — all GitHub variables are set"
echo ""
echo "Run 'gh variable list' to verify."
