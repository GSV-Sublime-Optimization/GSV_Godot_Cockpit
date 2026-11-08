extends Node

## Godot-side sensory adapter to the KiloCore Studio project constellation.
## R0 / read-only: never shells out, posts tasks, reads credential stores,
## impersonates an agent, or interprets an HTTP response as write authority.
## The /api/projects scan is slow (its backend times out after 15s), so this
## bridge is CACHED: observe() is a no-op (returns false) unless the last
## fetch is older than min_refresh_msec or force is true. Never poll
## unbounded projects directly from Godot. Timeout, freshness, and refresh
## are configuration with safe defaults and bounds.

signal observation_changed(observation: Dictionary)

const PROJECTION = preload("res://scripts/entity/StudioProjectsProjection.gd")
const LOCAL_STUDIO_BASE := "http://127.0.0.1:7340"
const MAX_BODY_BYTES := 262144

@export_range(5.0, 60.0, 1.0) var http_timeout_seconds: float = 20.0:
	set(value):
		http_timeout_seconds = clampf(value, 5.0, 60.0)
@export_range(60000.0, 1800000.0, 1000.0) var freshness_msec: float = 300000.0:
	set(value):
		freshness_msec = clampf(value, 60000.0, 1800000.0)
@export_range(30000.0, 1800000.0, 1000.0) var min_refresh_msec: float = 120000.0:
	set(value):
		min_refresh_msec = clampf(value, 30000.0, 1800000.0)

var _request: HTTPRequest
var _pending: bool = false
var _last_good: Dictionary = {}
var _observed_at_ms: int = 0
var _last_fetch_ms: int = 0
var _failure: String = "not_observed"

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = http_timeout_seconds
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)

func observe(force: bool = false) -> bool:
	if _pending:
		return false
	if not force and _last_fetch_ms > 0 and Time.get_ticks_msec() - _last_fetch_ms < min_refresh_msec:
		return false
	_pending = true
	_last_fetch_ms = Time.get_ticks_msec()
	# This adapter is specifically a same-host observation. Another machine
	# needs an authenticated, Kilo_Core-owned transport, not a configurable URL.
	var result := _request.request(
		LOCAL_STUDIO_BASE + "/api/projects",
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET
	)
	if result != OK:
		_pending = false
		_mark_failure("local_request_failed")
		return false
	return true

func current_observation() -> Dictionary:
	if _last_good.is_empty():
		return {
			"state": "unknown" if _failure == "not_observed" else "unavailable",
			"source": "KiloCore-Studio/GET-api-projects",
			"error": _failure,
			"observed_at_ms": 0,
			"age_ms": -1
		}
	var view := _last_good.duplicate(true)
	var age_ms: int = Time.get_ticks_msec() - _observed_at_ms
	view["age_ms"] = age_ms
	var expired := age_ms > freshness_msec
	if expired or not _failure.is_empty():
		view["state"] = "stale"
		view["error"] = "observation_expired" if expired and _failure.is_empty() else _failure
	return view

func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_mark_failure("studio_transport_unavailable")
		return
	if body.size() > MAX_BODY_BYTES:
		_mark_failure("projects_response_too_large")
		return
	var projection: Dictionary = PROJECTION.parse_projects(body.get_string_from_utf8())
	if not projection.get("ok", false):
		_mark_failure(String(projection.get("reason", "invalid_projects")))
		return
	var observation: Dictionary = projection["observation"]
	_observed_at_ms = Time.get_ticks_msec()
	_last_good = observation.duplicate(true)
	_last_good["observed_at_ms"] = _observed_at_ms
	_last_good["age_ms"] = 0
	_failure = ""
	observation_changed.emit(current_observation())

func _mark_failure(reason: String) -> void:
	_failure = reason
	observation_changed.emit(current_observation())
