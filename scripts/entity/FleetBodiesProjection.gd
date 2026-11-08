extends RefCounted

## A bounded read-only Godot projection of Studio's four fleet-body reports.
## Report freshness is NOT remote-work admission or permission to use tools.
const SCHEMA := "kilocore-studio.entity-bodies.v0"
const ENTITY_ID := "kilocore.colony.entity.primary.v0"
const BODY_IDS: PackedStringArray = [
	"kilo-core-msi",
	"desktop-i3anuvp",
	"desktop-l9v3emb",
	"imac-xanadu"
]
const ALLOWED_STATES: PackedStringArray = [
	"unknown", "invalid", "stale", "reported_fresh"
]

static func unknown() -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	for node_id in BODY_IDS:
		nodes.append({
			"body_id": node_id, "state": "unknown",
			"execution_authorized": false, "remote_work_admitted": false,
			"observation": {}
		})
	return nodes

static func parse_bodies(json_text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return {"ok": false, "reason": "malformed_json"}
	var raw: Variant = parser.data
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "wrong_root_type"}
	var data: Dictionary = raw
	if data.get("schema", "") != SCHEMA or data.get("entity_id", "") != ENTITY_ID:
		return {"ok": false, "reason": "unexpected_entity_contract"}
	var records: Variant = data.get("bodies", null)
	if typeof(records) != TYPE_ARRAY or records.size() != BODY_IDS.size():
		return {"ok": false, "reason": "unexpected_body_count"}
	var out: Array[Dictionary] = []
	var seen := {}
	for entry in records:
		if typeof(entry) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "non_object_body"}
		var item: Dictionary = entry
		var node_id: Variant = item.get("body_id", null)
		var state: Variant = item.get("state", null)
		if typeof(node_id) != TYPE_STRING or not BODY_IDS.has(node_id) or seen.has(node_id):
			return {"ok": false, "reason": "body_id_mismatch"}
		if typeof(state) != TYPE_STRING or not ALLOWED_STATES.has(state):
			return {"ok": false, "reason": "invalid_observation_state"}
		if item.get("identity_attested", true) != false or item.get("remote_work_admitted", true) != false or item.get("execution_authorized", true) != false:
			return {"ok": false, "reason": "unauthorized_body_claim"}
		seen[node_id] = true
		var projected := {
			"body_id": node_id, "state": state,
			"execution_authorized": false, "remote_work_admitted": false,
			"observation": {}
		}
		if state == "reported_fresh" or state == "stale":
			var observed: Variant = item.get("observation", null)
			if typeof(observed) != TYPE_DICTIONARY:
				return {"ok": false, "reason": "missing_physical_observation"}
			var record: Dictionary = observed
			var memory: Variant = record.get("memory_available_bytes", null)
			var disk: Variant = record.get("system_volume_free_bytes", null)
			if not _valid_int_or_unknown(memory) or not _valid_int_or_unknown(disk):
				return {"ok": false, "reason": "invalid_resource_measurement"}
			var age: Variant = item.get("age_seconds", null)
			if not _valid_int_or_unknown(age):
				return {"ok": false, "reason": "invalid_observation_age"}
			projected["observation"] = {
				"memory_available_bytes": memory,
				"system_volume_free_bytes": disk,
				"age_seconds": age
			}
		out.append(projected)
	return {"ok": true, "bodies": out}

static func _valid_int_or_unknown(value: Variant) -> bool:
	if value == null:
		return true
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var n := float(value)
	return n >= 0.0 and n <= 1.0e18 and floorf(n) == n
