extends SceneTree

## Ledger feed contract test — the #8 pattern (SceneTree script, exit 0/1).
## Exercises the real shared fixture files, never a copy, plus fail-closed
## rejections of tampered input.
##
## Run (queued — see docs/mindview-muse/VERIFICATION.md):
##   godot --headless --path . --script res://tests/ledger_feed_test.gd

const FEED = preload("res://tools/mindview_ledger/LedgerFeed.gd")
const DIR := "res://tests/fixtures/mindview-20261108"
var failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var feed: Dictionary = FEED.load_fixture_dir(DIR)
	_check(feed.get("ok", false), "shared fixture directory loads: " + String(feed.get("reason", "")))
	if not feed.get("ok", false):
		_finish()
		return
	_check(String(feed.get("schema", "")) == FEED.SCHEMA, "normalised to colony.mindview-feed/v0")
	_check(String(feed.get("provenance", "")) == FEED.FREEZE_LABEL, "freeze provenance attached")
	var events: Array = feed.get("events", [])
	_check(events.size() == 4, "exactly 4 events in the shared fixture")
	var minds := {}
	var models := {}
	var routine := 0
	for e in events:
		minds[String(e.get("mind", ""))] = true
		models[String(e.get("model", ""))] = true
		if String(e.get("level", "")) == "routine":
			routine += 1
	_check(minds.size() == 1 and minds.has("l9-triage-drone"), "one mind: l9-triage-drone")
	_check(models.size() == 1 and models.has("qwen3:4b-l9fast"), "one model: qwen3:4b-l9fast")
	_check(routine == 0, "zero routine events — the calm state never occurs in the fixture")
	var rows := FEED.recurrence_rows(events)
	_check(rows.size() == 2, "two distinct lines recur")
	_check(int(rows[0]["count"]) == 4 and int(rows[0]["span_min"]) == 61, "headline recurrence: 4x in 61 min")
	_check(String(rows[0]["line"]) == "i3 failing: docker", "headline line is 'i3 failing: docker'")
	var beats: Dictionary = feed.get("heartbeats", {})
	_check(beats.size() == 3, "three heartbeats present")
	_check(bool(beats["msi"].get("green", false)), "MSI heartbeat green")
	_check(not bool(beats["i3"].get("green", true)), "i3 heartbeat green:false")
	_check(bool(beats["l9"].get("green", false)), "L9 heartbeat green (via observer msi)")
	_check((feed.get("missing", []) as Array).has("xanadu"), "xanadu heartbeat recorded missing, never faked")
	_check(is_equal_approx(float(beats["msi"]["disks"]["C"]["pct_free"]), 8.5), "MSI C: 8.5% free")
	_check(is_equal_approx(float(beats["i3"]["disks"]["C"]["pct_free"]), 9.5), "i3 C: 9.5% free")
	var items := FEED.needs_you_items(feed)
	_check(items.size() == 3, "three needs-you items, all fixture-derived")
	_check(String(items[0].get("key", "")) == "i3-docker", "first item is the i3 docker failure")
	_check(String(items[1].get("key", "")) == "disk-pressure", "second item is the disk pressure no entry surfaces")
	_check(String(items[2].get("key", "")) == "backup-claim", "third item is the backup claim")
	_check(String(items[2].get("status", "")) == "unverified", "backup claim carried as UNVERIFIED, never as fact")
	var outcomes := FEED.outcome_rows(feed)
	_check(outcomes.size() == 2, "two outcome rows")
	_check(String(outcomes[0].get("state", "")) == "aged", "05:35 MSI alarm aged out by the 06:45 green heartbeat")
	_check(String(outcomes[1].get("state", "")) == "unresolved", "i3 docker still unresolved at the 06:46 heartbeat")
	var states := FEED.unexercised_states(feed)
	_check(states.size() == 4, "four unexercised states listed, none faked")
	# Fail-closed: tampered input is rejected, not rendered.
	var text := FileAccess.get_file_as_string(DIR + "/events.jsonl")
	_check(not FEED.parse_events_text("{bad").get("ok", false), "bad JSON line rejected")
	_check(not FEED.parse_events_text(text.replace("\"alarm\"", "\"meltdown\"")).get("ok", false), "unknown level rejected")
	_check(not FEED.parse_events_text(text.replace("\"i3\"", "\"rig-9\"")).get("ok", false), "unknown focus rig rejected")
	_check(not FEED.parse_events_text("x".repeat(FEED.MAX_BYTES + 1)).get("ok", false), "oversize events rejected before parsing")
	var msi_text := FileAccess.get_file_as_string(DIR + "/heartbeat_msi.json")
	_check(not FEED.parse_heartbeat_text(msi_text, "i3").get("ok", false), "heartbeat rig mismatch rejected")
	_check(not FEED.parse_heartbeat_text(msi_text.replace("colony.heartbeat/v1", "colony.heartbeat/v9"), "msi").get("ok", false), "unknown heartbeat schema rejected")
	_check(not FEED.load_fixture_dir("res://tests/fixtures/does-not-exist").get("ok", false), "missing fixture directory fails closed")
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("LEDGER_FEED_PASS")
		quit(0)
	else:
		for reason in failures:
			printerr("LEDGER_FEED_FAIL: " + reason)
		quit(1)


func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
