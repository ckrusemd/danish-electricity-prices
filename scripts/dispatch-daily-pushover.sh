#!/usr/bin/env bash
set -euo pipefail

slot="${1:-morning}"

if [ "$slot" = "morning" ]; then
  /usr/bin/gh workflow run 'Build and deploy electricity prices' \
    --repo ckrusemd/danish-electricity-prices \
    --ref master \
    -f send_notification=true \
    -f scheduled_delivery=true
fi

/usr/bin/gh workflow run 'Publish weather dashboard' \
  --repo ckrusemd/pushoverr-weather-forecast \
  --ref master \
  -f send_notification=true \
  -f scheduled_delivery=true \
  -f delivery_slot="$slot"
