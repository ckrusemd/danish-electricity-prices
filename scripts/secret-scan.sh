#!/usr/bin/env bash
set -euo pipefail

patterns='(ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----|api[_-]?key[[:space:]]*=[[:space:]]*["'"'][^"'"']{12,}["'"']|password[[:space:]]*=[[:space:]]*["'"'][^"'"']{8,}["'"'])'

scan() {
  local description="$1"
  shift
  if git grep --no-index -n -I -E "$patterns" -- "$@"; then
    echo "Potential secret found while scanning ${description}." >&2
    exit 1
  fi
}

scan "working tree" \
  ':!renv/activate.R' ':!renv.lock' ':!*.ipynb' ':!*.bib' ':!libs/**'

while IFS= read -r commit; do
  if git grep -n -I -E "$patterns" "$commit" -- \
      ':!renv/activate.R' ':!renv.lock' ':!*.ipynb' ':!*.bib' ':!libs/**'; then
    echo "Potential secret found in commit ${commit}." >&2
    exit 1
  fi
done < <(git rev-list --all)

echo "Secret scan passed."
