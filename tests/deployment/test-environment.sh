#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
for script in scripts/environment-*.sh; do bash -n "$script"; done
hash=$(bash scripts/environment-fingerprint.sh)
[[ $hash =~ ^[0-9a-f]{64}$ ]]
[[ $(cd /tmp && bash "$OLDPWD/scripts/environment-fingerprint.sh") == "$hash" ]]
gate() {
  GITHUB_EVENT_NAME=$1 SCHEDULED_DELIVERY=$2 ELECTRICITY_GATE_NOW=$3 bash scripts/environment-pages-gate.sh "$4"
}
[[ $(gate schedule false '2026-10-11T02:59:00Z' '') == *deploy=false* ]]
[[ $(gate schedule false '2026-10-11T03:00:00Z' '') == *deploy=true* ]]
[[ $(gate workflow_dispatch true '2026-10-11T03:00:00Z' '2026-10-11') == *deploy=false* ]]
[[ $(gate schedule false '2026-01-11T04:00:00Z' '') == *deploy=true* ]]
[[ $(gate push false '2026-10-11T03:00:00Z' '2026-10-11') == *deploy=true* ]]
[[ $(gate workflow_dispatch false '2026-10-11T03:00:00Z' '2026-10-11') == *deploy=true* ]]
[[ $(gate schedule false '2026-10-25T04:00:00Z' '2026-10-24') == *deploy=true* ]]
echo 'Deployment fingerprint, shell syntax, daily gate and DST tests passed'
