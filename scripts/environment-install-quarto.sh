#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source renvinfra/versions.env
destination=${1:?Usage: environment-install-quarto.sh DESTINATION}
[[ $(uname -m) == x86_64 ]] || { echo 'Pinned Quarto archive requires x86_64' >&2; exit 1; }
download_dir=$(mktemp -d)
trap 'rm -f "$download_dir/quarto.tar.gz"; rmdir "$download_dir"' EXIT
curl --fail --location --retry 3 --output "$download_dir/quarto.tar.gz" \
  "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
printf '%s  %s\n' "$QUARTO_SHA256" "$download_dir/quarto.tar.gz" | sha256sum --check --status
mkdir -p "$destination"
tar -xzf "$download_dir/quarto.tar.gz" --strip-components=1 -C "$destination"
test "$("$destination/bin/quarto" --version)" = "$QUARTO_VERSION"
