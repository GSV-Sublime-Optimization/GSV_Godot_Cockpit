extends Node

## File reader for the CHORUS feed (feed.json) — the live-activity stream.
## Same pattern as FleetTelemetryReader: a bounded file read, never a shell,
## never HTTP from Godot. The feeder (chorus/mindview_feed.py) writes the
## file; this room only reads it, with caps + schema + age.
##
## States: unknown (never read) / unavailable (no file / unreadable /
## malformed / wrong schema) / live (served < 300 s ago) / stale (older, or
## served in the future). A stale feed still shows its last smiths entries
## with their ages — never as live.
##
## `feed_path` is a variable (default the MSI path) so tests can point it at
## a fixture, and so another rig can override it with COCKPIT_CHORUS_FEED.
## No hardcoded Windows path in the logic beyond the documented default.

signal feed_changed(feed: Dictionary)

const PROJECTION = preload("res://scripts/holo/ChorusFeedProjection.gd")
const DEFAULT_FEED_PATH := "C:/dev/active/Dev-Mentor/state/fleet/feed.json"
const MAX_BYTES := 1048576
const STALE_AFTER_MSEC := 300000.0
const POLL_SECONDS := 30.0

var feed_path: String = DEFAULT_FEED_PATH

var _last_good: Dictionary = {}
var _failure: String = "not_observed"

func _ready() -> void:
	var env_path := OS.get_environment("COCKPIT_CHORUS_FEED")
	if not env_path.is_empty():
		feed_path = env_path
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(read_now)
	add_child(timer)

func read_now() -> void:
	if not FileAccess.file_exists(feed_path):
		_mark_failure("feed_missing")
		return
	var f := FileAccess.open(feed_path, FileAccess.READ)
	if f == null:
		_mark_failure("feed_unreadable")
		return
	if f.get_length() > MAX_BYTES:
		f.close()
		_mark_failure("feed_too_large")
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Dictionary = PROJECTION.parse_feed(text)
	if not parsed.get("ok", false):
		_mark_failure(String(parsed.get("reason", "invalid_feed")))
		return
	_last_good = parsed["feed"]
	_failure = ""
	feed_changed.emit(current_feed())

func current_feed() -> Dictionary:
	if _last_good.is_empty():
		return {
			"state": "unknown" if _failure == "not_observed" else "unavailable",
			"error": _failure,
			"smiths": [],
			"prs_waiting": [],
			"doctor": [],
			"spine": {"up": 0, "total": 0, "services": []},
			"served_at": -1.0,
			"age_ms": -1,
		}
	var view := _last_good.duplicate(true)
	var served_at := float(_last_good.get("served_at", -1.0))
	if served_at < 0.0:
		view["state"] = "stale"
		view["error"] = "feed_no_served_at"
		view["age_ms"] = -1
		return view
	var age_ms := int(Time.get_unix_time_from_system() * 1000.0) - int(served_at * 1000.0)
	view["age_ms"] = age_ms
	if age_ms < 0:
		view["state"] = "stale"
		view["error"] = "feed_from_future"
	elif age_ms > int(STALE_AFTER_MSEC):
		view["state"] = "stale"
		view["error"] = "feed_stale"
	else:
		view["state"] = "live"
		view["error"] = ""
	return view

func _mark_failure(reason: String) -> void:
	_failure = reason
	feed_changed.emit(current_feed())
