extends RefCounted

## A bounded, schema-pinned *observation* of the Studio project constellation.
## The /api/projects scan is slow (its own backend times out after 15s), so the
## sensor that uses this projection is cached with source age — never polled
## unboundedly. Only explicitly admitted fields cross into the scene tree:
## schema, scan state/source, generated_at, a bounded project count, and at
## most MAX_PROJECTS project name/status pairs. No project bodies, paths,
## prompts, secrets, or tokens.

const EXPECTED_SCHEMA := "kilocore-studio.projects-scan.v2"
const MAX_BODY_CHARS := 262144
const MAX_PROJECTS := 50
const MAX_COUNT := 1000000
const MAX_NAME_LENGTH := 120
const MAX_STATUS_LENGTH := 64
const MAX_REASON_LENGTH := 240
const MAX_SOURCE_LENGTH := 120
const MAX_GENERATED_AT_LENGTH := 64

static func parse_projects(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BODY_CHARS:
		return _invalid("projects_response_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	if body.get("schema", "") != EXPECTED_SCHEMA:
		return _invalid("unknown_projects_schema")
	var generated_at: Variant = body.get("generated_at", null)
	if typeof(generated_at) != TYPE_STRING or generated_at.is_empty() or generated_at.length() > MAX_GENERATED_AT_LENGTH:
		return _invalid("invalid_generated_at")
	var scan_state: Variant = body.get("state", null)
	if typeof(scan_state) != TYPE_STRING or scan_state.is_empty() or scan_state.length() > MAX_STATUS_LENGTH:
		return _invalid("invalid_scan_state")
	var source: Variant = body.get("source", null)
	if typeof(source) != TYPE_STRING or source.length() > MAX_SOURCE_LENGTH:
		return _invalid("invalid_source")
	var reason: Variant = body.get("reason", "")
	if typeof(reason) != TYPE_STRING or reason.length() > MAX_REASON_LENGTH:
		return _invalid("invalid_reason")
	var raw_count: Variant = body.get("count", null)
	var count: int = -1
	if raw_count != null:
		if typeof(raw_count) != TYPE_INT and typeof(raw_count) != TYPE_FLOAT:
			return _invalid("invalid_project_count")
		var n := float(raw_count)
		if n < 0.0 or n > float(MAX_COUNT) or floorf(n) != n:
			return _invalid("invalid_project_count")
		count = int(n)
	var raw_projects: Variant = body.get("projects", null)
	var admitted: Array = []
	var skipped: int = 0
	if raw_projects != null:
		if typeof(raw_projects) != TYPE_ARRAY:
			return _invalid("invalid_projects")
		for entry in raw_projects:
			if admitted.size() >= MAX_PROJECTS:
				skipped += 1
				continue
			if typeof(entry) != TYPE_DICTIONARY:
				skipped += 1
				continue
			var pname: Variant = entry.get("name", null)
			if typeof(pname) != TYPE_STRING or pname.is_empty() or pname.length() > MAX_NAME_LENGTH:
				skipped += 1
				continue
			var pstatus: Variant = entry.get("status", "")
			if typeof(pstatus) != TYPE_STRING or pstatus.length() > MAX_STATUS_LENGTH:
				skipped += 1
				continue
			admitted.append({"name": pname, "status": pstatus})
	var has_constellation: bool = raw_count != null and raw_projects != null
	return {
		"ok": true,
		"observation": {
			"state": "live" if has_constellation else "unavailable",
			"source": "KiloCore-Studio/GET-api-projects",
			"schema": EXPECTED_SCHEMA,
			"scan_state": scan_state,
			"scan_source": source,
			"generated_at": generated_at,
			"project_count": count,
			"projects": admitted,
			"projects_admitted": admitted.size(),
			"projects_skipped": skipped,
			"reason": reason,
			"observed_at_ms": 0,
			"error": "" if has_constellation else "constellation_scan_unavailable",
		}
	}

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
