#!/usr/bin/env bash
set -euo pipefail

slot="${1:-morning}"
case "$slot" in
  morning|afternoon) ;;
  *) echo "Usage: $0 {morning|afternoon}" >&2; exit 2 ;;
esac

GH_BIN="${GH_BIN:-/usr/bin/gh}"
MAX_ATTEMPTS="${PUSHOVER_MAX_ATTEMPTS:-3}"
POLL_SECONDS="${PUSHOVER_POLL_SECONDS:-5}"

encoded_repo_file() {
  local repo="$1" branch="$2" path="$3" response
  if response="$($GH_BIN api "repos/$repo/contents/$path?ref=$branch" --jq .content 2>/dev/null)"; then
    printf '%s' "$response"
  fi
}

state_date() {
  local repo="$1" branch="$2" state_slot="$3" encoded expected_date
  expected_date="$(TZ=Europe/Copenhagen date +%F)"
  encoded="$(encoded_repo_file "$repo" "$branch" delivery-state.json)"
  if [ -z "$encoded" ]; then
    encoded="$(encoded_repo_file "$repo" "$branch" notification-state.json)"
  fi
  if [ -z "$encoded" ]; then
    encoded="$(encoded_repo_file "$repo" "$branch" delivery_state)"
    if [ -n "$encoded" ]; then
      printf '%s' "$encoded" | tr -d '\n' | base64 --decode 2>/dev/null |
        sed -n "s/^${state_slot}=//p"
      return 0
    fi
  fi
  if [ -z "$encoded" ] && [ "$state_slot" = "morning" ]; then
    encoded="$(encoded_repo_file "$repo" "$branch" last_notification_date)"
    if [ -n "$encoded" ]; then
      printf '%s' "$encoded" | tr -d '\n' | base64 --decode 2>/dev/null
      return 0
    fi
  fi
  [ -n "$encoded" ] || return 0
  printf '%s' "$encoded" | tr -d '\n' | base64 --decode 2>/dev/null |
    jq -r --arg slot "$state_slot" --arg date "$expected_date" \
      '.deliveries[$slot].date // (if .deliveries[$date][$slot] then $date else empty end)'
}

dispatch_once() {
  local repo="$1" workflow="$2" state_branch="$3" state_slot="$4"
  local dispatch_id run_id expected_date current_date i
  dispatch_id="local-${state_slot}-$(date +%s)-$$-$RANDOM"
  expected_date="$(TZ=Europe/Copenhagen date +%F)"

  current_date="$(state_date "$repo" "$state_branch" "$state_slot")"
  if [ "$current_date" = "$expected_date" ]; then
    echo "Already confirmed $repo $state_slot Pushover delivery for $expected_date"
    return 0
  fi

  echo "Dispatching $repo/$workflow for $state_slot ($dispatch_id)"
  if [ "$repo" = "ckrusemd/pushoverr-weather-forecast" ]; then
    "$GH_BIN" workflow run "$workflow" --repo "$repo" --ref master \
      -f mode=reconcile -f slot="$state_slot" -f dispatch_id="$dispatch_id"
  else
    "$GH_BIN" workflow run "$workflow" --repo "$repo" --ref master \
      -f scheduled_delivery=true -f delivery_slot="$state_slot" -f dispatch_id="$dispatch_id"
  fi

  run_id=""
  for i in $(seq 1 24); do
    run_id="$($GH_BIN run list --repo "$repo" --workflow "$workflow" --event workflow_dispatch \
      --limit 30 --json databaseId,displayTitle \
      --jq ".[] | select(.displayTitle | contains(\"$dispatch_id\")) | .databaseId" | head -n 1)"
    [ -n "$run_id" ] && break
    sleep "$POLL_SECONDS"
  done
  if [ -z "$run_id" ]; then
    echo "Could not find the dispatched GitHub Actions run for $dispatch_id" >&2
    return 1
  fi

  echo "Watching https://github.com/$repo/actions/runs/$run_id"
  "$GH_BIN" run watch "$run_id" --repo "$repo" --exit-status
  current_date=""
  for i in $(seq 1 12); do
    current_date="$(state_date "$repo" "$state_branch" "$state_slot")"
    [ "$current_date" = "$expected_date" ] && break
    sleep "$POLL_SECONDS"
  done
  if [ "$current_date" != "$expected_date" ]; then
    echo "Workflow completed but delivery state is '$current_date', expected '$expected_date'" >&2
    return 1
  fi
  echo "Confirmed $repo $state_slot Pushover delivery for $expected_date"
}

dispatch_with_retry() {
  local repo="$1" workflow="$2" state_branch="$3" state_slot="$4" attempt
  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    if dispatch_once "$repo" "$workflow" "$state_branch" "$state_slot"; then
      return 0
    fi
    echo "Attempt $attempt/$MAX_ATTEMPTS failed for $repo ($state_slot)" >&2
    [ "$attempt" -lt "$MAX_ATTEMPTS" ] && sleep 300
  done
  return 1
}

failures=0
if [ "$slot" = "morning" ]; then
  electricity_status=0
  weather_status=0
  dispatch_with_retry ckrusemd/danish-electricity-prices daily-pushover.yml \
    electricity-notification-state morning &
  electricity_pid=$!
  dispatch_with_retry ckrusemd/pushoverr-weather-forecast daily-pushover.yml \
    weather-notification-state morning &
  weather_pid=$!
  wait "$electricity_pid" || electricity_status=$?
  wait "$weather_pid" || weather_status=$?
  [ "$electricity_status" -eq 0 ] || failures=$((failures + 1))
  [ "$weather_status" -eq 0 ] || failures=$((failures + 1))
else
  dispatch_with_retry ckrusemd/pushoverr-weather-forecast daily-pushover.yml \
    weather-notification-state afternoon || failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures scheduled Pushover delivery task(s) failed" >&2
  exit 1
fi
