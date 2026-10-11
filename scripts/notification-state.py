#!/usr/bin/env python3
"""Fail-closed notification journal and lightweight admission gate.

No POST is repeated after an uncertain response. State commits use fast-forward
ref updates, so concurrent claimants cannot both acquire a date/slot.
"""
import argparse
import base64
import datetime as dt
import io
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from zoneinfo import ZoneInfo

BRANCH = "electricity-notification-state"
STATE_FILES = ("delivery-state.json", "notification-state.json", "delivery_state", "last_notification_date")


class StateError(RuntimeError):
    pass


def valid_date(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise StateError("Invalid notification date")
    try:
        dt.date.fromisoformat(value)
    except ValueError:
        raise StateError("Invalid notification date") from None
    return value


def text_field(value):
    return isinstance(value, str) and bool(value) and len(value) <= 300 and not any(ord(c) < 32 for c in value)


def normalize(files):
    state = {"schema_version": 2, "deliveries": {}, "attempts": {}}
    for name in STATE_FILES[:2]:
        if name not in files:
            continue
        try:
            source = json.loads(files[name])
        except (ValueError, TypeError):
            raise StateError("Corrupt notification state JSON") from None
        if not isinstance(source, dict) or source.get("schema_version", 1) not in (1, 2):
            raise StateError("Unsupported notification state schema")
        deliveries = source.get("deliveries")
        if not isinstance(deliveries, dict):
            raise StateError("Missing notification deliveries")
        for key, record in deliveries.items():
            if key in ("morning", "afternoon"):
                records = [(key, record)]
            else:
                valid_date(key)
                if not isinstance(record, dict) or not record:
                    raise StateError("Invalid legacy deliveries")
                records = []
                for slot, item in record.items():
                    if slot not in ("morning", "afternoon") or not isinstance(item, dict):
                        raise StateError("Invalid legacy delivery")
                    records.append((slot, dict(item, date=key)))
            for slot, item in records:
                if not isinstance(item, dict):
                    raise StateError("Invalid delivery record")
                day = valid_date(item.get("date"))
                previous = state["deliveries"].get(slot)
                if previous is None or day > previous["date"]:
                    state["deliveries"][slot] = item
        attempts = source.get("attempts", {})
        if not isinstance(attempts, dict):
            raise StateError("Invalid attempt journal")
        for key, item in attempts.items():
            if not text_field(key) or not isinstance(item, dict):
                raise StateError("Invalid attempt record")
            valid_date(item.get("date"))
            if item.get("slot") != "morning" or item.get("status") not in ("pending", "accepted", "ambiguous", "rejected"):
                raise StateError("Invalid attempt status or slot")
            for field in ("run_id", "artifact_name"):
                if not text_field(item.get(field)):
                    raise StateError("Missing attempt recovery metadata")
            if item["status"] == "accepted" and not text_field(item.get("request")):
                raise StateError("Accepted attempt lacks receipt")
            if key in state["attempts"] and state["attempts"][key] != item:
                raise StateError("Conflicting attempt journals")
            state["attempts"][key] = item
    for name in STATE_FILES[2:]:
        if name not in files:
            continue
        value = files[name].strip()
        if name == "last_notification_date":
            records = [("morning", valid_date(value))]
        else:
            records = []
            for line in value.splitlines():
                parts = line.split("=", 1)
                if len(parts) != 2 or parts[0] not in ("morning", "afternoon"):
                    raise StateError("Corrupt legacy delivery state")
                records.append((parts[0], valid_date(parts[1])))
            if not records:
                raise StateError("Empty legacy delivery state")
        for slot, day in records:
            old = state["deliveries"].get(slot)
            if old is None or day > old["date"]:
                state["deliveries"][slot] = {"date": day, "legacy": True}
    if not files:
        raise StateError("Notification state is absent; reviewed bootstrap required")
    return state


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if urllib.parse.urlparse(newurl).netloc != "api.github.com":
            redirected.remove_header("Authorization")
        return redirected


def github_transport(method, url, body=None, raw=False):
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise StateError("GitHub token missing")
    headers = {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2026-03-10"}
    data = None if body is None else json.dumps(body).encode()
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.build_opener(SafeRedirect()).open(req, timeout=30) as response:
            content = response.read(10 * 1024 * 1024 + 1)
        if len(content) > 10 * 1024 * 1024:
            raise StateError("GitHub response exceeds limit")
        return content if raw else json.loads(content)
    except urllib.error.HTTPError as error:
        raise StateError("GitHub state API failed (HTTP %d); no notification admitted" % error.code) from None
    except (OSError, ValueError):
        raise StateError("GitHub state network/JSON failure; no notification admitted") from None


class Journal:
    def __init__(self, repo, transport=github_transport):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
            raise StateError("Invalid repository")
        self.base = "https://api.github.com/repos/" + repo
        self.transport = transport

    def call(self, method, path, body=None, raw=False):
        return self.transport(method, self.base + path, body, raw)

    def load(self):
        try:
            ref = self.call("GET", "/git/ref/heads/" + BRANCH)
            self.head = ref["object"]["sha"]
            commit = self.call("GET", "/git/commits/" + self.head)
            self.tree = commit["tree"]["sha"]
            tree = self.call("GET", "/git/trees/" + self.tree)
            if tree.get("truncated") or not isinstance(tree.get("tree"), list):
                raise StateError("Incomplete notification state tree")
            files = {}
            for entry in tree["tree"]:
                if entry.get("path") in STATE_FILES:
                    if entry.get("type") != "blob":
                        raise StateError("Invalid notification state file")
                    blob = self.call("GET", "/git/blobs/" + entry["sha"])
                    if blob.get("encoding") != "base64":
                        raise StateError("Invalid notification state encoding")
                    files[entry["path"]] = base64.b64decode(blob["content"].replace("\n", ""), validate=True).decode("utf-8")
            self.state = normalize(files)
            return self.state
        except (KeyError, TypeError, ValueError, UnicodeError):
            raise StateError("Invalid GitHub notification state response") from None

    def save(self, message):
        # GitHub rejects a non-fast-forward update if another claimant won.
        try:
            tree = self.call("POST", "/git/trees", {"base_tree": self.tree, "tree": [
                {"path": "delivery-state.json", "mode": "100644", "type": "blob",
                 "content": json.dumps(self.state, sort_keys=True)}]})
            commit = self.call("POST", "/git/commits", {"message": message, "tree": tree["sha"], "parents": [self.head]})
            self.call("PATCH", "/git/refs/heads/" + BRANCH, {"sha": commit["sha"], "force": False})
        except (KeyError, TypeError):
            raise StateError("Invalid GitHub state write response") from None

    def claim(self, date, attempt, run_id, artifact):
        state = self.load()
        decision = admission(state, date)
        if decision["action"] != "send":
            raise StateError("Date/slot was already claimed; POST blocked")
        if not all(text_field(x) for x in (attempt, run_id, artifact)):
            raise StateError("Invalid attempt metadata")
        if attempt in state["attempts"]:
            raise StateError("Attempt identifier already used; journal history preserved")
        state["attempts"][attempt] = {"date": valid_date(date), "slot": "morning", "status": "pending",
                                     "run_id": run_id, "artifact_name": artifact}
        self.save("Claim morning notification for " + date)

    def accept(self, receipt):
        validate_receipt(receipt)
        state = self.load()
        item = state["attempts"].get(receipt["attempt"])
        if item is None or item["date"] != receipt["date"] or item["slot"] != receipt["slot"]:
            raise StateError("Receipt does not match the admitted attempt")
        if item["status"] == "accepted" and item["request"] != receipt["request"]:
            raise StateError("Conflicting accepted receipts")
        item.update(status="accepted", request=receipt["request"])
        old = state["deliveries"].get("morning", {})
        if old.get("date", "") <= receipt["date"]:
            state["deliveries"]["morning"] = {"date": receipt["date"], "pushover_request_id": receipt["request"],
                                               "run_id": item["run_id"], "attempt": receipt["attempt"]}
        self.save("Accept morning notification for " + receipt["date"])

    def reject(self, attempt):
        state = self.load()
        item = state["attempts"].get(attempt)
        if item is None or item["status"] != "pending":
            raise StateError("Rejected response does not match a pending attempt")
        item["status"] = "rejected"
        self.save("Record explicit Pushover rejection")

    def recover(self, attempt):
        state = self.load()
        item = state["attempts"].get(attempt)
        if not item:
            raise StateError("Recovery attempt missing")
        if item["status"] == "accepted":
            receipt = {"status": 1, "request": item["request"], "attempt": attempt,
                       "date": item["date"], "slot": item["slot"]}
        else:
            run_id = item["run_id"]
            if not run_id.isdigit():
                raise StateError("Invalid recovery run ID")
            payload = self.call("GET", "/actions/runs/" + run_id + "/artifacts?per_page=100")
            if not isinstance(payload.get("artifacts"), list) or payload.get("total_count", 101) > 100:
                raise StateError("Invalid/incomplete recovery artifacts")
            matches = [a for a in payload["artifacts"] if a.get("name") == item["artifact_name"] and not a.get("expired")]
            if len(matches) != 1:
                raise StateError("Ambiguous pending attempt: no confirmed receipt; manual review required, no resend")
            artifact_id = matches[0].get("id")
            if not isinstance(artifact_id, int):
                raise StateError("Invalid recovery artifact")
            archive = self.call("GET", "/actions/artifacts/%d/zip" % artifact_id, raw=True)
            try:
                with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
                    entry = zipped.getinfo("pushover-result.json")
                    if entry.file_size > 8192:
                        raise StateError("Recovery receipt too large")
                    receipt = json.loads(zipped.read(entry))
            except (ValueError, KeyError, zipfile.BadZipFile):
                raise StateError("Invalid recovery receipt archive") from None
            validate_receipt(receipt)
            if receipt["attempt"] != attempt or receipt["date"] != item["date"]:
                raise StateError("Recovery receipt mismatch")
        self.accept(receipt)


def validate_receipt(receipt):
    if not isinstance(receipt, dict) or receipt.get("status") != 1 or receipt.get("slot") != "morning":
        raise StateError("Invalid accepted receipt")
    valid_date(receipt.get("date"))
    if not text_field(receipt.get("attempt")) or not text_field(receipt.get("request")):
        raise StateError("Incomplete accepted receipt")


def admission(state, date):
    valid_date(date)
    if state["deliveries"].get("morning", {}).get("date", "") >= date:
        return {"action": "skip", "reason": "already-sent"}
    # Any unresolved attempt blocks later dates as well: a lost response must
    # never be silently forgotten at midnight.
    for attempt, item in state["attempts"].items():
        if item["status"] in ("pending", "ambiguous") or (item["status"] == "accepted" and item["date"] == date):
            return {"action": "recover", "attempt": attempt, "reason": "receipt-recovery"}
    return {"action": "send", "reason": "eligible"}


def gate(now, scheduled=True, force=False, slot="morning", journal=None):
    if slot != "morning":
        raise StateError("Electricity supports the morning slot only")
    local = now.astimezone(ZoneInfo("Europe/Copenhagen"))
    result = {"date": local.date().isoformat(), "slot": slot, "record_daily": "true" if scheduled else "false"}
    if scheduled and local.hour < 5:
        return dict(result, action="skip", reason="before-05:00")
    if force and not scheduled:
        return dict(result, action="send", reason="manual-force")
    if not scheduled:
        return dict(result, action="skip", reason="manual-force-required")
    return dict(result, **admission(journal.load(), result["date"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("gate", "pending", "accepted", "rejected", "recover", "verify"))
    parser.add_argument("--date", default=os.environ.get("NOTIFICATION_DATE"))
    parser.add_argument("--attempt", default=os.environ.get("NOTIFICATION_ATTEMPT"))
    parser.add_argument("--receipt", default="pushover-result.json")
    args = parser.parse_args()
    journal = Journal(os.environ.get("GITHUB_REPOSITORY", "ckrusemd/danish-electricity-prices"))
    if args.command == "gate":
        result = gate(dt.datetime.now(dt.timezone.utc),
                      scheduled=os.environ.get("SCHEDULED_DELIVERY", "true") == "true",
                      force=os.environ.get("FORCE_SEND", "false") == "true",
                      slot=os.environ.get("REQUESTED_SLOT", "morning"), journal=journal)
        output = os.environ.get("GITHUB_OUTPUT")
        if output:
            with open(output, "a", encoding="utf-8") as handle:
                for key, value in result.items():
                    handle.write(f"{key}={value}\n")
        print("Notification gate: " + result["reason"] + " date=" + result["date"])
    elif args.command == "pending":
        journal.claim(args.date, args.attempt, os.environ.get("GITHUB_RUN_ID", ""), os.environ.get("NOTIFICATION_ARTIFACT", ""))
    elif args.command == "accepted":
        with open(args.receipt, encoding="utf-8") as handle:
            journal.accept(json.load(handle))
    elif args.command == "recover":
        journal.recover(args.attempt)
        print("Confirmed receipt recovered; no notification POST")
    elif args.command == "rejected":
        journal.reject(args.attempt)
    else:
        day = dt.datetime.now(ZoneInfo("Europe/Copenhagen")).date().isoformat()
        state = journal.load()
        if state["deliveries"].get("morning", {}).get("date") != day:
            raise StateError("No confirmed morning delivery for today")
        print("Confirmed morning delivery for " + day)


if __name__ == "__main__":
    try:
        main()
    except (StateError, OSError, ValueError) as error:
        # Never emit API response bodies, credentials, or raw transport errors.
        message = str(error) if isinstance(error, StateError) else "Notification state operation failed"
        print(message, file=sys.stderr)
        sys.exit(1)
