#!/usr/bin/env bash
set -euo pipefail
# Public GHCR lookup: stdout digest, exit 3 only for a missing tag, 1 for errors.
python3 - "$1" <<'PY'
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

reference = sys.argv[1]
match = re.fullmatch(r"ghcr\.io/([a-z0-9_./-]+):([a-z0-9_.-]+)", reference)
if not match:
    sys.exit("Invalid GHCR environment reference")
repository, tag = match.groups()
try:
    url = "https://ghcr.io/token?" + urllib.parse.urlencode({"service": "ghcr.io", "scope": f"repository:{repository}:pull"})
    with urllib.request.urlopen(url, timeout=30) as response:
        token = json.load(response)["token"]
    request = urllib.request.Request(f"https://ghcr.io/v2/{repository}/manifests/{tag}", headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            digest = response.headers.get("Docker-Content-Digest", "")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            sys.exit(3)
        raise
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("Registry returned no valid immutable digest")
    print(digest)
except urllib.error.HTTPError as error:
    sys.exit(f"GHCR lookup failed (HTTP {error.code}); environment package must be public and available")
except (urllib.error.URLError, TimeoutError, OSError, KeyError, ValueError) as error:
    sys.exit(f"GHCR environment lookup failed: {type(error).__name__}; retry after registry connectivity is restored")
PY
