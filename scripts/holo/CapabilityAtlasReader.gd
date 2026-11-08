class_name CapabilityAtlasReader
extends Node

## Reader for the graded capability atlas: the static file
## (res://data/capability_atlas.json, schema kilocore.capability-atlas.v1)
## PLUS a live-state overlay from the existing fleet snapshot
## (C:\GSV\state\fleet-telemetry.json, kilocore.fleet-telemetry.v1, 5-min
## refresh). The cockpit runs NO shell and holds NO credentials: two bounded
## file reads, schema-pinned parsers, age checks — the same pattern as
## FleetTelemetryReader.
##
## Overlay rule (never fabricated live): an entry shows "live" from a probe
## ONLY when the fleet snapshot is fresh (< 300 s) AND its mapped service
## reads "up" (or its mapped process name appears in the rig's seats list).
## A "down" probe demotes the entry to "unavailable". Anything else —
## unknown, missing, stale snapshot, no mapping — keeps the entry's static
## honest state and the overlay "static_only". The reader keeps ONE last-good
## snapshot (bounded history: no accumulation, no growth across reads).
##
## States: unknown (never read) / unavailable (static file missing /
## unreadable / malformed / wrong schema) / live (static parsed + telemetry
## fresh-or-absent) / stale (static parsed + telemetry present-but-stale).
## `atlas_path` and `telemetry_path` are variables so tests can point at
## fixtures without touching the real files. No HTTP is involved here (file
## reads only), so there is no redirect surface at all — and no POST, no
## shell, no secrets, ever.

signal atlas_changed(atlas: Dictionary)

const ATLAS_PROJECTION = preload("res://scripts/holo/CapabilityAtlasProjection.gd")
const TELEMETRY_PROJECTION = preload("res://scripts/holo/FleetTelemetryProjection.gd")
const DEFAULT_ATLAS_PATH := "res://data/capability_atlas.json"
const DEFAULT_TELEMETRY_PATH := "C:/GSV/state/fleet-telemetry.json"
const MAX_ATLAS_BYTES := 131072
const MAX_TELEMETRY_BYTES := 65536
const STALE_AFTER_MSEC := 300000.0
const POLL_SECONDS := 60.0

var atlas_path: String = DEFAULT_ATLAS_PATH
var telemetry_path: String = DEFAULT_TELEMETRY_PATH

var _last_good: Dictionary = {}
var _telemetry: Dictionary = {}
var _failure: String = "not_observed"


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(read_now)
	add_child(timer)


func read_now() -> void:
	var atlas := _read_static()
	if atlas.is_empty():
		return
	_read_telemetry()
	_last_good = atlas
	_failure = ""
	atlas_changed.emit(current_atlas())


## Pure overlay: static entries + parsed telemetry -> entries with effective
## states. Static so tests can drive it without a node. `telemetry` is a
## FleetTelemetryProjection telemetry dict (or {} when none was read);
## `telemetry_fresh` gates every live claim.
static func apply_overlay(entries: Array, telemetry: Dictionary, telemetry_fresh: bool) -> Array:
	var out: Array = []
	var rigs: Dictionary = telemetry.get("rigs", {})
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = (raw_entry as Dictionary).duplicate(true)
		entry["overlay"] = "static_only"
		var mapping: Dictionary = entry.get("telemetry", {})
		if mapping.is_empty() or not telemetry_fresh:
			out.append(entry)
			continue
		var rig_id := String(mapping.get("rig", ""))
		var rig: Dictionary = rigs.get(rig_id, {})
		if rig.is_empty():
			out.append(entry)
			continue
		if mapping.has("service"):
			var services: Dictionary = rig.get("services", {})
			var probe := String(services.get(String(mapping.get("service", "")), "unknown"))
			if probe == "up":
				entry["state"] = "live"
				entry["overlay"] = "live_probe"
			elif probe == "down":
				entry["state"] = "unavailable"
				entry["overlay"] = "live_probe"
		elif mapping.has("seat"):
			var seats := String(rig.get("seats", ""))
			if _seat_present(seats, String(mapping.get("seat", ""))):
				entry["state"] = "live"
				entry["overlay"] = "live_probe"
		out.append(entry)
	return out


## Case-insensitive token match against the rig's comma-joined seats list.
## Absence proves nothing (the probe lists only a few process names), so a
## miss keeps the static state — it never demotes an entry.
static func _seat_present(seats: String, wanted: String) -> bool:
	if wanted.is_empty() or seats.is_empty():
		return false
	for token in seats.split(","):
		if token.strip_edges().to_lower() == wanted.to_lower():
			return true
	return false


func current_atlas() -> Dictionary:
	if _last_good.is_empty():
		return {
			"state": "unknown" if _failure == "not_observed" else "unavailable",
			"error": _failure,
			"entries": [],
			"generated_at": "",
			"telemetry_state": "unknown",
			"telemetry_age_ms": -1,
			"live_probe_entries": 0,
			"unverified_entries": 0,
		}
	var view := _last_good.duplicate(true)
	var telemetry_age_ms := -1
	var telemetry_state := "unknown"
	if not _telemetry.is_empty():
		telemetry_age_ms = int(Time.get_unix_time_from_system() * 1000.0) - int(_telemetry.get("generated_unix_ms", 0))
		if telemetry_age_ms < 0 or telemetry_age_ms > int(STALE_AFTER_MSEC):
			telemetry_state = "stale"
		else:
			telemetry_state = "live"
	var entries: Array = apply_overlay(
		view.get("entries", []), _telemetry, telemetry_state == "live"
	)
	view["entries"] = entries
	view["telemetry_state"] = telemetry_state
	view["telemetry_age_ms"] = telemetry_age_ms
	var live_probe := 0
	var unverified := 0
	for entry in entries:
		if String((entry as Dictionary).get("overlay", "")) == "live_probe":
			live_probe += 1
		if String((entry as Dictionary).get("grade", "")) == "D":
			unverified += 1
	view["live_probe_entries"] = live_probe
	view["unverified_entries"] = unverified
	if telemetry_state == "stale":
		view["state"] = "stale"
		view["error"] = "telemetry_stale"
	else:
		view["state"] = "live"
		view["error"] = ""
	return view


func _read_static() -> Dictionary:
	if not FileAccess.file_exists(atlas_path):
		_mark_failure("atlas_missing")
		return {}
	var f := FileAccess.open(atlas_path, FileAccess.READ)
	if f == null:
		_mark_failure("atlas_unreadable")
		return {}
	if f.get_length() > MAX_ATLAS_BYTES:
		f.close()
		_mark_failure("atlas_response_too_large")
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Dictionary = ATLAS_PROJECTION.parse_atlas(text)
	if not parsed.get("ok", false):
		_mark_failure(String(parsed.get("reason", "invalid_atlas")))
		return {}
	return parsed["atlas"]


func _read_telemetry() -> void:
	_telemetry = {}
	if not FileAccess.file_exists(telemetry_path):
		return
	var f := FileAccess.open(telemetry_path, FileAccess.READ)
	if f == null:
		return
	if f.get_length() > MAX_TELEMETRY_BYTES:
		f.close()
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Dictionary = TELEMETRY_PROJECTION.parse_telemetry(text)
	if not parsed.get("ok", false):
		return
	_telemetry = parsed["telemetry"]


func _mark_failure(reason: String) -> void:
	_failure = reason
	atlas_changed.emit(current_atlas())
