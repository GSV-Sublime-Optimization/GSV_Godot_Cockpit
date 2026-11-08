extends RefCounted

## Schema-pinned parser for the cockpit event tape (data/cockpit_events.json).
## The tape is the room's 4th dimension: what just happened (review landed,
## PR merged, PR opened, check failed/passed, mission transitioned) — from
## observed feeds, never a timer. One zero-token scheduled `gh` job writes
## the file (tools/cockpit/events_emit.py, 5 min); the room and every agent
## read it. A failed fetch writes nothing (Loom collector rule: no fake
## green file).
##
## Schema: {"schema": "cockpit.events/v1", "generated_at": "<ISO>",
## "generated_by": "<job>", "events": [...]}. At most 80 events (Loom's
## tape cap); each event carries at / kind / repo / number / title / url /
## actor, plus verdict for review_submitted. Unknown kinds are rejected —
## never mapped down to routine.

const EXPECTED_SCHEMA := "cockpit.events/v1"
const MAX_BYTES := 262144
const MAX_EVENTS := 80
const MAX_TITLE := 200
const MAX_URL := 300
const MAX_NAME := 80
const KINDS: PackedStringArray = [
	"pr_opened", "pr_merged", "review_submitted",
	"check_failed", "check_passed", "mission_transitioned",
]

static func parse_events(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BYTES:
		return _invalid("events_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	if String(body.get("schema", "")) != EXPECTED_SCHEMA:
		return _invalid("unknown_events_schema")
	var raw: Variant = body.get("events", null)
	if typeof(raw) != TYPE_ARRAY:
		return _invalid("missing_events")
	var items: Array = []
	for entry in raw:
		if items.size() >= MAX_EVENTS:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			return _invalid("invalid_event")
		var kind := _bounded_string(entry.get("kind", null), MAX_NAME)
		if not KINDS.has(kind):
			return _invalid("unknown_event_kind")
		var repo := _bounded_string(entry.get("repo", null), MAX_NAME)
		var title := _bounded_string(entry.get("title", null), MAX_TITLE)
		var url := _bounded_string(entry.get("url", null), MAX_URL)
		var actor := _bounded_string(entry.get("actor", null), MAX_NAME)
		if repo.is_empty() or title.is_empty() or url.is_empty() or actor.is_empty():
			return _invalid("invalid_event")
		var number: Variant = entry.get("number", null)
		if typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT:
			return _invalid("invalid_event")
		items.append({
			"at": _bounded_string(entry.get("at", ""), MAX_NAME),
			"kind": kind,
			"repo": repo,
			"number": int(number),
			"title": title,
			"url": url,
			"actor": actor,
			"verdict": _bounded_string(entry.get("verdict", ""), MAX_NAME),
		})
	return {
		"ok": true,
		"events": items,
		"generated_at": _bounded_string(body.get("generated_at", ""), MAX_NAME),
	}


static func _bounded_string(value: Variant, max_len: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	if value.length() > max_len:
		return ""
	return value


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
