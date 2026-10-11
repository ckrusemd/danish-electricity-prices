#!/usr/bin/env bash
# One dispatch OR one present-state check; never polls, watches, or sleeps.
set -euo pipefail
repo="${ELECTRICITY_REPOSITORY:-ckrusemd/danish-electricity-prices}"
gh_bin="${GH_BIN:-gh}"
case "${1:-morning}" in
  --verify)
    [ "$#" -eq 1 ] || { echo "Usage: $0 [morning|--verify]" >&2; exit 2; }
    export GITHUB_REPOSITORY="$repo"
    # Use gh's existing credential store; do not persist credentials here.
    GH_TOKEN="$("$gh_bin" auth token)" python3 "$(dirname "$0")/notification-state.py" verify
    ;;
  morning)
    [ "$#" -le 1 ] || { echo "Usage: $0 [morning|--verify]" >&2; exit 2; }
    "$gh_bin" workflow run daily-pushover.yml --repo "$repo" --ref master \
      -f scheduled_delivery=true -f delivery_slot=morning -f trigger_source=local \
      -f dispatch_id="local-morning-$(date +%s)-$$"
    echo "Dispatch submitted; delivery is checked by the workflow gate."
    ;;
  *) echo "Usage: $0 [morning|--verify]" >&2; exit 2 ;;
esac
