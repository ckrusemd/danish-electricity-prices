#!/usr/bin/env bash
# Scan tracked/untracked text and every historical blob, including notebooks.
# Findings report locations/counts only; matched values never reach output.
set -euo pipefail
python3 - <<'PY'
import os
import re
import subprocess
import sys

patterns = [
    re.compile(rb"ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(rb"AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(rb"-----BEGIN (?:RSA |OPENSSH |EC |DSA |PGP )?PRIVATE KEY-----"),
    re.compile(rb"(?:api[_-]?key|password|passwd|pushover_(?:app_token|user_key)|openweathermap_apikey)\s*[=:]\s*[\"']([A-Za-z0-9_+/=-]{12,})[\"']", re.I),
]

def git(*args):
    result = subprocess.run(["git", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError("Git secret-scan operation failed")
    return result.stdout

def matches(data):
    # Binary blobs are omitted; UTF-8 notebook JSON and Rmd are scanned.
    if b"\x00" in data:
        return False
    return any(pattern.search(data) for pattern in patterns)

try:
    git("rev-parse", "--show-toplevel")
    findings = 0
    paths = git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\x00")
    for path in sorted(set(paths)):
        if not path:
            continue
        try:
            if os.path.islink(os.fsdecode(path)):
                data = os.fsencode(os.readlink(os.fsdecode(path)))
            else:
                with open(os.fsdecode(path), "rb") as source:
                    data = source.read()
        except FileNotFoundError:
            # Tracked deletions have no working-tree content; history is scanned.
            if os.path.lexists(os.fsdecode(path)):
                raise RuntimeError("Unreadable working-tree file")
            continue
        except OSError:
            raise RuntimeError("Unreadable working-tree file") from None
        if matches(data):
            findings += 1
            # Filenames can themselves contain secrets: only report category.
            location = "(path redacted)" if matches(path) else ascii(os.fsdecode(path))
            print("Potential secret in working-tree text file %s (value redacted)." % location, file=sys.stderr)
    objects = sorted(set(line.split(b" ", 1)[0] for line in git("rev-list", "--objects", "--all").splitlines()))
    if objects:
        batch = subprocess.run(["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                               input=b"\n".join(objects) + b"\n", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if batch.returncode:
            raise RuntimeError("History object enumeration failed")
        for entry in batch.stdout.splitlines():
            fields = entry.split()
            if len(fields) != 2 or fields[1] not in (b"blob", b"tree", b"commit", b"tag"):
                raise RuntimeError("Invalid/missing history object")
            if fields[1] == b"blob" and matches(git("cat-file", "blob", fields[0].decode("ascii"))):
                findings += 1
                print("Potential secret in historical blob %s (value redacted)." % fields[0].decode("ascii"), file=sys.stderr)
    if findings:
        print("Secret scan failed: %d finding(s); values suppressed." % findings, file=sys.stderr)
        sys.exit(1)
    print("Secret scan passed (working tree, notebooks, and all reachable history).")
except (RuntimeError, OSError, ValueError) as error:
    print(str(error) if isinstance(error, RuntimeError) else "Secret scan failed due to an operational error", file=sys.stderr)
    sys.exit(2)
PY
