extends RefCounted

## Portable bounded source capsule. This is *context*, not a session, approval
## grant, connector token, model memory or execution receipt.
const SCHEMA := "gsv.hyperspace-agent-handoff.v1"
const MAX_BYTES := 12000
const CONTRACT = preload("res://scripts/workstation/WorkbenchMissionContract.gd")
const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")

static func build(selected: Dictionary, graph: Dictionary, snapshot: Dictionary) -> Dictionary:
    var key := String(selected.get("key", ""))
    var source: Dictionary = {}
    for node in graph.get("nodes", []):
        if typeof(node) == TYPE_DICTIONARY and String(node.get("key", "")) == key:
            source = node
            break
    if source.is_empty():
        return {"ok": false, "reason": "not_in_current_graph"}
    var kind := String(source.get("kind", ""))
    var id := String(source.get("id", ""))
    if not ["rig", "project", "mission", "service", "capability"].has(kind) or id.is_empty() or id.length() > 500:
        return {"ok": false, "reason": "invalid_resource"}
    var owner := "unknown"
    var route := "refresh_source"
    var next_step := "Recheck the owning source and its runtime admission before execution."
    var ref := {
        "kind": kind, "id": id,
        "title": String(source.get("title", "")).substr(0, 80).strip_escapes(),
        "state": String(source.get("status", "unknown")).substr(0, 60),
        "source": String(source.get("source", "unknown")).substr(0, 150),
        "observed": bool(source.get("observed", false)),
        "execution_admitted": false
    }
    match kind:
        "project":
            var branch := String(source.get("detail", ""))
            if not CONTRACT._safe_path(id) or not CONTRACT._safe_branch(branch):
                return {"ok": false, "reason": "unqualified_project"}
            ref["repo"] = id
            ref["branch"] = branch
            owner = "KiloCore-Studio"
            route = "compose_studio_r0_after_fresh_recheck"
            next_step = "Re-observe exact repo and branch in Studio, draft bounded acceptance, explicitly submit R0. R2 needs separate human approval."
        "mission":
            if not CATALOG.valid_mission_id(id):
                return {"ok": false, "reason": "invalid_mission_id"}
            ref["updated_at"] = String(source.get("updated_at", "")).substr(0, 48)
            ref["risk"] = String(source.get("detail", "")).substr(0, 50)
            var repo := String(source.get("repo", ""))
            if CONTRACT._safe_path(repo):
                ref["repo"] = repo
            owner = "KiloCore-Studio"
            route = "inspect_mission_log_validator_receipt"
            next_step = "Read current Studio mission status, log and validator/receipt. If awaiting R2 approval, use authorized Studio approval, never assume a green build."
        "rig":
            owner = "FleetBridge / Kilo_Core / KiloCore-Studio"
            route = "inspect_observed_body_then_requalify"
        "service":
            owner = "Kilo_Core / KiloCore-Studio"
            route = "inspect_service_owner_health"
        "capability":
            ref["grade"] = String(source.get("grade", "D"))
            ref["machine"] = String(source.get("machine", "unknown"))
            ref["cost_class"] = String(source.get("cost_class", "unknown"))
            ref["evidence"] = String(source.get("evidence", "")).substr(0, 450).strip_escapes()
            ref["observed"] = false
            owner = "gsv-steward / Kilo_Core / owning capability provider"
            route = "requalify_capability_with_owner"
            next_step = "Probe owner for installed/callable/authenticated/qualified/admitted state. Snapshot is never execution authority."
    var bodies: Array[Dictionary] = []
    for node in graph.get("nodes", []):
        if typeof(node) == TYPE_DICTIONARY and node.get("kind") == "rig":
            bodies.append({
                "id": String(node.get("id", "")).substr(0, 64),
                "state": String(node.get("status", "unknown")).substr(0, 48)
            })
    var capsule := {
        "schema": SCHEMA,
        "generated_utc": Time.get_datetime_string_from_system(true) + "Z",
        "resource": ref,
        "next_step": next_step,
        "authority": {"owner": owner, "next_route": route,
            "actor_authenticated": false, "permission_granted": false,
            "session_attached": false, "studio_r2_bypassed": false},
        "sources": {
            "projects": String(snapshot.get("project_feed_state", "unknown")),
            "missions": String(snapshot.get("mission_feed_state", "unknown")),
            "bodies": String(snapshot.get("body_feed_state", "unknown")),
            "services": String(snapshot.get("service_feed_state", "unknown")),
            "capabilities": String(graph.get("atlas_source", "not_connected")),
            "snapshot_missing_timestamps_do_not_imply_freshness": true,
            "known_bodies": bodies
        },
        "candidate_integrations_not_invoked": [
            "KiloCore Studio mission and receipts",
            "Kilo_Core admitted agent registry",
            "gsv-steward capability atlas",
            "GSV exact-head build/check",
            "Dev-Mentor and Terminal Depths game sessions",
            "GitHub + user-connected ChatGPT plugins through their owning permissions"
        ],
        "contract": "This is inert context. Verify owner identity, session, scope, budget, source time and risk before any tool call."
    }
    var text := JSON.stringify(capsule, "  ")
    if text.to_utf8_buffer().size() > MAX_BYTES:
        return {"ok": false, "reason": "too_large"}
    return {"ok": true, "json": text, "data": capsule}

static func validate(blob: String) -> Dictionary:
    if blob.to_utf8_buffer().size() > MAX_BYTES:
        return {"ok": false, "reason": "too_large"}
    var parser := JSON.new()
    if parser.parse(blob) != OK or typeof(parser.data) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "bad_json"}
    var capsule: Dictionary = parser.data
    if capsule.get("schema", "") != SCHEMA or typeof(capsule.get("resource")) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "wrong_schema"}
    if typeof(capsule.get("authority")) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "no_authority_boundary"}
    var grants: Dictionary = capsule["authority"]
    for name in ["actor_authenticated", "permission_granted", "session_attached", "studio_r2_bypassed"]:
        if grants.get(name, true) != false:
            return {"ok": false, "reason": "false_grant"}
    var ref: Dictionary = capsule["resource"]
    match String(ref.get("kind", "")):
        "project":
            if not CONTRACT._safe_path(String(ref.get("repo", ""))) or not CONTRACT._safe_branch(String(ref.get("branch", ""))):
                return {"ok": false, "reason": "bad_project"}
        "mission":
            if not CATALOG.valid_mission_id(String(ref.get("id", ""))):
                return {"ok": false, "reason": "bad_mission"}
        "rig", "service", "capability":
            if String(ref.get("id", "")).is_empty():
                return {"ok": false, "reason": "bad_identity"}
        _:
            return {"ok": false, "reason": "bad_kind"}
    return {"ok": true, "resource": ref.duplicate(true)}
