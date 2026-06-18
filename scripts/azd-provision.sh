#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$(cd "$HARNESS_DIR/../word-game-infra" && pwd)"
TF_OUTPUT_FILE="$HARNESS_DIR/.azure/tf-outputs.json"

mkdir -p "$HARNESS_DIR/.azure"
cd "$INFRA_DIR"

[ -f terraform.tfstate ] || die "terraform.tfstate not found in $INFRA_DIR. azd provision must complete successfully before outputs can be exported."

terraform output -json > "$TF_OUTPUT_FILE"
info "Terraform outputs exported to $TF_OUTPUT_FILE"
