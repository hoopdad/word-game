#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/ci-run.sh --target <web|api|agent|shared|infra|all>
EOF
}

log() {
  echo "[ci-run] $*"
}

die() {
  echo "[ci-run] error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

run_workspace() {
  local workspace="$1"
  log "Running lint/test/build for ${workspace}"
  npm --workspace "${workspace}" run lint
  npm --workspace "${workspace}" run test
  npm --workspace "${workspace}" run build
}

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$TARGET" ]] || { usage; die "--target is required"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

require_cmd npm

NODE_REQUIRED=0
INFRA_REQUIRED=0

case "$TARGET" in
  all)
    NODE_REQUIRED=1
    INFRA_REQUIRED=1
    ;;
  web|api|agent|shared)
    NODE_REQUIRED=1
    ;;
  infra)
    INFRA_REQUIRED=1
    ;;
  *)
    usage
    die "unsupported target: $TARGET"
    ;;
esac

if [[ "$NODE_REQUIRED" -eq 1 ]]; then
  log "Installing workspace dependencies"
  npm ci
fi

if [[ "$TARGET" == "all" || "$TARGET" == "shared" ]]; then
  run_workspace "@word-game/shared"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "web" ]]; then
  run_workspace "@word-game/web"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "api" ]]; then
  run_workspace "@word-game/api"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "agent" ]]; then
  run_workspace "@word-game/agent"
fi

if [[ "$INFRA_REQUIRED" -eq 1 ]]; then
  require_cmd terraform
  log "Running Terraform fmt/init/validate for mcaps-infra"
  terraform -chdir=mcaps-infra fmt -recursive -check
  terraform -chdir=mcaps-infra init -backend=false
  terraform -chdir=mcaps-infra validate
fi

log "Target ${TARGET} passed"
