class_name CapabilityAtlasProjection
extends RefCounted

## Schema-pinned projection for the graded capability atlas
## (res://data/capability_atlas.json, schema kilocore.capability-atlas.v1),
## generated from the Slice 5 synthesis (CAPABILITY-ATLAS-20261108.md §1 + §5).
##
## Same discipline as the Mind's projections (PRs #8–#11) and the fleet
## telemetry projection: admit only named fields, bounded; reject malformed /
## wrong-schema / oversized bodies with a fixed reason string. Unknown grades,
## machines, cost classes, kinds, or states reject the document — a grade is
## a claim with evidence, and an ungraded entry is never silently admitted.
## A missing machine is its own reason (missing_machine), so a bad row can
## never lose its rig. No paths, prompts, secrets, or tokens cross — only
## grades, states, and bounded note strings.

const EXPECTED_SCHEMA := "kilocore.capability-atlas.v1"
const MAX_BODY_CHARS := 131072
const MAX_ENTRIES := 128
const MAX_ID_CHARS := 64
const MAX_NAME_CHARS := 64
const MAX_EVIDENCE_CHARS := 300
const MAX_CAN_DO_CHARS := 200
const MAX_DISCREPANCY_CHARS := 1024
const MAX_STRING_CHARS := 128

const KINDS: PackedStringArray = [
	"seat", "harness", "model", "service", "hardware", "software",
	"cloud", "wrapper", "vault", "agent", "capability",
]
const MACHINES: PackedStringArray = ["msi", "i3", "l9", "xanadu"]
const GRADES: PackedStringArray = ["D", "I", "C", "Q", "U", "M"]
const COST_CLASSES: PackedStringArray = ["tokenless", "cloud", "mixed"]
const STATES: PackedStringArray = [
	"live", "unavailable", "planned", "not_detected", "degraded",
]


static func parse_atlas(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BODY_CHARS:
		return _invalid("atlas_response_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	if body.get("schema", "") != EXPECTED_SCHEMA:
		return _invalid("unknown_atlas_schema")
	var raw_entries: Variant = body.get("entries", null)
	if typeof(raw_entries) != TYPE_ARRAY:
		return _invalid("missing_entries")
	var raw: Array = raw_entries
	if raw.size() > MAX_ENTRIES:
		return _invalid("too_many_entries")
	var entries: Array = []
	var seen: Dictionary = {}
	for raw_entry in raw:
		var entry: Dictionary = _parse_entry(raw_entry)
		if entry.has("_error"):
			return _invalid(String(entry.get("_error", "malformed_entry")))
		var entry_id := String(entry.get("id", ""))
		if seen.has(entry_id):
			return _invalid("duplicate_entry_id")
		seen[entry_id] = true
		entries.append(entry)
	return {
		"ok": true,
		"atlas": {
			"schema": EXPECTED_SCHEMA,
			"generated_at": String(body.get("generated_at", "")).substr(0, 64),
			"source": String(body.get("source", "")).substr(0, MAX_STRING_CHARS),
			"notes": String(body.get("notes", "")).substr(0, 1024),
			"entries": entries,
		},
	}


## One entry, strictly validated. Returns {}-with-_error on rejection (the
## caller returns it as the document rejection), or the admitted entry.
static func _parse_entry(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"_error": "malformed_entry"}
	var d: Dictionary = raw
	var entry_id := String(d.get("id", "")).substr(0, MAX_ID_CHARS)
	if entry_id.is_empty():
		return {"_error": "malformed_entry"}
	var kind := String(d.get("kind", ""))
	if not KINDS.has(kind):
		return {"_error": "unknown_kind"}
	if not d.has("machine"):
		return {"_error": "missing_machine"}
	var machine := String(d.get("machine", ""))
	if not MACHINES.has(machine):
		return {"_error": "missing_machine"}
	var grade := String(d.get("grade", ""))
	if not GRADES.has(grade):
		return {"_error": "unknown_grade"}
	var cost_class := String(d.get("cost_class", ""))
	if not COST_CLASSES.has(cost_class):
		return {"_error": "unknown_cost_class"}
	var state := String(d.get("state", ""))
	if not STATES.has(state):
		return {"_error": "unknown_state"}
	var name := String(d.get("name", "")).substr(0, MAX_NAME_CHARS)
	if name.is_empty():
		return {"_error": "malformed_entry"}
	var evidence := String(d.get("evidence", "")).substr(0, MAX_EVIDENCE_CHARS)
	if evidence.is_empty():
		return {"_error": "malformed_entry"}
	var entry := {
		"id": entry_id,
		"name": name,
		"kind": kind,
		"machine": machine,
		"grade": grade,
		"cost_class": cost_class,
		"state": state,
		"evidence": evidence,
		"can_do": String(d.get("can_do", "")).substr(0, MAX_CAN_DO_CHARS),
		"discrepancy": String(d.get("discrepancy", "")).substr(0, MAX_DISCREPANCY_CHARS),
		"telemetry": _parse_telemetry_map(d.get("telemetry", {})),
		"overlay": "static_only",
	}
	return entry


## Optional live-probe mapping for one entry: {"rig": <machine>,
## "service": <fleet-feed service key>} or {"rig": <machine>,
## "seat": <process name in the rig's seats list>}. Malformed maps are
## dropped (the entry keeps its static state) — never fatal.
static func _parse_telemetry_map(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = raw
	var rig := String(d.get("rig", ""))
	if not MACHINES.has(rig):
		return {}
	if d.has("service"):
		var service := String(d.get("service", "")).substr(0, 64)
		if service.is_empty():
			return {}
		return {"rig": rig, "service": service}
	if d.has("seat"):
		var seat := String(d.get("seat", "")).substr(0, 64)
		if seat.is_empty():
			return {}
		return {"rig": rig, "seat": seat}
	return {}


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
