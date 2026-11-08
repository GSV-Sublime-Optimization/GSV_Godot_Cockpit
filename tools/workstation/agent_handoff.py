#!/usr/bin/env python3
"""Inspect an exported Hyperspace context capsule without granting any tool authority."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA = "gsv.hyperspace-agent-handoff.v1"
MAX_BYTES = 12000
MISSION_RE = re.compile(r"^msn_[0-9a-f]{12}$")
BRANCH_RE = re.compile(r"^[A-Za-z0-9_./-]{1,160}$")
KINDS = {"project", "mission", "rig", "service", "capability"}
ROUTES = {
    "compose_studio_r0_after_fresh_recheck",
    "inspect_mission_log_validator_receipt",
    "inspect_observed_body_then_requalify",
    "inspect_service_owner_health",
    "requalify_capability_with_owner",
}


def _safe_repo(value: object) -> bool:
    return (
        isinstance(value, str) and 3 <= len(value) <= 500
        and (bool(re.match(r"^[A-Za-z]:[/\\]", value)) or value.startswith("/"))
        and ".." not in value and "://" not in value
        and "\n" not in value and "\r" not in value
    )


def validate(value: Any) -> dict[str, Any]:
    """Return a strict, inert projection. Never execute or trust asserted privileges."""
    if not isinstance(value, dict) or value.get("schema") != SCHEMA:
        raise ValueError("wrong_schema")
    ref, auth = value.get("resource"), value.get("authority")
    if not isinstance(ref, dict) or not isinstance(auth, dict):
        raise ValueError("missing_resource_or_authority")
    for field in ("actor_authenticated", "permission_granted", "session_attached", "studio_r2_bypassed"):
        if auth.get(field) is not False:
            raise ValueError("false_authority_grant")
    kind, ident = ref.get("kind"), ref.get("id")
    if not isinstance(kind, str) or kind not in KINDS or not isinstance(ident, str) or not 1 <= len(ident) <= 500:
        raise ValueError("invalid_resource")
    if ref.get("execution_admitted") is not False:
        raise ValueError("false_execution_admission")
    owner, route = auth.get("owner"), auth.get("next_route")
    if not isinstance(owner, str) or not owner or len(owner) > 140 or not isinstance(route, str) or route not in ROUTES:
        raise ValueError("bad_owner_route")
    if kind == "project":
        branch = ref.get("branch")
        if (not _safe_repo(ident) or ref.get("repo") != ident
                or not isinstance(branch, str) or not BRANCH_RE.fullmatch(branch)
                or ".." in branch or "@{" in branch):
            raise ValueError("invalid_project")
    if kind == "mission" and not MISSION_RE.fullmatch(ident):
        raise ValueError("invalid_mission")
    if kind == "capability" and ref.get("observed") is not False:
        raise ValueError("false_live_capability")
    title, state, next_step = ref.get("title", ""), ref.get("state", ""), value.get("next_step", "")
    if not all(isinstance(x, str) for x in (title, state, next_step)) or not 1 <= len(next_step) <= 500:
        raise ValueError("invalid_explanation")
    return {
        "schema": SCHEMA, "kind": kind, "id": ident, "title": title[:80],
        "state": state[:60], "owner": owner, "route": route,
        "next_step": next_step, "source": str(ref.get("source", "unknown"))[:150],
        "observed": ref.get("observed") is True,
        "execution_admitted": False, "permission_granted": False,
        "session_attached": False, "generated_utc": str(value.get("generated_utc", "unknown"))[:50],
        "repo": str(ref.get("repo", ""))[:500] if kind in {"project", "mission"} else "",
        "branch": str(ref.get("branch", ""))[:160] if kind == "project" else "",
    }


def load(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError("capsule_missing_or_oversized")
    return validate(json.loads(path.read_text(encoding="utf-8")))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("file", type=Path, help="Path printed by Hyperspace's export action")
    parser.add_argument("--json", action="store_true", help="Machine-readable allowlisted projection")
    parser.add_argument("--observe-studio", action="store_true",
                        help="Perform one source-bounded, read-only loopback Studio observation")
    parser.add_argument("--timeout", type=float, default=6.0,
                        help="Max seconds for one Studio GET (0.5..35, default 6)")
    args = parser.parse_args(argv)
    try:
        result = load(args.file)
        if args.observe_studio:
            from studio_reobserve import get_local_json, observe
            result["owner_observation"] = observe(
                result, lambda route: get_local_json(route, timeout=args.timeout))
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"HANDOFF_REFUSED: {exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"SOURCE: {result['kind']} {result['id']} [{result['state']}]")
        print(f"OWNER: {result['owner']} | ROUTE: {result['route']}")
        print(f"STEP: {result['next_step']}")
        if args.observe_studio:
            observed = result["owner_observation"]
            print("OWNER RE-OBSERVATION: " + json.dumps(observed, ensure_ascii=False, sort_keys=True))
        print("AUTHORITY: NONE. Recheck the owning system before any execution.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
