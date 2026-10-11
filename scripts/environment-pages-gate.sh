#!/usr/bin/env bash
set -euo pipefail
# Pure admission logic; the workflow reads the independent state branch first.
last_date=${1:-}
local_date=$(TZ=Europe/Copenhagen date ${ELECTRICITY_GATE_NOW:+--date="$ELECTRICITY_GATE_NOW"} +%F)
local_hour=$(TZ=Europe/Copenhagen date ${ELECTRICITY_GATE_NOW:+--date="$ELECTRICITY_GATE_NOW"} +%H)
daily=false
if [[ ${GITHUB_EVENT_NAME:-workflow_dispatch} == schedule || ${SCHEDULED_DELIVERY:-false} == true ]]; then daily=true; fi
deploy=true
if [[ $daily == true ]] && { (( 10#$local_hour < 5 )) || [[ $last_date == "$local_date" ]]; }; then deploy=false; fi
printf 'deploy=%s\ndate=%s\ndaily=%s\n' "$deploy" "$local_date" "$daily"
