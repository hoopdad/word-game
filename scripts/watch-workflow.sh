#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <workflow-name> <event> <branch>"
  echo "example: $0 CI pull_request feature/my-branch"
  echo "example: $0 CD push main"
  exit 1
fi

workflow_name="$1"
event_name="$2"
branch_name="$3"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required"
  exit 1
fi

echo "watching workflow=$workflow_name event=$event_name branch=$branch_name"

for _ in $(seq 1 120); do
  line="$(gh run list --workflow "$workflow_name" --event "$event_name" --branch "$branch_name" --limit 1 --json status,conclusion,name --jq 'if length == 0 then "none" else .[0] | "\(.name): \(.status) \(.conclusion)" end')"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $line"

  if [[ "$line" == "none" ]]; then
    sleep 10
    continue
  fi

  if [[ "$line" == *"completed success"* ]]; then
    echo "workflow succeeded"
    exit 0
  fi

  if [[ "$line" == *"completed failure"* || "$line" == *"completed cancelled"* ]]; then
    echo "workflow did not succeed"
    exit 1
  fi

  sleep 10
done

echo "timed out waiting for workflow completion"
exit 1
