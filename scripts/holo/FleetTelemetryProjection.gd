extends RefCounted

## Schema-pinned projection for the fleet telemetry snapshot
## (C:\GSV\state\fleet-telemetry.json, schema kilocore.fleet-telemetry.v1),
## written by tools/fleet_feed/fleet_feed.ps1 on the MSI (via mssh or the
## MuseFleetFeed scheduled task, every 5 min).
##
## Same discipline as the Mind's projections (PRs #8–#11): admit only named
## fields, bounded; reject malformed / wrong-schema / oversized bodies with a
## fixed reason string. Unknown rig keys are ignored; missing rigs read as
## unknown. No paths, prompts, secrets, or tokens cross — only states,
## counts, and bounded note strings.

const EXPECTED_SCHEMA := "kilocore.fleet-telemetry.v1"
const MAX_BODY_CHARS := 65536
const MAX_SERVICES := 32
const MAX_TASKS := 16
const MAX_NOTE_CHARS := 200
const MAX_SEATS_CHARS := 200

const KNOWN_RIGS: PackedStringArray = ["msi", "i3", "l9", "xanadu"]
const RIG_STATES: PackedStringArray = ["live", "unavailable", "degraded", "unknown"]
const SERVICE_STATES: PackedStringArray = ["up", "down", "unknown"]

static func parse_telemetry(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BODY_CHARS:
		return _invalid("telemetry_response_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	if body.get("schema", "") != EXPECTED_SCHEMA:
		return _invalid("unknown_telemetry_schema")
	var generated_unix_ms: Variant = body.get("generated_unix_ms", null)
	if typeof(generated_unix_ms) != TYPE_INT and typeof(generated_unix_ms) != TYPE_FLOAT:
		return _invalid("invalid_generated_at")
	var gen_n := float(generated_unix_ms)
	if gen_n < 0.0 or gen_n > 10000000000000.0 or floorf(gen_n) != gen_n:
		return _invalid("invalid_generated_at")
	var raw_rigs: Variant = body.get("rigs", null)
	if typeof(raw_rigs) != TYPE_DICTIONARY:
		return _invalid("missing_rigs")
	var rigs := {}
	for rig_id in KNOWN_RIGS:
		rigs[rig_id] = _parse_rig((raw_rigs as Dictionary).get(rig_id, {}))
	return {
		"ok": true,
		"telemetry": {
			"schema": EXPECTED_SCHEMA,
			"generated_at": String(body.get("generated_at", "")).substr(0, 64),
			"generated_unix_ms": int(gen_n),
			"probe_host": String(body.get("probe_host", "")).substr(0, 64),
			"rigs": rigs,
		},
	}


static func _parse_rig(raw: Variant) -> Dictionary:
	var rig := {
		"state": "unknown",
		"ram_free_mb": -1,
		"ram_total_mb": -1,
		"ram_free_pct": -1.0,
		"cpu_load_pct": -1,
		"services": {},
		"tasks": {},
		"seats": "",
		"note": "",
	}
	if typeof(raw) != TYPE_DICTIONARY:
		return rig
	var d: Dictionary = raw
	var state := String(d.get("state", "unknown"))
	rig["state"] = state if RIG_STATES.has(state) else "unknown"
	rig["ram_free_mb"] = _bounded_int(d.get("ram_free_mb", null), 0, 10000000)
	rig["ram_total_mb"] = _bounded_int(d.get("ram_total_mb", null), 0, 10000000)
	rig["ram_free_pct"] = _bounded_float(d.get("ram_free_pct", null), 0.0, 100.0)
	rig["cpu_load_pct"] = _bounded_int(d.get("cpu_load_pct", null), 0, 100)
	rig["services"] = _bounded_string_map(d.get("services", {}), MAX_SERVICES, SERVICE_STATES)
	rig["tasks"] = _bounded_string_map(d.get("tasks", {}), MAX_TASKS, [])
	rig["seats"] = String(d.get("seats", "")).substr(0, MAX_SEATS_CHARS)
	rig["note"] = String(d.get("note", "")).substr(0, MAX_NOTE_CHARS)
	return rig


## -1 for missing / wrong-typed / out-of-range. Never a fabricated zero.
static func _bounded_int(value: Variant, low: int, high: int) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1
	var n := float(value)
	if n < float(low) or n > float(high) or floorf(n) != n:
		return -1
	return int(n)


static func _bounded_float(value: Variant, low: float, high: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var n := float(value)
	if n < low or n > high:
		return -1.0
	return n


## Admits at most `cap` entries; keys capped at 64 chars, values capped at 64.
## When `allowed` is non-empty, values outside it map to "unknown" (lenient on
## values, strict on shape — a weird service state is unknown, never fatal).
static func _bounded_string_map(raw: Variant, cap: int, allowed: PackedStringArray) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	for key in d.keys():
		if out.size() >= cap:
			break
		var k := String(key).substr(0, 64)
		var v := String(d.get(key, "")).substr(0, 64)
		if not allowed.is_empty() and not allowed.has(v):
			v = "unknown"
		out[k] = v
	return out


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
