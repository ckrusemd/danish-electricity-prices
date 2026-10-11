#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# Names and bytes: verifier changes and additions/removals also invalidate reuse.
{ printf '%s\0' Dockerfile .dockerignore .Rprofile renv.lock;
  find renvinfra -type f -print0;
  find scripts -maxdepth 1 -type f \( -name 'environment-*.sh' -o -name 'verify-environment.R' \) -print0;
} | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1
