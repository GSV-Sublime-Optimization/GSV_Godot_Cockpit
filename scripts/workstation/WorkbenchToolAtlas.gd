extends RefCounted

## Local, read-only discovery of explicitly exported tool/source presence.
## An installed repository is not a callable agent, authenticated connector or live service.
## Importing an atlas never triggers any process, network call or authority change.

const SCHEMA := "gsv.workstation.tool-atlas.v1"
const MAX_BYTES := 65536
const MAX_ITEMS := 32
const MAX_AGE_SECONDS := 300

static func load_from_environment() -> Dictionary:
	var path := OS.get_environment("GSV_WORKSTATION_TOOL_ATLAS")
	if path.is_empty():
		return {"state": "not_configured", "tools": []}
	if not path.is_absolute_path() or path.contains("..") or path.length() > 500:
		return {"state": "invalid", "tools": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"state": "unavailable", "tools": []}
	if file.get_length() > MAX_BYTES:
		return {"state": "invalid", "tools": []}
	return parse(file.get_as_text(), int(Time.get_unix_time_from_system()))

static func parse(text: String, now_unix: int) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"state": "invalid", "tools": []}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"state": "invalid", "tools": []}
	var payload: Variant = json.data
	if typeof(payload) != TYPE_DICTIONARY or payload.get("schema", "") != SCHEMA:
		return {"state": "invalid", "tools": []}
	var stamp: Variant = payload.get("observed_at_unix")
	var records: Variant = payload.get("tools")
	if typeof(stamp) != TYPE_INT or typeof(records) != TYPE_ARRAY or records.size() > MAX_ITEMS:
		return {"state": "invalid", "tools": []}
	if stamp < 1 or stamp > now_unix + 30:
		return {"state": "invalid", "tools": []}
	if now_unix - stamp > MAX_AGE_SECONDS:
		return {"state": "stale", "tools": []}
	var output: Array[Dictionary] = []
	var seen := {}
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			return {"state": "invalid", "tools": []}
		var id: Variant = record.get("id", "")
		var name: Variant = record.get("name", "")
		var state: Variant = record.get("state", "")
		var path: Variant = record.get("path", "")
		if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 48 or seen.has(id):
			return {"state": "invalid", "tools": []}
		for character in id:
			if not "abcdefghijklmnopqrstuvwxyz0123456789-_".contains(character):
				return {"state": "invalid", "tools": []}
		if typeof(name) != TYPE_STRING or name.strip_edges().is_empty() or name.length() > 80:
			return {"state": "invalid", "tools": []}
		if typeof(state) != TYPE_STRING or not ["source_present", "directory_seen", "not_found"].has(state):
			return {"state": "invalid", "tools": []}
		if typeof(path) != TYPE_STRING or path.length() > 500 or not path.is_absolute_path() or path.contains(".."):
			return {"state": "invalid", "tools": []}
		seen[id] = true
		output.append({
			"id": id, "name": name.strip_edges(), "status": state, "path": path,
			"source": "operator local filesystem inventory",
			"observed_at_unix": stamp
		})
	return {"state": "observed", "tools": output, "observed_at_unix": stamp}
