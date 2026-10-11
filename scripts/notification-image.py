#!/usr/bin/env python3
"""Resolve the current environment tag to a digest; never build an image."""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request


def resolve(fingerprint, request=None):
    if not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        raise RuntimeError("Invalid environment fingerprint")
    repository = "ckrusemd/danish-electricity-prices-r"
    request = request or urllib.request.urlopen
    scope = urllib.parse.urlencode({"service": "ghcr.io", "scope": "repository:" + repository + ":pull"})
    try:
        with request("https://ghcr.io/token?" + scope, timeout=20) as response:
            token = json.load(response)["token"]
        manifest = urllib.request.Request("https://ghcr.io/v2/" + repository + "/manifests/env-" + fingerprint,
            headers={"Authorization": "Bearer " + token,
                     "Accept": "application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json"})
        with request(manifest, timeout=20) as response:
            digest = response.headers.get("Docker-Content-Digest", "")
            payload = json.load(response)
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest) or payload.get("schemaVersion") != 2:
            raise ValueError("Invalid registry manifest")
    except (OSError, ValueError, KeyError, TypeError):
        raise RuntimeError("Verified environment image unavailable: run Build container image for this fingerprint after integration") from None
    return "ghcr.io/" + repository + "@" + digest


def main():
    result = subprocess.run(["bash", "scripts/environment-fingerprint.sh"], capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError("Environment fingerprint failed")
    fingerprint = result.stdout.strip()
    image = resolve(fingerprint)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
            handle.write("image=" + image + "\nenvironment_hash=" + fingerprint + "\n")
    print("Resolved verified environment image " + image)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Environment image resolution failed", file=sys.stderr)
        sys.exit(1)
