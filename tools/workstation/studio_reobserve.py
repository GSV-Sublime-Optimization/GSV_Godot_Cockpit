#!/usr/bin/env python3
"""Bounded, read-only Studio source re-observation of a verified Hyperspace capsule.

No POST, credentials, arbitrary URLs, process spawn or shell. The only network
target is this machine's 127.0.0.1 Studio API on an explicitly bounded port.
The returned document is an allowlisted EVIDENCE INDEX, not the raw Studio
response or an assertion that a successful mission built functional software.
"""
from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from typing import Any, Callable

OWNER_SCHEMA = "gsv.hyperspace-owner-observation.v1"
PROJECT_SCHEMA = "kilocore-studio.projects-scan.v2"
BODY_SCHEMA = "kilocore-studio.entity-bodies.v0"
HEALTH_SCHEMA = "kilocore-studio.cockpit-health.v2"
MAX_BYTES = 131072
MAX_PROJECTS = 512
STATUS = {"proposed", "awaiting_approval", "approved", "queued", "running",
          "succeeded", "failed", "cancelled", "rejected"}
RISK = {"R0", "R1", "R2", "R3"}
BODY_STATE = {"unknown", "invalid", "stale", "reported_fresh"}
RECEIPT = re.compile(r"^[a-zA-Z0-9_.-]{8,120}$")
COMMIT = re.compile(r"^[0-9a-fA-F]{40}$")


def studio_port() -> int:
    raw = os.environ.get("GSV_STUDIO_ENTITY_PORT", "7340")
    if not raw.isdecimal() or not 1 <= int(raw) <= 65535:
        raise ValueError("invalid_local_port")
    return int(raw)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str,
                         headers: Any, newurl: str) -> None:
        raise ValueError("studio_redirect_refused")


def get_local_json(path: str, *, timeout: float = 6.0) -> dict[str, Any]:
    """Reach one literal same-host endpoint. Caller must provide a whitelisted path."""
    if not (
        path in {"/api/projects", "/api/entity/bodies", "/api/health"}
        or re.fullmatch(r"/api/missions/msn_[0-9a-f]{12}", path)
    ):
        raise ValueError("unapproved_studio_route")
    if not 0.5 <= timeout <= 35.0:
        raise ValueError("invalid_timeout")
    url = f"http://127.0.0.1:{studio_port()}{path}"
    opener = urllib.request.build_opener(_NoRedirect)
    req = urllib.request.Request(url, method="GET", headers={"Accept": "application/json"})
    try:
        with opener.open(req, timeout=timeout) as response:
            if response.status != 200:
                raise ValueError("studio_response_not_200")
            body = response.read(MAX_BYTES + 1)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        # Do not echo the raw response, URL userinfo, exception internals or logs.
        raise ValueError("local_studio_unavailable") from exc
    if len(body) > MAX_BYTES:
        raise ValueError("oversized_studio_response")
    try:
        obj = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid_studio_json") from exc
    if not isinstance(obj, dict):
        raise ValueError("non_object_studio_response")
    return obj


def _text(value: Any, max_chars: int = 120) -> str:
    if not isinstance(value, str):
        return ""
    return "".join(ch for ch in value[:max_chars] if ch >= " " and ch != "\x7f")


def _base(source: dict[str, Any], route: str) -> dict[str, Any]:
    return {
        "schema": OWNER_SCHEMA, "source": "KiloCore-Studio/127.0.0.1",
        "resource_kind": source["kind"], "resource_id": source["id"],
        "source_route": route, "fetched_from_owner": False,
        "actor_authenticated": False, "execution_admitted": False,
        "approval_granted": False, "merge_performed": False,
        "artifact_verified": False,
        "claim": "source observation, not execution authority",
    }


def _mission(source: dict[str, Any], read: Callable[[str], dict[str, Any]]) -> dict[str, Any]:
    mid = source["id"]
    raw = read("/api/missions/" + mid)
    if raw.get("id") != mid:
        raise ValueError("mission_identity_changed")
    status, risk = raw.get("status"), raw.get("risk")
    if not isinstance(status, str) or not isinstance(risk, str) or status not in STATUS or risk not in RISK:
        raise ValueError("unrecognized_mission_state")
    repo = raw.get("repo", "")
    if not isinstance(repo, str):
        raise ValueError("invalid_mission_repo")
    expected_repo = source.get("repo", "")
    if expected_repo and repo != expected_repo:
        raise ValueError("mission_repo_drift")
    proof = _base(source, "/api/missions/{id}")
    proof.update({
        "fetched_from_owner": True,
        "status": status, "risk": risk, "repo": _text(repo, 500),
        "updated_at": _text(raw.get("updated_at"), 50),
        "lifecycle_changed_since_capsule": source.get("state") != status,
        "receipt_id": None, "validator": "NOT_REPORTED",
        "runner_exit_zero": False, "report": "NOT_REPORTED",
        "acceptance_met": None, "acceptance_count": None,
        "changed_paths": [], "commits": [],
        "review_flag": raw.get("review") is True,
        "mergeable_flag": raw.get("mergeable") is True,
        "needs_approval": raw.get("needs_approval") is True,
    })
    result = raw.get("result")
    if result is None:
        return proof
    if not isinstance(result, dict):
        raise ValueError("invalid_mission_result")
    exit_code = result.get("exit_code")
    proof["runner_exit_zero"] = type(exit_code) is int and exit_code == 0
    receipt = result.get("receipt_id")
    if isinstance(receipt, str) and RECEIPT.fullmatch(receipt):
        proof["receipt_id"] = receipt
    validator = result.get("validator")
    if validator is not None:
        if not isinstance(validator, dict):
            raise ValueError("invalid_validator_shape")
        code, timed_out = validator.get("exit_code"), validator.get("timed_out")
        if type(code) is not int or type(timed_out) is not bool:
            raise ValueError("invalid_validator_fields")
        proof["validator"] = "PASS" if code == 0 and not timed_out else "FAIL"
    report = result.get("report")
    if report is not None:
        if not isinstance(report, dict) or type(report.get("raw_ok")) is not bool:
            raise ValueError("invalid_acceptance_report")
        if not report["raw_ok"]:
            proof["report"] = "INVALID"
        else:
            acceptance = report.get("acceptance", [])
            if not isinstance(acceptance, list) or len(acceptance) > 32:
                raise ValueError("invalid_acceptance_entries")
            if any(not isinstance(x, dict) or type(x.get("met")) is not bool for x in acceptance):
                raise ValueError("invalid_acceptance_entry")
            proof["acceptance_met"] = sum(x["met"] for x in acceptance)
            proof["acceptance_count"] = len(acceptance)
            proof["report"] = "REPORTED"
    commits = result.get("commits", [])
    if isinstance(commits, list):
        proof["commits"] = [s.lower() for s in commits[:8]
                            if isinstance(s, str) and COMMIT.fullmatch(s)]
    paths = result.get("changed_paths", [])
    if isinstance(paths, list):
        proof["changed_paths"] = [_text(s, 180) for s in paths[:24]
                                  if isinstance(s, str) and "\x00" not in s
                                  and ".." not in s and not s.startswith("/")]
    # A reported success and a receipt do not independently establish build or game quality.
    proof["artifact_verified"] = False
    return proof


def _project(source: dict[str, Any], read: Callable[[str], dict[str, Any]]) -> dict[str, Any]:
    raw = read("/api/projects")
    if raw.get("schema") != PROJECT_SCHEMA:
        raise ValueError("unexpected_project_schema")
    state = raw.get("state")
    proof = _base(source, "/api/projects")
    proof["source_state"] = _text(state, 32)
    proof["ready_for_composer"] = False
    proof["qualified_exact_repo_and_branch"] = False
    proof["fetched_from_owner"] = True
    if state != "OBSERVED":
        # Show bounded operational state, not raw exception details that could
        # include paths, token-bearing commands or private environment strings.
        proof["reason"] = "owner_project_discovery_unavailable"
        return proof
    projects = raw.get("projects")
    if not isinstance(projects, list) or len(projects) > MAX_PROJECTS:
        raise ValueError("invalid_project_array")
    candidates = [x for x in projects if isinstance(x, dict)
                  and x.get("path") == source["id"]]
    if len(candidates) != 1:
        proof["reason"] = "target_not_unique_or_missing"
        return proof
    item = candidates[0]
    git = item.get("git")
    if not isinstance(git, dict) or git.get("is_repo") is not True:
        proof["reason"] = "target_not_git"
        return proof
    branch = git.get("branch")
    if branch != source.get("branch"):
        proof["reason"] = "branch_changed"
        return proof
    proof["ready_for_composer"] = True
    proof["qualified_exact_repo_and_branch"] = True
    proof["reason"] = "fresh_owner_scan_confirmed"
    proof["branch"] = _text(branch, 160)
    return proof


def _rig(source: dict[str, Any], read: Callable[[str], dict[str, Any]]) -> dict[str, Any]:
    raw = read("/api/entity/bodies")
    if raw.get("schema") != BODY_SCHEMA:
        raise ValueError("unexpected_body_schema")
    bodies = raw.get("bodies")
    if not isinstance(bodies, list) or len(bodies) != 4:
        raise ValueError("invalid_body_count")
    item = [b for b in bodies if isinstance(b, dict) and b.get("body_id") == source["id"]]
    if len(item) != 1 or not isinstance(item[0].get("state"), str) or item[0].get("state") not in BODY_STATE:
        raise ValueError("body_not_observed")
    if any(item[0].get(field, True) is not False for field in (
        "identity_attested", "execution_authorized", "remote_work_admitted")):
        raise ValueError("false_owner_body_admission")
    proof = _base(source, "/api/entity/bodies")
    proof.update({"fetched_from_owner": True, "state": item[0]["state"],
                  "identity_attested": False, "remote_work_admitted": False})
    return proof


def _service(source: dict[str, Any], read: Callable[[str], dict[str, Any]]) -> dict[str, Any]:
    raw = read("/api/health")
    if raw.get("schema") != HEALTH_SCHEMA:
        raise ValueError("unexpected_health_schema")
    colony = raw.get("colony_observation", {})
    if not isinstance(colony, dict) or colony.get("state") != "OBSERVED" or colony.get("available") is not True:
        proof = _base(source, "/api/health")
        proof.update({"fetched_from_owner": True, "state": "UNKNOWN"})
        return proof
    projection = colony.get("projection", {})
    if not isinstance(projection, dict):
        raise ValueError("invalid_colony_projection")
    facts = projection.get("facts", {})
    if not isinstance(facts, dict):
        raise ValueError("invalid_colony_facts")
    services = facts.get("services", [])
    if not isinstance(services, list) or len(services) > 128:
        raise ValueError("invalid_service_collection")
    entries = [x for x in services if isinstance(x, dict)
               and x.get("service_id") == source["id"]]
    proof = _base(source, "/api/health")
    proof["fetched_from_owner"] = True
    if len(entries) != 1:
        proof["state"] = "UNKNOWN"
        return proof
    semantic = entries[0].get("semantic_health", {})
    proof["state"] = _text(semantic.get("value", "unknown"), 32) if isinstance(semantic, dict) else "unknown"
    return proof


def observe(source: dict[str, Any], read: Callable[[str], dict[str, Any]]) -> dict[str, Any]:
    """A validated agent_handoff.validate() source only. Readonly owner-specific path."""
    kind = source.get("kind")
    if kind == "mission":
        return _mission(source, read)
    if kind == "project":
        return _project(source, read)
    if kind == "rig":
        return _rig(source, read)
    if kind == "service":
        return _service(source, read)
    if kind == "capability":
        proof = _base(source, "owning_capability_provider")
        proof.update({"state": "REQUIRES_LIVE_PROBE",
                      "reason": "file_snapshot_cannot_admit_a_capability"})
        return proof
    raise ValueError("unsupported_resource_kind")
