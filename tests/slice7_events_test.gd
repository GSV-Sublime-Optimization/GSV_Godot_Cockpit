extends SceneTree

## Slice 7 event-tape tests: the schema-pinned cockpit_events.json parser
## and reader (the room's 4th dimension — review landed, PR merged, PR
## opened — from observed feeds, never a timer).
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/slice7_events_test.gd
##
## Exit 0 = pass, 1 = fail.
## Also run by tests/godot_smoke_gate.py as the "slice7-events" case.

const PROJECTION = preload("res://scripts/holo/CockpitEventsProjection.gd")
const READER = preload("res://scripts/holo/CockpitEventsReader.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_valid_tape()
	_check_unknown_kind_rejected()
	_check_wrong_schema_rejected()
	_check_cap_eighty()
	await _check_reader_and_real_file()
	_finish()


func _good_tape_json() -> String:
	return """{
		"schema": "cockpit.events/v1",
		"generated_at": "2026-11-08T10:40:00Z",
		"generated_by": "tools/cockpit/events_emit.py",
		"events": [
			{"at": "2026-11-08T08:33:54Z", "kind": "pr_merged", "repo": "GSV_Godot_Cockpit", "number": 22, "title": "contrib(chorus): POST origin guard", "url": "https://github.com/GSV-Sublime-Optimization/GSV_Godot_Cockpit/pull/22", "actor": "KiloMusician", "verdict": ""},
			{"at": "2026-11-08T08:30:20Z", "kind": "pr_opened", "repo": "GSV_Godot_Cockpit", "number": 21, "title": "contrib(muse entry): three fixes from running it on the i3", "url": "https://github.com/GSV-Sublime-Optimization/GSV_Godot_Cockpit/pull/21", "actor": "KiloMusician", "verdict": ""}
		]
	}"""


func _check_valid_tape() -> void:
	var parsed := PROJECTION.parse_events(_good_tape_json())
	if not bool(parsed.get("ok", false)):
		_fail("valid tape rejected: %s" % String(parsed.get("reason", "?")))
		return
	var events: Array = parsed["events"]
	if events.size() != 2:
		_fail("tape parsed %d events, expected 2" % events.size())
	elif String(events[0].get("kind", "")) != "pr_merged":
		_fail("first event kind is %s, expected pr_merged" % String(events[0].get("kind", "")))


func _check_unknown_kind_rejected() -> void:
	var text := _good_tape_json().replace("pr_merged", "pr_vanished")
	if bool(PROJECTION.parse_events(text).get("ok", false)):
		_fail("unknown event kind pr_vanished accepted — never map down to routine")
	elif String(PROJECTION.parse_events(text).get("reason", "")) != "unknown_event_kind":
		_fail("unknown kind rejected with the wrong reason")


func _check_wrong_schema_rejected() -> void:
	var text := _good_tape_json().replace("cockpit.events/v1", "cockpit.events/v9")
	if bool(PROJECTION.parse_events(text).get("ok", false)):
		_fail("wrong events schema accepted")


func _check_cap_eighty() -> void:
	var parts: PackedStringArray = []
	for i in 90:
		parts.append('{"at": "2026-11-08T08:33:54Z", "kind": "pr_opened", "repo": "GSV_Godot_Cockpit", "number": %d, "title": "t", "url": "https://example.invalid/x", "actor": "KiloMusician", "verdict": ""}' % i)
	var text := '{"schema": "cockpit.events/v1", "events": [%s]}' % ", ".join(parts)
	var parsed := PROJECTION.parse_events(text)
	if not bool(parsed.get("ok", false)):
		_fail("90-event tape rejected instead of capped: %s" % String(parsed.get("reason", "?")))
	elif (parsed["events"] as Array).size() != 80:
		_fail("tape capped at %d, expected 80" % (parsed["events"] as Array).size())


func _check_reader_and_real_file() -> void:
	# The reader on a fixture file.
	var path := "user://slice7-test-events.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(_good_tape_json())
	f.close()
	var reader := READER.new()
	reader.events_path = path
	root.add_child(reader)
	reader.read_now()
	var events := reader.current_events()
	if String(events.get("state", "")) != "live":
		_fail("fixture events read '%s', expected 'live'" % String(events.get("state", "")))
	if (events["events"] as Array).size() != 2:
		_fail("reader lost events")
	reader.queue_free()
	await process_frame
	# The real shipped file must parse and carry the seed events (written by
	# tools/cockpit/events_emit.py on the MSI before filing).
	var real := READER.new()
	root.add_child(real)
	real.read_now()
	var real_events := real.current_events()
	if String(real_events.get("state", "")) != "live":
		_fail("shipped data/cockpit_events.json reads '%s' (%s)" % [String(real_events.get("state", "")), String(real_events.get("error", ""))])
	elif (real_events["events"] as Array).is_empty():
		_fail("shipped data/cockpit_events.json has no events")
	real.queue_free()
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
