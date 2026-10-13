import importlib.util
import io
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("notification_image", ROOT / "scripts/notification-image.py")
image = importlib.util.module_from_spec(spec)
spec.loader.exec_module(image)


class RegistryResponse(io.BytesIO):
    def __init__(self, payload, headers=None):
        super().__init__(json.dumps(payload).encode())
        self.headers = headers or {}


class AutomationTests(unittest.TestCase):
    def test_registry_resolution_is_immutable_and_fail_closed(self):
        calls = []
        def request(url, timeout=0):
            calls.append(url)
            if isinstance(url, str):
                return RegistryResponse({"token": "fixture-public-pull"})
            return RegistryResponse({"schemaVersion": 2}, {"Docker-Content-Digest": "sha256:" + "a" * 64})
        result = image.resolve("b" * 64, request)
        self.assertEqual(result, "ghcr.io/ckrusemd/danish-electricity-prices-r@sha256:" + "a" * 64)
        self.assertIn("/manifests/env-" + "b" * 64, calls[1].full_url)
        def failed(*args, **kwargs):
            raise OSError("fixture")
        with self.assertRaisesRegex(RuntimeError, "Verified environment image unavailable"):
            image.resolve("b" * 64, failed)

    def test_disabled_scheduler_templates_and_workflow_contract(self):
        import yaml
        for filename, workflow in (("cron-job-notify.json", "daily-pushover.yml"), ("cron-job-publish.json", "deploy-pages.yml")):
            job = json.loads((ROOT / "ops" / filename).read_text())["job"]
            self.assertFalse(job["enabled"])
            self.assertFalse(job["saveResponses"])
            self.assertEqual(job["schedule"]["timezone"], "Europe/Copenhagen")
            self.assertEqual((job["schedule"]["hours"], job["schedule"]["minutes"]), ([5], [0, 15, 30]))
            self.assertEqual(job["extendedData"]["headers"]["X-GitHub-Api-Version"], "2026-03-10")
            self.assertIn("<REPOSITORY_ACTIONS_WRITE_PAT>", job["extendedData"]["headers"]["Authorization"])
            body = json.loads(job["extendedData"]["body"])
            self.assertEqual(body["inputs"]["trigger_source"], "external")
            self.assertEqual(body["inputs"]["scheduled_delivery"], "true")
            self.assertTrue(job["url"].endswith(workflow + "/dispatches"))
        workflow = yaml.safe_load((ROOT / ".github/workflows/daily-pushover.yml").read_text())
        self.assertEqual(set(workflow["jobs"]), {"gate", "delivery"})
        self.assertFalse(workflow["concurrency"]["cancel-in-progress"])
        expected_schedule = [
            {"cron": "0,17,37 5 * * *", "timezone": "Europe/Copenhagen"},
            {"cron": "17,37 6-8 * * *", "timezone": "Europe/Copenhagen"},
            {"cron": "37 9-23 * * *", "timezone": "Europe/Copenhagen"},
        ]
        for filename in ("daily-pushover.yml", "deploy-pages.yml"):
            definition = yaml.safe_load((ROOT / ".github/workflows" / filename).read_text())
            on = definition.get("on", definition.get(True))
            self.assertEqual(on["schedule"], expected_schedule)
            runs = "\n".join(step.get("run", "") for job in definition["jobs"].values()
                             for step in job.get("steps", []))
            self.assertNotRegex(runs, r"\bsleep\b|\bwait_seconds\b|\btarget_epoch\b")
            self.assertIn("Skipped: this successful gate did not", runs)
        self.assertNotIn("latest", workflow["jobs"]["delivery"]["container"]["image"])
        steps = workflow["jobs"]["delivery"]["steps"]
        artifact = next(step for step in steps if step.get("uses", "").startswith("actions/upload-artifact@"))
        self.assertIn("always()", artifact["if"])
        self.assertEqual(artifact["with"]["path"], "pushover-result.json")
        for filename in ("daily-pushover.yml", "security.yml"):
            for job in yaml.safe_load((ROOT / ".github/workflows" / filename).read_text())["jobs"].values():
                for step in job["steps"]:
                    if "uses" in step:
                        self.assertRegex(step["uses"], r"@[0-9a-f]{40}$")

    def test_dispatcher_makes_one_call_and_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = pathlib.Path(directory) / "gh"
            log = pathlib.Path(directory) / "calls"
            fake.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$MOCK_CALLS\"\n")
            fake.chmod(0o700)
            env = dict(os.environ, GH_BIN=str(fake), MOCK_CALLS=str(log))
            result = subprocess.run(["bash", str(ROOT / "scripts/dispatch-daily-pushover.sh"), "morning"], env=env, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            lines = log.read_text().splitlines()
            self.assertEqual(len(lines), 1)
            self.assertTrue(lines[0].startswith("workflow run daily-pushover.yml"))
            self.assertNotIn("weather", lines[0])
            result = subprocess.run(["bash", str(ROOT / "scripts/dispatch-daily-pushover.sh"), "afternoon"], env=env, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(len(log.read_text().splitlines()), 1)

    def test_scanner_notebooks_history_redaction_and_errors(self):
        # All generated objects are confined to a disposable fixture repository.
        # Use git plumbing, not a commit in the user's working repository.
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            def git(*args, data=None):
                return subprocess.run(["git", *args], cwd=directory, input=data, capture_output=True, check=True).stdout
            git("init", "-q")
            scanner = directory / "scanner.sh"
            shutil.copyfile(ROOT / "scripts/secret-scan.sh", scanner)
            token = "gh" + "p_" + "X" * 30
            notebook = directory / "fixture.ipynb"
            notebook.write_text(json.dumps({"cells": [{"source": [token]}]}))
            scan = lambda: subprocess.run(["bash", str(scanner)], cwd=directory, capture_output=True, text=True, timeout=20)
            result = scan()
            self.assertEqual(result.returncode, 1)
            self.assertNotIn(token, result.stdout + result.stderr)
            self.assertIn("fixture.ipynb", result.stderr)
            blob = git("hash-object", "-w", "--stdin", data=notebook.read_bytes()).decode().strip()
            tree = git("mktree", data=("100644 blob " + blob + "\tfixture.ipynb\n").encode()).decode().strip()
            fixture_env = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                               GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
            commit = subprocess.run(["git", "commit-tree", tree], cwd=directory, input=b"fixture\n", env=fixture_env, capture_output=True, check=True).stdout.decode().strip()
            git("update-ref", "refs/heads/fixture", commit)
            notebook.unlink()
            result = scan()
            self.assertEqual(result.returncode, 1)
            self.assertIn("historical blob", result.stderr)
            self.assertNotIn(token, result.stdout + result.stderr)
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["bash", str(ROOT / "scripts/secret-scan.sh")], cwd=directory, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 2)
            self.assertIn("operation failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
