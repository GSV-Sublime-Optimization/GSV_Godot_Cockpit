extends RefCounted

## Schema-pinned parser for the suggestions shelf file
## (data/cockpit_suggestions.json), compiled from docs/suggestions/*.md by
## the stdlib generator tools/cockpit/suggestions_emit.py (design §6).
## One file per suggestion, filename YYYYMMDD-<slug>.md; any agent submits
## by filing a PR adding one file. Lifecycle: open -> triaged -> accepted /
## declined (reason kept) -> implemented (linked PR) -> closed. Declined
## suggestions are kept with their reason, never deleted.
##
## The room accepts no typed input (read-only): the shelf renders the file,
## and its "Suggest" card shows the exact path, the template, and the PR
## route. The CHORUS live path (POST /suggest -> order at station cockpit)
## is a follow-up, not built here — one suggestion system, not two.

const EXPECTED_SCHEMA := "cockpit.suggestions/v1"
const MAX_BYTES := 262144
const MAX_SUGGESTIONS := 200
const MAX_TEXT := 200
const KINDS: PackedStringArray = ["fix", "edit", "correction", "update", "improvement"]
const STATUSES: PackedStringArray = ["open", "triaged", "accepted", "declined", "implemented", "closed"]
const TARGETS: PackedStringArray = [
	"room", "table", "seat", "web", "card", "shelf", "ledger", "tape", "rail",
	"legend", "needs", "doors", "docs", "other",
]

static func parse_suggestions(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BYTES:
		return _invalid("suggestions_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	if String(body.get("schema", "")) != EXPECTED_SCHEMA:
		return _invalid("unknown_suggestions_schema")
	var raw: Variant = body.get("suggestions", null)
	if typeof(raw) != TYPE_ARRAY:
		return _invalid("missing_suggestions")
	var items: Array = []
	for entry in raw:
		if items.size() >= MAX_SUGGESTIONS:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			return _invalid("invalid_suggestion")
		var title := _bounded_string(entry.get("title", null), MAX_TEXT)
		var author := _bounded_string(entry.get("author", null), MAX_TEXT)
		var kind := _bounded_string(entry.get("kind", null), MAX_TEXT)
		var target := _bounded_string(entry.get("target", null), MAX_TEXT)
		var status := _bounded_string(entry.get("status", null), MAX_TEXT)
		var file := _bounded_string(entry.get("file", null), MAX_TEXT)
		if title.is_empty() or author.is_empty() or file.is_empty():
			return _invalid("invalid_suggestion")
		if not KINDS.has(kind):
			return _invalid("unknown_suggestion_kind")
		if not STATUSES.has(status):
			return _invalid("unknown_suggestion_status")
		if not TARGETS.has(target):
			return _invalid("unknown_suggestion_target")
		items.append({
			"file": file,
			"title": title,
			"author": author,
			"kind": kind,
			"target": target,
			"status": status,
			"reason": _bounded_string(entry.get("reason", ""), MAX_TEXT),
			"link_pr": _bounded_string(entry.get("link_pr", ""), MAX_TEXT),
			"evidence": _bounded_string(entry.get("evidence", ""), MAX_TEXT),
		})
	return {
		"ok": true,
		"suggestions": items,
		"generated_at": _bounded_string(body.get("generated_at", ""), MAX_TEXT),
	}


static func _bounded_string(value: Variant, max_len: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	if value.length() > max_len:
		return ""
	return value


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
