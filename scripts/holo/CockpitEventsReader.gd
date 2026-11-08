extends Node

## File reader for the cockpit event tape (data/cockpit_events.json).
## Same bounded-read pattern as FleetTelemetryReader / ChorusFeedReader:
## no shell, no HTTP, no POST. The scheduled `gh` job writes the file;
## this room only reads it, with caps + schema. A missing or malformed
## file is an empty tape, labelled — never a fabricated history.
##
## `events_path` defaults to the repo data file (res://) so a staged build
## carries its tape; override with COCKPIT_EVENTS_PATH for a live checkout.

signal events_changed(events: Dictionary)

const PROJECTION = preload("res://scripts/holo/CockpitEventsProjection.gd")
const DEFAULT_EVENTS_PATH := "res://data/cockpit_events.json"
const MAX_BYTES := 262144
const POLL_SECONDS := 30.0

var events_path: String = DEFAULT_EVENTS_PATH

var _last_good: Dictionary = {}
var _failure: String = "not_observed"

func _ready() -> void:
	var env_path := OS.get_environment("COCKPIT_EVENTS_PATH")
	if not env_path.is_empty():
		events_path = env_path
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(read_now)
	add_child(timer)

func read_now() -> void:
	if not FileAccess.file_exists(events_path):
		_mark_failure("events_missing")
		return
	var f := FileAccess.open(events_path, FileAccess.READ)
	if f == null:
		_mark_failure("events_unreadable")
		return
	if f.get_length() > MAX_BYTES:
		f.close()
		_mark_failure("events_too_large")
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Dictionary = PROJECTION.parse_events(text)
	if not parsed.get("ok", false):
		_mark_failure(String(parsed.get("reason", "invalid_events")))
		return
	_last_good = parsed
	_failure = ""
	events_changed.emit(current_events())

func current_events() -> Dictionary:
	if _last_good.is_empty():
		return {
			"state": "unknown" if _failure == "not_observed" else "unavailable",
			"error": _failure,
			"events": [],
			"generated_at": "",
		}
	var view := _last_good.duplicate(true)
	view["state"] = "live"
	view["error"] = ""
	return view

func _mark_failure(reason: String) -> void:
	_failure = reason
	events_changed.emit(current_events())
