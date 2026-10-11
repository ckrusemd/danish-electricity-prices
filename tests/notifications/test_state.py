import base64
import copy
import datetime as dt
import importlib.util
import io
import json
import pathlib
import unittest
import urllib.error
import zipfile
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("notification_state", ROOT / "scripts/notification-state.py")
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class MockHTTP:
    """In-memory GitHub HTTP routes, including optimistic ref updates."""
    def __init__(self, files=None):
        self.head = "initial"
        self.files = files or {"delivery-state.json": json.dumps({"schema_version": 1, "deliveries": {}})}
        self.trees = {"tree-initial": copy.deepcopy(self.files)}
        self.commits = {"initial": {"tree": {"sha": "tree-initial"}}}
        self.calls = []
        self.fail = None
        self.artifacts = {"total_count": 0, "artifacts": []}
        self.archive = b""

    def __call__(self, method, url, body=None, raw=False):
        path = url.split("/repos/owner/repo", 1)[1]
        self.calls.append((method, path, body))
        if self.fail and self.fail(method, path):
            raise state.StateError("Mock HTTP/auth/network failure")
        if path == "/git/ref/heads/" + state.BRANCH:
            return {"object": {"sha": self.head}}
        if path.startswith("/git/commits/"):
            return self.commits[path.rsplit("/", 1)[1]]
        if method == "GET" and path.startswith("/git/trees/"):
            tree = self.trees[path.rsplit("/", 1)[1]]
            return {"tree": [{"path": key, "type": "blob", "sha": key} for key in tree], "truncated": False}
        if path.startswith("/git/blobs/"):
            name = path.rsplit("/", 1)[1]
            tree = self.commits[self.head]["tree"]["sha"]
            return {"encoding": "base64", "content": base64.b64encode(self.trees[tree][name].encode()).decode()}
        if method == "POST" and path == "/git/trees":
            key = "tree-" + str(len(self.trees))
            self.trees[key] = copy.deepcopy(self.trees[body["base_tree"]])
            self.trees[key]["delivery-state.json"] = body["tree"][0]["content"]
            return {"sha": key}
        if method == "POST" and path == "/git/commits":
            key = "commit-" + str(len(self.commits))
            self.commits[key] = {"tree": {"sha": body["tree"]}, "parents": body["parents"]}
            return {"sha": key}
        if method == "PATCH":
            if self.commits[body["sha"]]["parents"] != [self.head] or body["force"]:
                raise state.StateError("HTTP 422 concurrent state claim")
            self.head = body["sha"]
            return {"object": {"sha": self.head}}
        if "/artifacts?" in path:
            return self.artifacts
        if path == "/actions/artifacts/42/zip":
            return self.archive
        raise AssertionError((method, path))


class NotificationStateTests(unittest.TestCase):
    def setUp(self):
        self.http = MockHTTP()
        self.journal = state.Journal("owner/repo", self.http)

    def claim(self, day="2026-10-11", attempt="123-1"):
        self.journal.claim(day, attempt, "123", "notification-receipt-123-1")

    def receipt(self):
        return {"status": 1, "request": "confirmed-123", "date": "2026-10-11", "slot": "morning", "attempt": "123-1"}

    def test_dst_admission_and_frozen_date(self):
        for moment, day, action in [
            ("2026-03-29T02:59:00+00:00", "2026-03-29", "skip"),
            ("2026-03-29T03:00:00+00:00", "2026-03-29", "send"),
            ("2026-10-25T03:59:00+00:00", "2026-10-25", "skip"),
            ("2026-10-25T04:00:00+00:00", "2026-10-25", "send"),
            ("2026-10-11T22:30:00+00:00", "2026-10-12", "skip"),
        ]:
            result = state.gate(dt.datetime.fromisoformat(moment), journal=self.journal)
            self.assertEqual((result["date"], result["action"]), (day, action))
        self.claim()
        self.journal.accept(self.receipt())
        self.assertEqual(self.journal.load()["deliveries"]["morning"]["date"], "2026-10-11")

    def test_early_and_manual_force_do_not_read_state(self):
        self.http.fail = lambda *_: True
        result = state.gate(dt.datetime(2026, 10, 11, 2, tzinfo=dt.timezone.utc), journal=self.journal)
        self.assertEqual(result["action"], "skip")
        result = state.gate(dt.datetime.now(dt.timezone.utc), scheduled=False, force=True, journal=self.journal)
        self.assertEqual((result["action"], result["record_daily"]), ("send", "false"))
        self.assertEqual(self.http.calls, [])
        with self.assertRaises(state.StateError):
            state.gate(dt.datetime.now(dt.timezone.utc), slot="afternoon")

    def test_legacy_formats_preserved(self):
        for files in [
            {"last_notification_date": "2026-10-11\n"},
            {"delivery_state": "morning=2026-10-11\nafternoon=2026-10-10\n"},
            {"notification-state.json": json.dumps({"deliveries": {"2026-10-11": {"morning": {"request": "old"}}}})},
            {"delivery-state.json": json.dumps({"schema_version": 1, "deliveries": {"morning": {"date": "2026-10-11", "run_id": "old"}}})},
        ]:
            normalized = state.normalize(files)
            self.assertEqual(state.admission(normalized, "2026-10-11")["action"], "skip")
            self.http = MockHTTP(files)
            self.journal = state.Journal("owner/repo", self.http)
            self.claim("2026-10-12")
            loaded = self.journal.load()
            self.assertEqual(loaded["deliveries"]["morning"]["date"], "2026-10-11")
            if "delivery_state" in files:
                self.assertEqual(loaded["deliveries"]["afternoon"]["date"], "2026-10-10")

    def test_absent_corrupt_and_unknown_schema_fail_closed(self):
        for files in [{}, {"delivery-state.json": "bad"}, {"delivery-state.json": "null"},
                      {"delivery-state.json": '{"schema_version":9,"deliveries":{}}'},
                      {"delivery-state.json": '{"deliveries":{"morning":{"date":"2026-02-30"}}}'},
                      {"last_notification_date": ""}, {"delivery_state": "unknown=2026-10-11"}]:
            with self.assertRaises(state.StateError):
                state.normalize(files)

    def test_failed_get_and_failed_claim_never_admit(self):
        for route in ("/git/ref/", "/git/commits/", "/git/trees/", "/git/blobs/"):
            self.http.fail = lambda method, path: route in path
            with self.assertRaises(state.StateError):
                self.journal.load()
        self.http.fail = lambda method, path: method == "PATCH"
        with self.assertRaises(state.StateError):
            self.claim()

    def test_concurrent_claims_one_winner(self):
        first = self.journal
        second = state.Journal("owner/repo", self.http)
        first.load()
        second.load()
        first.state["attempts"]["a"] = {"date": "2026-10-11", "slot": "morning", "status": "pending", "run_id": "123", "artifact_name": "a"}
        second.state["attempts"]["b"] = {"date": "2026-10-11", "slot": "morning", "status": "pending", "run_id": "124", "artifact_name": "b"}
        first.save("first")
        with self.assertRaises(state.StateError):
            second.save("second")
        self.assertEqual(list(first.load()["attempts"]), ["a"])

    def test_pending_blocks_resend_including_next_day(self):
        self.claim()
        for day in ("2026-10-11", "2026-10-12"):
            self.assertEqual(state.admission(self.journal.load(), day)["action"], "recover")
        with self.assertRaisesRegex(state.StateError, "manual review"):
            self.journal.recover("123-1")
        with self.assertRaises(state.StateError):
            self.journal.claim("2026-10-11", "124-1", "124", "artifact")

    def test_explicit_rejection_permits_later_claim(self):
        self.claim()
        self.journal.reject("123-1")
        self.assertEqual(state.admission(self.journal.load(), "2026-10-11")["action"], "send")
        self.journal.claim("2026-10-11", "124-1", "124", "artifact")
        self.assertEqual(self.journal.load()["attempts"]["123-1"]["status"], "rejected")

    def test_failed_record_recovered_without_resend(self):
        self.claim()
        self.http.fail = lambda method, path: method == "PATCH"
        with self.assertRaises(state.StateError):
            self.journal.accept(self.receipt())
        self.http.fail = None
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("pushover-result.json", json.dumps(self.receipt()))
        self.http.archive = buffer.getvalue()
        self.http.artifacts = {"total_count": 1, "artifacts": [{"id": 42, "name": "notification-receipt-123-1", "expired": False}]}
        self.journal.recover("123-1")
        self.assertEqual(state.admission(self.journal.load(), "2026-10-11")["action"], "skip")
        self.assertFalse(any("messages.json" in call[1] for call in self.http.calls))

    def test_transport_http_errors_and_json_header(self):
        with patch.dict("os.environ", {"GH_TOKEN": "fixture"}):
            opener = unittest.mock.Mock()
            opener.open.side_effect = urllib.error.HTTPError("url", 401, "redacted", {}, None)
            with patch.object(state.urllib.request, "build_opener", return_value=opener):
                with self.assertRaisesRegex(state.StateError, "HTTP 401"):
                    state.github_transport("POST", "https://api.github.com/test", {"a": 1})
            req = opener.open.call_args.args[0]
            self.assertEqual(req.get_header("Content-type"), "application/json")


if __name__ == "__main__":
    unittest.main()
