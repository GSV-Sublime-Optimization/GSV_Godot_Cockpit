extends SceneTree

## Slice 7 suggestions tests: the schema-pinned cockpit_suggestions.json
## parser and reader (design §6: repo-native suggestion files compiled by
## a stdlib generator into the JSON the room renders as the shelf).
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/slice7_suggestions_test.gd
##
## Exit 0 = pass, 1 = fail.
## Also run by tests/godot_smoke_gate.py as the "slice7-suggestions" case.

const PROJECTION = preload("res://scripts/holo/CockpitSuggestionsProjection.gd")
const READER = preload("res://scripts/holo/CockpitSuggestionsReader.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_valid_shelf()
	_check_unknown_values_rejected()
	_check_wrong_schema_rejected()
	await _check_real_file()
	_finish()


func _good_shelf_json() -> String:
	return """{
		"schema": "cockpit.suggestions/v1",
		"generated_at": "2026-11-08T10:40:00Z",
		"suggestions": [
			{"file": "20261108-slice7-alive-room.md", "title": "Slice 7 — boot into the living room", "author": "Muse (agent/muse)", "kind": "improvement", "target": "room", "status": "open", "reason": "", "link_pr": "", "evidence": "https://github.com/GSV-Sublime-Optimization/GSV_Godot_Cockpit/pull/19"}
		]
	}"""


func _check_valid_shelf() -> void:
	var parsed := PROJECTION.parse_suggestions(_good_shelf_json())
	if not bool(parsed.get("ok", false)):
		_fail("valid shelf rejected: %s" % String(parsed.get("reason", "?")))
		return
	var items: Array = parsed["suggestions"]
	if items.size() != 1:
		_fail("shelf parsed %d suggestions, expected 1" % items.size())
	elif String(items[0].get("status", "")) != "open":
		_fail("seed suggestion status is %s, expected open" % String(items[0].get("status", "")))


func _check_unknown_values_rejected() -> void:
	var bad_kind := _good_shelf_json().replace('"improvement"', '"wish"')
	if bool(PROJECTION.parse_suggestions(bad_kind).get("ok", false)):
		_fail("unknown suggestion kind wish accepted")
	var bad_status := _good_shelf_json().replace('"open"', '"maybe"')
	if bool(PROJECTION.parse_suggestions(bad_status).get("ok", false)):
		_fail("unknown suggestion status maybe accepted")
	var bad_target := _good_shelf_json().replace('"room"', '"everywhere"')
	if bool(PROJECTION.parse_suggestions(bad_target).get("ok", false)):
		_fail("unknown suggestion target everywhere accepted")


func _check_wrong_schema_rejected() -> void:
	var text := _good_shelf_json().replace("cockpit.suggestions/v1", "cockpit.suggestions/v9")
	if bool(PROJECTION.parse_suggestions(text).get("ok", false)):
		_fail("wrong suggestions schema accepted")


func _check_real_file() -> void:
	# The real shipped file must parse and carry the seed suggestion (written
	# by tools/cockpit/suggestions_emit.py on the MSI before filing).
	var reader := READER.new()
	root.add_child(reader)
	reader.read_now()
	var shelf := reader.current_suggestions()
	if String(shelf.get("state", "")) != "live":
		_fail("shipped data/cockpit_suggestions.json reads '%s' (%s)" % [String(shelf.get("state", "")), String(shelf.get("error", ""))])
		reader.queue_free()
		return
	var items: Array = shelf["suggestions"]
	var found := false
	for item in items:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("file", "")) == "20261108-slice7-alive-room.md":
			found = true
	if not found:
		_fail("seed suggestion 20261108-slice7-alive-room.md missing from the shipped file")
	reader.queue_free()
	await process_frame


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[slice7-test] PASS")
		quit(0)
		return
	for message in _failures:
		printerr("[slice7-test] FAIL: %s" % message)
	print("[slice7-test] FAILED (%d)" % _failures.size())
	quit(1)
