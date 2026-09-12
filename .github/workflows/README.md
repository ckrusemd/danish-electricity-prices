# Workflow operations

`deploy-pages.yml` renders `index.Rmd` in a prebuilt public GHCR container,
uploads `_site` as a Pages artifact, and deploys it to the `github-pages`
environment. It runs daily at 06:00 Europe/Copenhagen time, on relevant
changes to `master`, and manually. Because GitHub cron uses UTC, it triggers
at 04:00 and 05:00 UTC and selects the trigger matching the current
CET/CEST daylight-saving offset. It also sends a Pushover summary at 05:00
Europe/Copenhagen using the `PUSHOVER_APP_TOKEN` and `PUSHOVER_USER_KEY`
repository secrets. The gate uses the triggering cron expression rather than
the actual start time, so GitHub schedule delays do not suppress the jobs.

`build-container.yml` rebuilds and publishes
`ghcr.io/ckrusemd/danish-electricity-prices-r` when the Dockerfile or locked R
environment changes. The image contains R 4.3.3, Pandoc, and the packages in
`renv.lock`.

`security.yml` runs on pushes, pull requests, and manual dispatch. It scans all
reachable Git history for common secret formats and checks required project files.
R syntax is validated during the deployment build inside the container.

## Required settings

1. Set **Pages → Source** to **GitHub Actions**.
2. Keep the repository public for free standard Actions and Pages usage.
3. After the first container publication, set the GHCR package visibility to
   **Public** so Pages runners can pull it without credentials.
4. Keep the default branch named `master`, or update workflow filters before
   renaming it.
5. Protect `master` with pull requests and required status checks before adding
   collaborators.

## Recovery and maintenance

Run the deployment workflow manually after a failed or missed scheduled run.
When `renv.lock` or the Dockerfile changes, let the container workflow finish
before manually running the deployment workflow so `latest` has the matching
environment.
Do not add mail, Pushover, or other credentials to the workflow. If a credential
is ever committed, revoke it immediately; deleting it later does not remove it
from Git history.

Dependabot groups monthly GitHub Actions updates. Review those pull requests.
Update the R environment with `renv`, commit the resulting `renv.lock`, and
allow the container workflow to publish the new image before deploying.
