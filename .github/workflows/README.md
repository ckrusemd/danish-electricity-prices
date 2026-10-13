# Workflow operations

Publication and notification run independently. Business dates and gates use
`Europe/Copenhagen`, including DST. The external schedule targets 05:00 with
recovery at 05:15 and 05:30. Native GitHub schedules attempt 05:00, 05:17 and
05:37, minutes 17/37 in hours 06–08, then minute 37 in hours 09–23. They may
still be delayed or dropped; only activating the external scheduler adds an
independent timing source. No runner waits for a future clock time.

## Publication

`deploy-pages.yml` checks daily state before starting the R container.
External dispatches use `scheduled_delivery=true` and the same daily gate as
GitHub cron. Source pushes and ordinary manual publication can update the site
during a day. Notebook-only changes validate without publishing.

`build-container.yml` resolves an environment fingerprint to a verified image.
A missing environment is built and tested before publication uses it.
R 4.6.1 and Quarto 1.10.19 are pinned; consumers use the resolved image digest.
Persistent registry build caching avoids identical dependency restores.

Rendering prepares one snapshot, renders five Quarto pages, validates links
and assets, then deploys `_site`. Metadata identifies source, environment,
coverage and timings. The `electricity-pages-state` branch records successful
daily publication. Failure leaves the last successful site available.

## Notification

`daily-pushover.yml` has a lightweight admission gate and a delivery job.
Early or accepted invocations use only the gate. Preparation excludes weather,
so weather or Pages failures do not block notification.

A green workflow with skipped downstream jobs does not prove publication or
delivery. Gate summaries explicitly report admission/skip and the business
date. Check the actual deploy/send job, public snapshot date, and state journal.

`electricity-notification-state` retains accepted deliveries and pending
attempts. The sender makes one POST and records a valid success request ID.
Ambiguous acceptance blocks automatic retransmission. Invalid or unreadable
state is an error, not permission to send again. Legacy dates remain respected.

Use `Rscript --vanilla scripts/send-pushover.R --dry-run --fixture` to inspect text/graph
without credentials or sends. Explicit forced unrecorded tests must not modify
the ordinary daily lock. Real sends use `PUSHOVER_APP_TOKEN` and
`PUSHOVER_USER_KEY` repository secrets.

The optional local dispatcher performs bounded checks and at most one dispatch,
then exits. Later invocations reconcile state. See
[external scheduler setup](../../ops/README.md).

## Validation and recovery

CI uses offline fixtures for calculations, notification state, notebook
execution and publication. Security scanning reports locations without printing
credential values. Review dependency and action updates before merging.

For a failed publication, correct its first error and run publication again.
For uncertain notification delivery, inspect the originating run and recovery
receipt. Confirmed acceptance should be recorded without resending. Unconfirmed
attempts require review before an explicitly authorized resend; do not erase
the state branch.

Scheduler HTTP success confirms dispatch acceptance only. Verify workflow
results and delivery state. After activation, inspect seven consecutive morning
dates, then periodically check token expiry, scheduler activation and workflow
health.

## Settings

- **Pages → Source:** GitHub Actions.
- Keep the repository and verified GHCR image public.
- Default branch: `master`; update filters if renamed.
- Protect `master` with reviewed PRs and required CI/security checks.
- External token: restricted to this repository, **Actions: write**.
- Pushover keys stay in repository secrets; dispatch token stays in the scheduler.
