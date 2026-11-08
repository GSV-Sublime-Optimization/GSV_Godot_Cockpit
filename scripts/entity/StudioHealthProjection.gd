extends RefCounted

## An unprivileged, strictly typed *observation*, not a second mission store.
## Use current Studio server truth; reject anything that looks like the wrong API.

const EXPECTED_SCHEMA := "kilocore-studio.cockpit-health.v2"
const MAX_REASON_LENGTH := 120

static func parse_health(json_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	if body.get("schema", "") != EXPECTED_SCHEMA:
		return _invalid("unknown_health_schema")
	var raw_missions: Variant = body.get("missions", null)
	if typeof(raw_missions) != TYPE_DICTIONARY:
		return _invalid("missing_missions")
	var missions: Dictionary = raw_missions
	var counts := {}
	for key in ["awaiting", "running", "queued"]:
		var value: Variant = missions.get(key, null)
		if typeof(value) != TYPE_INT or value < 0:
			return _invalid("invalid_mission_count_" + key)
		counts[key] = value
	var gate: Variant = missions.get("thermal_gate", "")
	if typeof(gate) != TYPE_STRING or gate.is_empty() or gate.length() > MAX_REASON_LENGTH:
		return _invalid("invalid_thermal_gate")
	# Do not import mission titles/objectives, secrets, credentials, or arbitrary
	# raw JSON into the scene tree. Only explicitly admitted fields cross.
	return {
		"ok": true,
		"observation": {
			"state": "live",
			"source": "KiloCore-Studio/GET-api-health",
			"schema": EXPECTED_SCHEMA,
			"mission_counts": counts,
			"thermal_gate": gate,
			"observed_at_ms": 0,
			"error": ""
		}
	}

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
