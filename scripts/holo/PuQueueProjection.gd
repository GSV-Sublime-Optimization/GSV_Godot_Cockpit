extends RefCounted

## Schema-pinned parser for the Unified PU Queue file
## (NuSyQ-Hub data/unified_pu_queue.json): a top-level array of proof-gated
## work units. Statuses: queued / voting / approved / executing / completed
## / failed. Unknown statuses are rejected, never mapped to a calm state.
##
## Honesty rule (design §4.11): the queue is REAL but STALE — the file was
## last written 2026-09-16 and the :5002 API has no listener. The parser
## reports counts and the file age it is handed; the room renders the rail
## header "STALE — file <age>, API :5002 DOWN" and never animates from it.

const MAX_BYTES := 1048576
const MAX_ITEMS := 512
const MAX_TITLE := 200
const MAX_NAME := 80
const STATUSES: PackedStringArray = [
	"queued", "voting", "approved", "executing", "completed", "failed",
]

static func parse_queue(json_text: String, file_age_hours: float) -> Dictionary:
	if json_text.length() > MAX_BYTES:
		return _invalid("pu_queue_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		return _invalid("malformed_json")
	var counts := {}
	for status in STATUSES:
		counts[status] = 0
	var items: Array = []
	for entry in parsed:
		if items.size() >= MAX_ITEMS:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			return _invalid("invalid_pu_entry")
		var status := _bounded_string(entry.get("status", null), MAX_NAME)
		if not STATUSES.has(status):
			return _invalid("unknown_pu_status")
		counts[status] = int(counts[status]) + 1
		items.append({
			"id": _bounded_string(entry.get("id", ""), MAX_NAME),
			"title": _bounded_string(entry.get("title", ""), MAX_TITLE),
			"status": status,
			"source_repo": _bounded_string(entry.get("source_repo", ""), MAX_NAME),
			"priority": _bounded_string(entry.get("priority", ""), MAX_NAME),
			"type": _bounded_string(entry.get("type", ""), MAX_NAME),
		})
	var age_text := "unknown age"
	if file_age_hours >= 0.0:
		if file_age_hours < 1.0:
			age_text = "%d min old" % int(file_age_hours * 60.0)
		elif file_age_hours < 48.0:
			age_text = "%.1f h old" % file_age_hours
		else:
			age_text = "%d d old" % int(file_age_hours / 24.0)
	return {
		"ok": true,
		"queue": {
			"counts": counts,
			"total": items.size(),
			"items": items,
			"file_age_hours": file_age_hours,
			"file_age": age_text,
			"stale": file_age_hours >= 168.0,
			"api_down": true,
		},
	}


static func _bounded_string(value: Variant, max_len: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	if value.length() > max_len:
		return ""
	return value


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
