extends RefCounted

## Safe adapter for Muse's kilocore.capability-atlas.v1 snapshot or a local
## exported provider catalogue. Snapshot presence is NOT callable/admitted proof.
const SCHEMA := "kilocore.capability-atlas.v1"
const MAX_BYTES := 131072
const MAX_ENTRIES := 128
const KINDS := ["seat", "harness", "model", "service", "hardware", "software",
    "cloud", "wrapper", "vault", "agent", "capability"]
const MACHINES := ["msi", "i3", "l9", "xanadu"]
const GRADES := ["D", "I", "C", "Q", "U", "M"]
const COST := ["tokenless", "cloud", "mixed"]
const STATES := ["live", "unavailable", "planned", "not_detected", "degraded"]

static func parse(data: String) -> Dictionary:
    if data.to_utf8_buffer().size() > MAX_BYTES:
        return {"ok": false, "reason": "oversized"}
    var j := JSON.new()
    if j.parse(data) != OK or typeof(j.data) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "malformed_json"}
    var body: Dictionary = j.data
    if body.get("schema", "") != SCHEMA:
        return {"ok": false, "reason": "wrong_schema"}
    var entries: Variant = body.get("entries", null)
    if typeof(entries) != TYPE_ARRAY or entries.size() > MAX_ENTRIES:
        return {"ok": false, "reason": "bad_entry_count"}
    var safe: Array[Dictionary] = []
    var ids: Dictionary = {}
    for raw in entries:
        if typeof(raw) != TYPE_DICTIONARY:
            return {"ok": false, "reason": "invalid_entry"}
        var id: Variant = raw.get("id")
        var name: Variant = raw.get("name")
        var kind: Variant = raw.get("kind")
        var machine: Variant = raw.get("machine")
        var grade: Variant = raw.get("grade")
        var cost: Variant = raw.get("cost_class")
        var state: Variant = raw.get("state")
        var evidence: Variant = raw.get("evidence")
        if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 64 or ids.has(id):
            return {"ok": false, "reason": "duplicate_or_bad_id"}
        if typeof(name) != TYPE_STRING or name.is_empty() or name.length() > 100:
            return {"ok": false, "reason": "invalid_name"}
        if typeof(kind) != TYPE_STRING or not KINDS.has(kind):
            return {"ok": false, "reason": "invalid_kind"}
        if typeof(machine) != TYPE_STRING or not MACHINES.has(machine):
            return {"ok": false, "reason": "invalid_machine"}
        if typeof(grade) != TYPE_STRING or not GRADES.has(grade):
            return {"ok": false, "reason": "invalid_grade"}
        if typeof(cost) != TYPE_STRING or not COST.has(cost):
            return {"ok": false, "reason": "invalid_cost"}
        if typeof(state) != TYPE_STRING or not STATES.has(state):
            return {"ok": false, "reason": "invalid_state"}
        if typeof(evidence) != TYPE_STRING or evidence.is_empty() or evidence.length() > 450:
            return {"ok": false, "reason": "invalid_evidence"}
        ids[id] = true
        safe.append({
            "id": id, "name": name.strip_escapes(), "kind": kind,
            "machine": machine, "grade": grade, "cost_class": cost,
            "snapshot_state": state, "evidence": evidence.strip_escapes(),
            "can_do": String(raw.get("can_do", "")).substr(0, 200).strip_escapes()
                if typeof(raw.get("can_do", "")) == TYPE_STRING else "",
            "discrepancy": String(raw.get("discrepancy", "")).substr(0, 1000).strip_escapes()
                if typeof(raw.get("discrepancy", "")) == TYPE_STRING else "",
            "source": "capability-atlas-file",
            "executable": false, "authenticated": false, "admitted": false
        })
    return {"ok": true, "entries": safe,
        "generated_at": String(body.get("generated_at", "")).substr(0, 48)
            if typeof(body.get("generated_at", "")) == TYPE_STRING else "",
        "snapshot_only": true}

static func read_optional() -> Dictionary:
    ## user:// is an explicit locally managed export by a trusted provider.
    ## res:// appears when Muse's Atlas edition is incorporated into this entry.
    var places := ["user://capability_atlas.json", "res://data/capability_atlas.json"]
    for path in places:
        if not FileAccess.file_exists(path):
            continue
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
            return {"ok": false, "reason": "cannot_read_snapshot", "source": path}
        if file.get_length() > MAX_BYTES:
            file.close()
            return {"ok": false, "reason": "oversized_snapshot", "source": path}
        var contents := file.get_as_text()
        file.close()
        var projected := parse(contents)
        projected["source"] = path
        return projected
    return {"ok": false, "reason": "atlas_not_connected",
        "source": "user://capability_atlas.json | res://data/capability_atlas.json"}
