#!/usr/bin/env python3
"""Export a bounded, source-stamped PR investigation queue, never a merge authority.

Pulls read-only GitHub CLI facts. Does NOT write GitHub, contact agents or
perform reviews. Candidate actors require a separately observed, fresh
availability feed. One output is an atomic, cacheable, sanitized JSON snapshot.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable

SCHEMA = "gsv.review-operations.v1"
ACTORS_SCHEMA = "gsv.actor-availability.v1"
ORG = "GSV-Sublime-Optimization"
MAX_BYTES = 131072
MAX_ITEMS = 48
MAX_DETAILS = 20
MAX_OUTPUT_TEXT = 1048576
SHA = re.compile(r"^[0-9a-f]{40}$")
REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
URL = re.compile(r"^https://github\.com/GSV-Sublime-Optimization/[A-Za-z0-9_.-]+/pull/[0-9]{1,7}$")
ACTOR = re.compile(r"^agent/[A-Za-z0-9_.-]{1,72}$")
ISO = "%Y-%m-%dT%H:%M:%SZ"
PR_FIELDS = "headRefOid,baseRefName,reviewDecision,mergeable,isDraft,statusCheckRollup,body,changedFiles"

class ReviewError(Exception):
    pass

def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)

def ts(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else None
    except ValueError:
        return None

def bounded_text(value: Any, limit: int) -> str:
    return (value[:limit] if isinstance(value, str) else "").replace("\x00", "").replace("\r", " ").replace("\n", " ")

def gh_json(argv: list[str], timeout: int = 16) -> Any:
    """Never use a shell, a shell environment token, or unbounded output."""
    args = ["gh", *argv]
    try:
        run = subprocess.run(args, capture_output=True, check=False,
                             text=True, encoding="utf-8", errors="replace",
                             timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ReviewError("github_cli_unavailable_or_timeout") from exc
    if run.returncode != 0:
        # gh stderr could contain secrets; intentionally do not repeat it.
        raise ReviewError("github_cli_nonzero")
    if len(run.stdout.encode("utf-8")) > MAX_OUTPUT_TEXT:
        raise ReviewError("github_reply_oversized")
    try:
        return json.loads(run.stdout)
    except ValueError as exc:
        raise ReviewError("github_json_invalid") from exc

def source_rows(limit: int, run_gh: Callable[[list[str]], Any] = gh_json) -> list[dict[str, Any]]:
    raw = run_gh(["search", "prs", "--owner", ORG, "--state", "open",
                  "--limit", str(limit), "--json",
                  "number,title,repository,updatedAt,isDraft,url"])
    if not isinstance(raw, list) or len(raw) > MAX_ITEMS:
        raise ReviewError("search_collection_invalid")
    return raw

def check_rollup(value: Any) -> str:
    if not isinstance(value, list) or not value:
        return "unobserved"
    states: list[str] = []
    for item in value[:50]:
        if not isinstance(item, dict):
            return "unobserved"
        status = str(item.get("status", item.get("state", ""))).upper()
        conclusion = str(item.get("conclusion", "")).upper()
        if conclusion in {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED"} or status in {"FAILURE", "ERROR"}:
            states.append("failed")
        elif conclusion == "SUCCESS" or (status == "SUCCESS" and conclusion in {"SUCCESS", ""}):
            states.append("passed")
        else:
            states.append("pending")
    return ("failed" if "failed" in states else
            "pending" if "pending" in states else "passed")

def review_lane(item: dict[str, Any]) -> tuple[str, list[str]]:
    if not item["detail_observed"]:
        return "inspect_source", ["details_unobserved"]
    blockers: list[str] = []
    if item["draft"]:
        blockers.append("draft")
    if item["mergeable"] == "CONFLICTING":
        blockers.append("conflict")
    if item["ci"] == "failed":
        blockers.append("ci_failed")
    elif item["ci"] in {"unobserved", "pending"}:
        blockers.append("ci_unverified")
    if not item["provenance"]:
        blockers.append("author_provenance_missing")
    if item["review"] == "CHANGES_REQUESTED":
        blockers.append("changes_requested")
    elif item["review"] != "APPROVED":
        blockers.append("independent_review_unverified")
    if item["head"] == "":
        blockers.append("exact_head_unverified")
    if item["base"] != "master" and item["base"] != "main":
        blockers.append("stacked_dependency")
    if "conflict" in blockers:
        return "repair_conflict", blockers
    if "ci_failed" in blockers:
        return "repair_ci", blockers
    if "author_provenance_missing" in blockers:
        return "author_provenance", blockers
    if "changes_requested" in blockers:
        return "author_changes", blockers
    if "draft" in blockers:
        return "author_admission", blockers
    if "stacked_dependency" in blockers:
        return "dependency_review", blockers
    if item["ci"] != "passed":
        return "verify_check", blockers
    if item["review"] != "APPROVED":
        return "independent_review", blockers
    return "gate_recheck_candidate", blockers

def skills_for(title: str, repo: str) -> list[str]:
    source = (title + " " + repo).lower()
    skills: list[str] = []
    if "godot" in source or "game" in source or "fury" in source or "bastion" in source:
        skills.append("godot")
    if "gateway" in source or "fleet" in source or "security" in source or "auth" in source:
        skills.append("security")
    if "python" in source or "agent" in source or "mentor" in source or "api" in source:
        skills.append("python")
    if "docs" in source or "readme" in source:
        skills.append("docs")
    return skills or ["code"]

def rank(item: dict[str, Any]) -> int:
    scores = {
        "gate_recheck_candidate": 100,
        "independent_review": 92,
        "verify_check": 75,
        "repair_ci": 70,
        "repair_conflict": 58,
        "author_changes": 50,
        "author_provenance": 40,
        "dependency_review": 35,
        "author_admission": 28,
        "inspect_source": 18,
    }
    size = item.get("changed_files")
    small_bonus = 6 if type(size) is int and size <= 5 else 3 if type(size) is int and size <= 12 else 0
    return scores[item["lane"]] + small_bonus

def availability(path: Path | None, now: dt.datetime) -> list[dict[str, Any]]:
    if path is None:
        return []
    try:
        if not path.is_file() or path.stat().st_size > 16000:
            return []
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if not isinstance(raw, dict) or raw.get("schema") != ACTORS_SCHEMA:
        return []
    generated = ts(raw.get("generated_utc"))
    if generated is None or not 0 <= (now - generated).total_seconds() <= 600:
        return []
    records = raw.get("actors")
    if not isinstance(records, list) or len(records) > 24:
        return []
    accepted: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in records:
        if not isinstance(item, dict):
            continue
        ident = item.get("id")
        if not isinstance(ident, str) or not ACTOR.fullmatch(ident) or ident in seen:
            continue
        if item.get("state") != "available" or item.get("can_review") is not True:
            continue
        cap, busy = item.get("max_concurrent"), item.get("active")
        if type(cap) is not int or type(busy) is not int or cap not in {1, 2} or busy < 0 or busy >= cap:
            continue
        skills = item.get("skills")
        if not isinstance(skills, list) or any(not isinstance(x, str) or len(x) > 24 for x in skills):
            continue
        checked = ts(item.get("observed_utc"))
        if checked is None or not 0 <= (now - checked).total_seconds() <= 300:
            continue
        seen.add(ident)
        accepted.append({"id": ident, "skills": skills[:16], "slots": cap - busy})
    return accepted

def route(candidates: list[dict[str, Any]], actors: list[dict[str, Any]]) -> None:
    # Sequential advisory allocation. Only exact observed capacity. No actual dispatch.
    for item in candidates:
        item["suggested_actor"] = ""
        item["assignment_authorized"] = False
        item["routing_reason"] = "no_fresh_qualified_reviewer_capacity"
        if item["lane"] not in {"independent_review", "gate_recheck_candidate",
                                "verify_check", "repair_ci", "repair_conflict", "inspect_source"}:
            item["routing_reason"] = "source_owner_or_dependency_action_required"
            continue
        for actor in actors:
            if actor["slots"] <= 0:
                continue
            if item["required_skill"] not in actor["skills"] and "code" not in actor["skills"]:
                continue
            # Identity of PR author in the GitHub account is not the colony's
            # engineering_actor, so independence cannot be proven here.
            item["suggested_actor"] = actor["id"]
            item["routing_reason"] = "candidate_only_independence_and_permissions_unverified"
            actor["slots"] -= 1
            break

def collect(rows: list[dict[str, Any]],
            details: dict[str, dict[str, Any]],
            now: dt.datetime,
            actors: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in rows[:MAX_ITEMS]:
        if not isinstance(raw, dict) or not isinstance(raw.get("repository"), dict):
            continue
        repo = raw["repository"].get("nameWithOwner", "")
        nr = raw.get("number")
        url = raw.get("url")
        if not isinstance(repo, str) or not REPO.fullmatch(repo) or not repo.startswith(ORG + "/"):
            continue
        if type(nr) is not int or nr <= 0 or nr > 9999999:
            continue
        if not isinstance(url, str) or not URL.fullmatch(url):
            continue
        key = f"{repo}#{nr}"
        if key in seen:
            continue
        seen.add(key)
        extra = details.get(key, {})
        head = extra.get("headRefOid", "")
        head = head if isinstance(head, str) and SHA.fullmatch(head) else ""
        body = extra.get("body")
        has_provenance = isinstance(body, str) and (
            "<!-- KILOCORE-PROVENANCE-V1 -->" in body
            and "<!-- /KILOCORE-PROVENANCE-V1 -->" in body)
        review = extra.get("reviewDecision", "")
        review = review if review in {"APPROVED", "CHANGES_REQUESTED"} else "UNVERIFIED"
        mergeable = extra.get("mergeable")
        mergeable = mergeable if mergeable in {"MERGEABLE", "CONFLICTING"} else "UNKNOWN"
        base = bounded_text(extra.get("baseRefName"), 90) or "unknown"
        item = {
            "key": key, "repo": repo, "number": nr, "url": url,
            "title": bounded_text(raw.get("title"), 130),
            "updated_at": bounded_text(raw.get("updatedAt"), 36),
            "head": head, "base": base,
            "draft": raw.get("isDraft") is True,
            "ci": check_rollup(extra.get("statusCheckRollup")),
            "review": review, "mergeable": mergeable,
            "provenance": has_provenance,
            "changed_files": extra.get("changedFiles") if type(extra.get("changedFiles")) is int
                                and 0 <= extra["changedFiles"] <= 5000 else None,
            "required_skill": skills_for(str(raw.get("title", "")), repo)[0],
            "detail_observed": bool(extra),
        }
        item["lane"], item["blockers"] = review_lane(item)
        item["score"] = rank(item)
        out.append(item)
    out.sort(key=lambda row: (-row["score"], row["key"]))
    route(out, actors or [])
    return {
        "schema": SCHEMA,
        "generated_utc": now.strftime(ISO),
        "ttl_seconds": 300,
        "source": "GitHub gh-cli read-only",
        "actor_source": "optional fresh local availability feed" if actors else "unobserved",
        "gate": "advisory_only_exact_head_gsv_merge_dry_run_required",
        "counts": {
            "open_sampled": len(out),
            "detail_observed": sum(bool(x["detail_observed"]) for x in out),
            "review_candidates": sum(x["lane"] in {"independent_review", "gate_recheck_candidate"} for x in out),
        },
        "items": out,
    }

def dump_atomic(dest: Path, data: dict[str, Any]) -> None:
    content = (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    if len(content) > MAX_BYTES:
        raise ReviewError("snapshot_too_large")
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp: str | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", dir=dest.parent, prefix=".review-",
                                         suffix=".tmp", delete=False) as handle:
            tmp = handle.name
            handle.write(content)
        os.replace(tmp, dest)
    finally:
        if tmp and os.path.exists(tmp):
            os.unlink(tmp)

def run(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--output", type=Path, required=True,
                    help="Explicit local JSON destination, e.g. %%APPDATA%%/Godot/app_userdata/.../review_queue.json")
    ap.add_argument("--limit", type=int, default=24)
    ap.add_argument("--details", type=int, default=12)
    ap.add_argument("--availability", type=Path, help="Optional TTL-bound actor availability JSON")
    ap.add_argument("--fixture", type=Path, help="Offline test fixture; no GitHub calls")
    args = ap.parse_args(argv)
    if not 1 <= args.limit <= MAX_ITEMS or not 0 <= args.details <= MAX_DETAILS:
        ap.error("limit 1..48 and details 0..20")
    try:
        if args.fixture:
            raw = json.loads(args.fixture.read_text(encoding="utf-8"))
            rows, detail = raw["rows"], raw["details"]
        else:
            rows = source_rows(args.limit)
            detail = {}
            for row in rows[:args.details]:
                repo = row.get("repository", {}).get("nameWithOwner", "")
                number = row.get("number")
                if not isinstance(repo, str) or not REPO.fullmatch(repo) or type(number) is not int:
                    continue
                try:
                    detail[f"{repo}#{number}"] = gh_json(
                        ["pr", "view", str(number), "-R", repo, "--json", PR_FIELDS], timeout=18)
                except ReviewError:
                    # Missing detail is explicitly unknown, never falsely approved.
                    pass
        now = now_utc()
        result = collect(rows, detail, now, availability(args.availability, now))
        dump_atomic(args.output, result)
    except (OSError, KeyError, TypeError, ValueError, ReviewError) as exc:
        print("REVIEW_QUEUE_REFUSED: " + str(exc).split("\n", 1)[0][:140], file=sys.stderr)
        return 2
    print(f"REVIEW_QUEUE_EXPORTED {args.output} items={len(result['items'])} "
          f"observed={result['counts']['detail_observed']} "
          "advisory_only=true")
    return 0

if __name__ == "__main__":
    raise SystemExit(run())
