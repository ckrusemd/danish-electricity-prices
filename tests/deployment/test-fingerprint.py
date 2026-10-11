#!/usr/bin/env python3
"""Verify deployment identity changes only with environment inputs."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class FingerprintTests(unittest.TestCase):
    def test_source_only_reuse_and_environment_invalidation(self):
        with tempfile.TemporaryDirectory(prefix="electricity-fingerprint-") as directory:
            root = pathlib.Path(directory)
            for name in ("Dockerfile", ".dockerignore", ".Rprofile", "renv.lock"):
                shutil.copy2(ROOT / name, root / name)
            shutil.copytree(ROOT / "renvinfra", root / "renvinfra")
            (root / "scripts").mkdir()
            for source in (ROOT / "scripts").glob("environment-*.sh"):
                shutil.copy2(source, root / "scripts" / source.name)
            shutil.copy2(ROOT / "scripts/verify-environment.R", root / "scripts/verify-environment.R")

            def fingerprint():
                return subprocess.check_output(["bash", str(root / "scripts/environment-fingerprint.sh")], text=True).strip()

            before = fingerprint()
            (root / "index.qmd").write_text("Source-only edit\n")
            self.assertEqual(before, fingerprint())
            with (root / "renvinfra/versions.env").open("a") as pins:
                pins.write("# Test environment change\n")
            self.assertNotEqual(before, fingerprint())
            before = fingerprint()
            (root / "renvinfra/new-input").write_text("new environment input\n")
            self.assertNotEqual(before, fingerprint())
            before = fingerprint()
            (root / "renvinfra/new-input").unlink()
            self.assertNotEqual(before, fingerprint())
            before = fingerprint()
            with (root / "scripts/verify-environment.R").open("a") as verifier:
                verifier.write("# Changed verifier\n")
            self.assertNotEqual(before, fingerprint())


if __name__ == "__main__":
    unittest.main()
