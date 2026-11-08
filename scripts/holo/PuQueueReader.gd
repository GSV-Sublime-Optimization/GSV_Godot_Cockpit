extends Node

## File reader for the Unified PU Queue (NuSyQ-Hub data file). Same bounded
## pattern as the other readers: no shell, no HTTP. The file's mtime is the
## staleness evidence — the reader passes the age (hours) to the projection,
## which labels the rail STALE when the file is older than 7 days.
##
## `queue_path` defaults to the MSI Hub checkout; override with
## COCKPIT_PU_QUEUE_PATH. The :5002 queue API has no listener (verified
## 2026-11-08), so there is no live fallback — the file IS the source, and
## its age is shown on the rail header.

signal queue_changed(queue: Dictionary)

const PROJECTION = preload("res://scripts/holo/PuQueueProjection.gd")
const DEFAULT_QUEUE_PATH := "C:/dev/active/NuSyQ-Hub/data/unified_pu_queue.json"
const MAX_BYTES := 1048576
const STALE_AFTER_DAYS := 7.0
const POLL_SECONDS := 60.0

var queue_path: String = DEFAULT_QUEUE_PATH

var _last_good: Dictionary = {}
var _failure: String = "not_observed"

func _ready() -> void:
	var env_path := OS.get_environment("COCKPIT_PU_QUEUE_PATH")
	if not env_path.is_empty():
		queue_path = env_path
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(read_now)
	add_child(timer)

func read_now() -> void:
	if not FileAccess.file_exists(queue_path):
		_mark_failure("pu_queue_missing")
		return
	var f := FileAccess.open(queue_path, FileAccess.READ)
	if f == null:
		_mark_failure("pu_queue_unreadable")
		return
	if f.get_length() > MAX_BYTES:
		f.close()
		_mark_failure("pu_queue_too_large")
		return
	var text := f.get_as_text()
	f.close()
	var age_hours := -1.0
	var mtime := FileAccess.get_modified_time(queue_path)
	if mtime > 0:
		age_hours = (Time.get_unix_time_from_system() - float(mtime)) / 3600.0
	var parsed: Dictionary = PROJECTION.parse_queue(text, age_hours)
	if not parsed.get("ok", false):
		_mark_failure(String(parsed.get("reason", "invalid_pu_queue")))
		return
	_last_good = parsed["queue"]
	_failure = ""
	queue_changed.emit(current_queue())

func current_queue() -> Dictionary:
	if _last_good.is_empty():
		return {
			"state": "unknown" if _failure == "not_observed" else "unavailable",
			"error": _failure,
			"counts": {},
			"total": 0,
			"items": [],
			"file_age": "unknown",
			"stale": false,
			"api_down": true,
		}
	var view := _last_good.duplicate(true)
	view["state"] = "stale" if bool(view.get("stale", false)) else "live"
	view["error"] = ""
	return view

func _mark_failure(reason: String) -> void:
	_failure = reason
	queue_changed.emit(current_queue())
