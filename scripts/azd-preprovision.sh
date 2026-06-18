#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

need_cmd az
need_cmd azd
need_cmd terraform
need_cmd jq
need_cmd git

az account show >/dev/null 2>&1 || die "Not logged in to Azure. Run 'az login' first."
mkdir -p "$HARNESS_DIR/.azure"

info "Pre-provision checks passed."
