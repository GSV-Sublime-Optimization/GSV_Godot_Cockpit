extends Node

## File reader for the fleet telemetry snapshot
## (C:\GSV\state\fleet-telemetry.json, written by fleet_feed.ps1).
##
## The cockpit runs NO shell: this is a bounded file read with a schema-pinned
## parser (FleetTelemetryProjection) and an age check — the same pattern as
## Mind View's mind_feed.py. States: unknown (never read) / unavailable (no
## file / unreadable / malformed / wrong schema) / live (fresh, age < 300 s) /
## stale (age >= 300 s, or generated in the future). The probe refreshes every
## 5 min, so a live snapshot is at most ~5 min old; anything older is stale,
## never silently trusted.
##
## `snapshot_path` is a variable (default the MSI path) so tests can point it
## at a fixture file without touching the real snapshot.

signal telemetry_changed(telemetry: Dictionary)

const PROJECTION = preload("res://scripts/holo/FleetTelemetryProjection.gd")
const DEFAULT_SNAPSHOT_PATH := "C:/GSV/state/fleet-telemetry.json"
const MAX_BYTES := 65536
const STALE_AFTER_MSEC := 300000.0
const POLL_SECONDS := 30.0

var snapshot_path: String = DEFAULT_SNAPSHOT_PATH

var _last_good: Dictionary = {}
var _failure: String = "not_observed"

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(read_now)
	add_child(timer)

func read_now() -> void:
	if not FileAccess.file_exists(snapshot_path):
		_mark_failure("snapshot_missing")
		return
	var f := FileAccess.open(snapshot_path, FileAccess.READ)
	if f == null:
		_mark_failure("snapshot_unreadable")
		return
	if f.get_length() > MAX_BYTES:
		f.close()
		_mark_failure("telemetry_response_too_large")
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Dictionary = PROJECTION.parse_telemetry(text)
	if not parsed.get("ok", false):
		_mark_failure(String(parsed.get("reason", "invalid_telemetry")))
		return
	_last_good = parsed["telemetry"]
	_failure = ""
	telemetry_changed.emit(current_telemetry())

func current_telemetry() -> Dictionary:
	if _last_good.is_empty():
		return {
			"state": "unknown" if _failure == "not_observed" else "unavailable",
			"error": _failure,
			"rigs": {},
			"age_ms": -1,
		}
	var view := _last_good.duplicate(true)
	var age_ms := int(Time.get_unix_time_from_system() * 1000.0) - int(_last_good.get("generated_unix_ms", 0))
	view["age_ms"] = age_ms
	if age_ms < 0:
		view["state"] = "stale"
		view["error"] = "telemetry_from_future"
	elif age_ms > int(STALE_AFTER_MSEC):
		view["state"] = "stale"
		view["error"] = "telemetry_stale"
	else:
		view["state"] = "live"
		view["error"] = ""
	return view

func _mark_failure(reason: String) -> void:
	_failure = reason
	telemetry_changed.emit(current_telemetry())
