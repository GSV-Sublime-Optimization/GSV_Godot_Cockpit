extends SceneTree

## Slice 7 CHORUS feed tests: the schema-pinned feed.json parser and the
## file reader (smiths live activity / prs_waiting / doctor / spine).
## Negative controls on malformed input + an opt-in live canary that accepts
## live OR honest unavailable, never fabricated live.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/slice7_chorus_feed_test.gd
##
## Exit 0 = pass, 1 = fail. The live canary runs only with GSV_CHORUS_LIVE=1.
## Also run by tests/godot_smoke_gate.py as the "slice7-chorus" case.

const PROJECTION = preload("res://scripts/holo/ChorusFeedProjection.gd")
const READER = preload("res://scripts/holo/ChorusFeedReader.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_valid_feed()
	_check_missing_arrays_are_empty()
	_check_malformed_rejected()
	_check_oversized_doing_rejected()
	_check_unknown_types_rejected()
	await _check_reader_states()
	if OS.get_environment("GSV_CHORUS_LIVE") == "1":
		await _check_live_canary()
	_finish()


func _good_feed_json() -> String:
	# served_at is deliberately ancient (2023): the fixture is always stale
	# by the time any test reads it — the reader must say stale, never live.
	return """{
		"served_at": 1700000000.0,
		"smiths": [
			{"name": "MSI Claude", "doing": "Reviewing FleetBridge#49", "t": 1794133961.0, "at": "2026-11-08T10:32:41Z", "station": "hearth", "rig": "msi"}
		],
		"prs_waiting": [
			{"repo": "dev", "number": 430, "title": "fix(gsv): PowerShell parse gate", "url": "https://github.com/GSV-Sublime-Optimization/dev/pull/430", "created": "2026-11-08T10:19:49Z"}
		],
		"doctor": [
			{"key": "i3:docker", "at": "2026-11-08T10:33:29Z", "verdict": "confirmed: VT-x is off in the i3's BIOS", "evidence": ["i3 says: vtx=False"]}
		],
		"spine": {"up": 16, "total": 18, "services": [
			{"name": "chatdev", "tier": "agent", "up": true, "ms": 12},
			{"name": "mempalace-api", "tier": "memory", "up": false, "ms": 13}
		]}
	}"""


func _check_valid_feed() -> void:
	var parsed := PROJECTION.parse_feed(_good_feed_json())
	if not bool(parsed.get("ok", false)):
		_fail("valid feed rejected: %s" % String(parsed.get("reason", "?")))
		return
	var feed: Dictionary = parsed["feed"]
	var smiths: Array = feed["smiths"]
	if smiths.size() != 1 or String(smiths[0].get("name", "")) != "MSI Claude":
		_fail("smiths did not parse: %s" % str(smiths))
	var spine: Dictionary = feed["spine"]
	if int(spine.get("up", -1)) != 1 or int(spine.get("total", -1)) != 2:
		_fail("spine counts wrong: %s" % str(spine))
	if (feed["prs_waiting"] as Array).size() != 1 or (feed["doctor"] as Array).size() != 1:
		_fail("prs_waiting/doctor did not parse")


func _check_missing_arrays_are_empty() -> void:
	var parsed := PROJECTION.parse_feed("""{"served_at": 1794134096.4}""")
	if not bool(parsed.get("ok", false)):
		_fail("feed without optional arrays rejected: %s" % String(parsed.get("reason", "?")))
		return
	var feed: Dictionary = parsed["feed"]
	if not (feed["smiths"] as Array).is_empty():
		_fail("missing smiths did not default to empty")


func _check_malformed_rejected() -> void:
	if bool(PROJECTION.parse_feed("{not json").get("ok", false)):
		_fail("malformed JSON accepted")
	if bool(PROJECTION.parse_feed("[1, 2]").get("ok", false)):
		_fail("non-dictionary feed accepted")
	if bool(PROJECTION.parse_feed("""{"smiths": "nope"}""").get("ok", false)):
		_fail("string smiths accepted")


func _check_oversized_doing_rejected() -> void:
	var long_doing := ""
	for i in 200:
		long_doing += "x"
	var text := '{"smiths": [{"name": "MSI Claude", "doing": "%s", "t": 1.0}]}' % long_doing
	if bool(PROJECTION.parse_feed(text).get("ok", false)):
		_fail("oversized smiths doing (>160 chars) accepted")


func _check_unknown_types_rejected() -> void:
	var text := '{"smiths": [{"name": "MSI Claude", "doing": "x", "t": "soon"}]}'
	if bool(PROJECTION.parse_feed(text).get("ok", false)):
		_fail("string smiths timestamp accepted")
	text = '{"spine": {"services": [{"name": "chatdev", "up": "yes"}]}}'
	if bool(PROJECTION.parse_feed(text).get("ok", false)):
		_fail("string spine up flag accepted")


func _check_reader_states() -> void:
	var path := "user://slice7-test-feed.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(_good_feed_json())
	f.close()
	var reader := READER.new()
	reader.feed_path = path
	root.add_child(reader)
	reader.read_now()
	# served_at is ancient in the fixture — the reader must say stale, never
	# live. That IS the honest state.
	var feed := reader.current_feed()
	if String(feed.get("state", "")) != "stale":
		_fail("old fixture feed reads '%s', expected 'stale'" % String(feed.get("state", "")))
	if (feed["smiths"] as Array).size() != 1:
		_fail("reader lost the smiths entries")
	reader.queue_free()
	await process_frame
	# Missing file -> unavailable, not unknown-live.
	var missing := READER.new()
	missing.feed_path = "user://slice7-no-such-feed.json"
	root.add_child(missing)
	missing.read_now()
	if String(missing.current_feed().get("state", "")) != "unavailable":
		_fail("missing feed reads '%s', expected 'unavailable'" % String(missing.current_feed().get("state", "")))
	missing.queue_free()
	await process_frame


func _check_live_canary() -> void:
	var reader := READER.new()
	root.add_child(reader)
	reader.read_now()
	var feed := reader.current_feed()
	print("[slice7-test] live canary: chorus feed state = %s" % String(feed.get("state", "")))
	if String(feed.get("state", "")) != "live" and String(feed.get("state", "")) != "stale" and String(feed.get("state", "")) != "unavailable":
		_fail("live canary: chorus feed state stayed '%s'" % String(feed.get("state", "")))
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
