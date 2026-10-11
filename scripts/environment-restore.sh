#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source renvinfra/versions.env
export R_LIBS_USER=${1:?Usage: environment-restore.sh LIBRARY}
mkdir -p "$R_LIBS_USER"
test "$(Rscript --vanilla -e 'cat(as.character(getRversion()))')" = "$R_VERSION"
download_dir=$(mktemp -d)
trap 'rm -f "$download_dir/renv.tar.gz"; rmdir "$download_dir"' EXIT
curl --fail --location --retry 3 --output "$download_dir/renv.tar.gz" \
  "https://cran.r-project.org/src/contrib/Archive/renv/renv_${RENV_VERSION}.tar.gz"
printf '%s  %s\n' "$RENV_SHA256" "$download_dir/renv.tar.gz" | sha256sum --check --status
Rscript --vanilla -e 'args <- commandArgs(TRUE); install.packages(args[1], repos=NULL, type="source", lib=Sys.getenv("R_LIBS_USER"))' "$download_dir/renv.tar.gz"
# Restore into an explicit library from a disposable project. This avoids rewriting
# legacy renv/activate.R or user project settings as a side effect of restoration.
Rscript --vanilla -e 'renv::restore(project=tempdir(),lockfile=normalizePath("renv.lock"),library=Sys.getenv("R_LIBS_USER"),prompt=FALSE,strict=TRUE)'
