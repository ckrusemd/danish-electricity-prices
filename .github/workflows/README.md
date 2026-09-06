# Workflow operations

`deploy-pages.yml` restores the locked R environment, renders `index.Rmd`,
uploads `_site` as a Pages artifact, and deploys it to the `github-pages`
environment. It runs daily, on relevant changes to `master`, and manually.

`security.yml` runs on pushes, pull requests, and manual dispatch. It scans all
reachable Git history for common secret formats and checks required project files.
R syntax is validated during the deployment build after the R environment has
been installed.

## Required settings

1. Set **Pages → Source** to **GitHub Actions**.
2. Keep the repository public for free standard Actions and Pages usage.
3. Keep the default branch named `master`, or update workflow filters before
   renaming it.
4. Protect `master` with pull requests and required status checks before adding
   collaborators.

## Recovery and maintenance

Run the deployment workflow manually after a failed or missed scheduled run.
Do not add mail, Pushover, or other credentials to the workflow. If a credential
is ever committed, revoke it immediately; deleting it later does not remove it
from Git history.

Dependabot groups monthly GitHub Actions updates. Review those pull requests.
Update the R environment with `renv`, commit the resulting `renv.lock`, and let
the deployment workflow rebuild its cache.
