extends Node

## File reader for the suggestions shelf (data/cockpit_suggestions.json).
## Same bounded-read pattern as the other readers. The stdlib generator
## (tools/cockpit/suggestions_emit.py) compiles docs/suggestions/*.md into
## the file; this room only reads it. A missing file is an empty shelf,
## labelled — the shelf never invents suggestions.

signal suggestions_changed(suggestions: Dictionary)

const PROJECTION = preload("res://scripts/holo/CockpitSuggestionsProjection.gd")
const DEFAULT_SUGGESTIONS_PATH := "res://data/cockpit_suggestions.json"
const MAX_BYTES := 262144
const POLL_SECONDS := 60.0

var suggestions_path: String = DEFAULT_SUGGESTIONS_PATH

var _last_good: Dictionary = {}
var _failure: String = "not_observed"

func _ready() -> void:
	var env_path := OS.get_environment("COCKPIT_SUGGESTIONS_PATH")
	if not env_path.is_empty():
		suggestions_path = env_path
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(read_now)
	add_child(timer)

func read_now() -> void:
	if not FileAccess.file_exists(suggestions_path):
		_mark_failure("suggestions_missing")
		return
	var f := FileAccess.open(suggestions_path, FileAccess.READ)
	if f == null:
		_mark_failure("suggestions_unreadable")
		return
	if f.get_length() > MAX_BYTES:
		f.close()
		_mark_failure("suggestions_too_large")
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Dictionary = PROJECTION.parse_suggestions(text)
	if not parsed.get("ok", false):
		_mark_failure(String(parsed.get("reason", "invalid_suggestions")))
		return
	_last_good = parsed
	_failure = ""
	suggestions_changed.emit(current_suggestions())

func current_suggestions() -> Dictionary:
	if _last_good.is_empty():
		return {
			"state": "unknown" if _failure == "not_observed" else "unavailable",
			"error": _failure,
			"suggestions": [],
			"generated_at": "",
		}
	var view := _last_good.duplicate(true)
	view["state"] = "live"
	view["error"] = ""
	return view

func _mark_failure(reason: String) -> void:
	_failure = reason
	suggestions_changed.emit(current_suggestions())
