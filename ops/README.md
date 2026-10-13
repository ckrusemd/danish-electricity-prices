# Morning publication and notification operations

The two `cron-job-*.json` files are **disabled templates**, with placeholders
only. Nothing in this directory activates a service or sends a notification.
Each template dispatches its own workflow at **05:00, 05:15, and 05:30 in
Europe/Copenhagen**, including daylight saving time. The 05:15 and 05:30 calls
are later admission/recovery opportunities; they are not Pushover POST retries.
Native Actions schedules attempt 05:00, 05:17 and 05:37, then minutes 17/37
in hours 06–08 and minute 37 in hours 09–23 in the same timezone. These are
independent invocations, not a runner waiting or polling. GitHub can delay or
drop them; more cron entries do not guarantee timely morning delivery. An early
or already delivered notification exits after one
lightweight gate job. An eligible notification uses only gate and delivery jobs.

After integration and reviewing rollout, use cron-job.org's free
tier to create the two jobs from these templates. Replace
`<REPOSITORY_ACTIONS_WRITE_PAT>` **inside the service**, never in a tracked file,
with a fine-grained GitHub PAT restricted to
`ckrusemd/danish-electricity-prices`, repository **Actions: write** permission,
and a chosen expiry. The scheduler does not require Contents write or Pushover
credentials. Leave `enabled: false` until the verified environment and state
have been reviewed. Keep `saveResponses: false`. The request is POST, with
JSON content type, API version `2026-03-10`, `ref: master`, and
`scheduled_delivery: "true"` / `trigger_source: "external"`. Publication and
notification have independent daily state, so one can recover when the other
fails. GitHub dispatch acceptance confirms only that a workflow was requested.

The notification gate resolves the current environment fingerprint to the
verified GHCR `env-<hash>` tag and passes an immutable digest to its container.
It never uses `latest` or builds an image. Missing/inaccessible tags fail
clearly; run the verified container workflow after integration and review.
The delivery container verifies R 4.6.1, Quarto 1.10.19, locked packages, and
the mounted source fingerprint before preparing one weather-free snapshot.

## Journal bootstrap and legacy migration

The `electricity-notification-state` branch must exist and contain reviewed
state. All failed GETs, authentication/network errors, invalid JSON, unknown
schemas, and missing state **fail closed**. Never create an empty state merely
because an API request failed.

Before the first rollout, inspect the branch and preserve every legacy
delivery from `delivery-state.json`, `notification-state.json`, `delivery_state`
(`morning=YYYY-MM-DD`, optionally afternoon), and `last_notification_date`.
The reader accepts legacy slot-keyed or date-keyed JSON. An absent branch may
be initialized only after reviewing historical runs and delivery receipts and
confirming no delivery or unresolved attempt needs preservation. A truly new
installation uses this reviewed initial `delivery-state.json`:

```json
{"schema_version":2,"deliveries":{},"attempts":{}}
```

Do not replace existing state with that example. The implementation adds its
canonical journal using a Git tree based on the existing tree, preserving
legacy files and other branch content. Fast-forward-only ref updates prevent
two concurrent claimants from acquiring the same daily slot. Workflow-wide
concurrency also serializes native, external, local, and manual runs with
`cancel-in-progress: false`.

## Acceptance, rejection, and ambiguity

An admitted run freezes its Copenhagen date. After preparing and validating
the body and graph, it commits a `pending` attempt for that date/morning slot
**before** its one Pushover POST. On a valid success response, it immediately
saves `pushover-result.json` locally, then writes `accepted` and the daily
delivery in the same job. The accepted receipt contains no credentials. It is
uploaded as `notification-receipt-<run_id>-<run_attempt>` even when the journal
write fails, with 90-day retention. Receipts retain the admitted date even if
the run crosses midnight. Summaries distinguish accepted-and-recorded,
accepted-unrecorded-manual, receipt-recovered-without-resend, and failures.

An HTTP 4xx response with Pushover `status: 0` is an explicit rejection. The
attempt becomes `rejected`; after configuration is fixed, a later invocation
may claim again. There is no immediate POST retry. If recording the rejection
fails, the attempt remains pending and requires review.

A timeout, lost response, malformed success, HTTP 5xx, or response without a
confirmed request identifier leaves the attempt pending. Later invocations
search that original run's receipt artifact and record a confirmed receipt
**without another POST**. A missing, expired, invalid, or mismatched receipt
blocks delivery, including later dates, for manual review. Recovery cannot
infer delivery from a successful workflow conclusion alone.

For review, inspect the pending journal attempt, original workflow log, and
receipt artifact. If a valid receipt exists, use the normal recovery workflow
or the following command with an existing authorized GitHub token in the
environment; it performs no Pushover POST:

```sh
NOTIFICATION_ATTEMPT=<original-run-id>-<original-run-attempt> \
  python3 scripts/notification-state.py recover
```

If the result is ambiguous, keep the pending record and seek confirmation
from Pushover using the original request identifier when available. Only
confirmed non-acceptance permits a reviewed journal correction to `rejected`;
retain the attempt metadata and record the evidence in the branch commit.
Confirmed acceptance requires recording its matching receipt. Do not clear
an ambiguous attempt to resume automation or use a forced send as recovery.
There is deliberately no automatic pending-expiry policy.

For an intentional manual notification, dispatch with `force_send: true` and
`scheduled_delivery: false`. It bypasses the daily lock and writes no pending
or daily record; accepted-unrecorded-manual is a successful expected outcome.
Scheduled delivery always respects the 05:00 gate and journal, even if the
force flag is set. Electricity supports the morning slot only.

## Local and offline checks

`bash scripts/dispatch-daily-pushover.sh morning` makes one electricity
workflow dispatch and exits. It does not sleep, poll, watch, or dispatch the
weather repository. `--verify` checks present state once, for today's
Copenhagen date, using the local `gh` credential store; it does not wait for
an earlier dispatch or store credentials. Do not run a dispatch until rollout
has been reviewed. Service activation requires access to the external scheduler
account and a repository-scoped PAT; neither is supplied by these templates.

Safe offline checks, requiring no credentials or notification API:

```sh
python3 -m unittest discover -s tests/notifications -p 'test_*.py' -v
Rscript --vanilla tests/notifications/test-content.R
Rscript --vanilla scripts/send-pushover.R --dry-run --fixture
python3 scripts/notification-lint.py
bash scripts/secret-scan.sh
```

Dry-run prints the compact text and writes `.cache/notification-preview.png`.
It reads no Pushover credentials and makes no notification/state API request.
The message uses shared wholesale spot-price period summaries and the shared
three-hour windows, including the signed difference from the six-month low.
Unavailable windows are labeled unavailable. The graph uses actual quarter
prices and the supplied 30 completed days history profile. Body and attachment
limits are 1024 UTF-8 characters and 5 MiB. All timestamp ordering uses UTC;
display labels use Copenhagen, including distinct repeated DST hours.

The secret scanner checks working-tree text, untracked files, notebooks, and
every reachable historical blob. It prints filenames/object identifiers and
counts, never matched values; filenames containing a detected secret are also
redacted. Git/read failures fail the scan. CI parses every repository YAML,
shell script, Python script, and R source/script/test and runs offline policy
tests. PyYAML 6.0.3 is used for YAML parsing.

References: [GitHub dispatch API](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event),
[timezone-aware schedules](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onschedule),
[cron-job.org API](https://docs.cron-job.org/rest-api.html), and
[Pushover limits and responses](https://pushover.net/api).
