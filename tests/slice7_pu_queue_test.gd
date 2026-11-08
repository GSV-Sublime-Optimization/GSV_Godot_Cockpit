extends SceneTree

## Slice 7 PU queue tests: the schema-pinned unified_pu_queue.json parser
## and reader. The queue is real but stale (file last written 2026-09-16,
## :5002 API down) — the parser reports counts and the file age it is
## handed, and the room renders the STALE header from it.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/slice7_pu_queue_test.gd
##
## Exit 0 = pass, 1 = fail.
## Also run by tests/godot_smoke_gate.py as the "slice7-pu" case.

const PROJECTION = preload("res://scripts/holo/PuQueueProjection.gd")
const READER = preload("res://scripts/holo/PuQueueReader.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_counts()
	_check_unknown_status_rejected()
	_check_stale_flag()
	_check_missing_file()
	_finish()


func _queue_json() -> String:
	return """[
		{"id": "PU-1", "title": "Fix ValueError", "status": "approved", "source_repo": "NuSyQ-Hub", "priority": "medium", "type": "BugFixPU"},
		{"id": "PU-2", "title": "Add test", "status": "approved", "source_repo": "NuSyQ-Hub", "priority": "low", "type": "TestPU"},
		{"id": "PU-3", "title": "Broken proof", "status": "failed", "source_repo": "SimulatedVerse", "priority": "high", "type": "BugFixPU"},
		{"id": "PU-4", "title": "Running job", "status": "executing", "source_repo": "NuSyQ-Hub", "priority": "medium", "type": "FeaturePU"}
	]"""


func _check_counts() -> void:
	var parsed := PROJECTION.parse_queue(_queue_json(), 1254.0)
	if not bool(parsed.get("ok", false)):
		_fail("valid queue rejected: %s" % String(parsed.get("reason", "?")))
		return
	var queue: Dictionary = parsed["queue"]
	var counts: Dictionary = queue.get("counts", {})
	if int(counts.get("approved", -1)) != 2:
		_fail("approved count is %s, expected 2" % str(counts.get("approved", "?")))
	if int(counts.get("failed", -1)) != 1:
		_fail("failed count is %s, expected 1" % str(counts.get("failed", "?")))
	if int(counts.get("executing", -1)) != 1:
		_fail("executing count is %s, expected 1" % str(counts.get("executing", "?")))
	if int(queue.get("total", -1)) != 4:
		_fail("total is %s, expected 4" % str(queue.get("total", "?")))
	if String(queue.get("file_age", "")) != "52 d old":
		_fail("file age reads '%s', expected '52 d old'" % String(queue.get("file_age", "")))


func _check_unknown_status_rejected() -> void:
	var text := _queue_json().replace('"failed"', '"limbo"')
	if bool(PROJECTION.parse_queue(text, 1.0).get("ok", false)):
		_fail("unknown PU status limbo accepted — never map to a calm state")
	elif String(PROJECTION.parse_queue(text, 1.0).get("reason", "")) != "unknown_pu_status":
		_fail("unknown status rejected with the wrong reason")


func _check_stale_flag() -> void:
	var old := PROJECTION.parse_queue(_queue_json(), 200.0)
	if not bool(old.get("ok", false)):
		_fail("old queue rejected")
	elif not bool((old["queue"] as Dictionary).get("stale", false)):
		_fail("200 h old queue not flagged stale")
	var fresh := PROJECTION.parse_queue(_queue_json(), 1.0)
	if not bool(fresh.get("ok", false)):
		_fail("fresh queue rejected")
	elif bool((fresh["queue"] as Dictionary).get("stale", true)):
		_fail("1 h old queue flagged stale")
	if not bool((old["queue"] as Dictionary).get("api_down", false)):
		_fail("queue does not record api_down=true")


func _check_missing_file() -> void:
	var reader := READER.new()
	reader.queue_path = "user://slice7-no-such-pu.json"
	root.add_child(reader)
	reader.read_now()
	if String(reader.current_queue().get("state", "")) != "unavailable":
		_fail("missing PU file reads '%s', expected 'unavailable'" % String(reader.current_queue().get("state", "")))
	reader.queue_free()


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
