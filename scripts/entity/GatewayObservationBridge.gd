extends Node

## Godot-side sensory adapter to the KiloCore Colony Gateway (routing layer).
## R0 / read-only: never shells out, posts tasks, reads credential stores,
## impersonates an agent, or interprets an HTTP response as write authority.
## One asynchronous, explicit GET to http://127.0.0.1:8001/health; no POST,
## no arbitrary URL input, no redirect following. Timeout and freshness are
## configuration with safe defaults and bounds.

signal observation_changed(observation: Dictionary)

const PROJECTION = preload("res://scripts/entity/GatewayHealthProjection.gd")
const LOCAL_GATEWAY_BASE := "http://127.0.0.1:8001"
const MAX_BODY_BYTES := 8192

@export_range(1.0, 30.0, 0.5) var http_timeout_seconds: float = 4.0:
	set(value):
		http_timeout_seconds = clampf(value, 1.0, 30.0)
@export_range(5000.0, 300000.0, 1000.0) var freshness_msec: float = 15000.0:
	set(value):
		freshness_msec = clampf(value, 5000.0, 300000.0)

var _request: HTTPRequest
var _pending: bool = false
var _last_good: Dictionary = {}
var _observed_at_ms: int = 0
var _failure: String = "not_observed"

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = http_timeout_seconds
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)

func observe() -> bool:
	if _pending:
		return false
	_pending = true
	# This adapter is specifically a same-host observation. Another machine
	# needs an authenticated, Kilo_Core-owned transport, not a configurable URL.
	var result := _request.request(
		LOCAL_GATEWAY_BASE + "/health",
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
			"source": "KiloCore-Gateway/GET-health",
			"error": _failure,
			"observed_at_ms": 0
		}
	var view := _last_good.duplicate(true)
	var expired := Time.get_ticks_msec() - _observed_at_ms > freshness_msec
	if expired or not _failure.is_empty():
		view["state"] = "stale"
		view["error"] = "observation_expired" if expired and _failure.is_empty() else _failure
	return view

func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_mark_failure("gateway_transport_unavailable")
		return
	if body.size() > MAX_BODY_BYTES:
		_mark_failure("gateway_response_too_large")
		return
	var projection: Dictionary = PROJECTION.parse_health(body.get_string_from_utf8())
	if not projection.get("ok", false):
		_mark_failure(String(projection.get("reason", "invalid_gateway_health")))
		return
	_observed_at_ms = Time.get_ticks_msec()
	_last_good = projection["observation"].duplicate(true)
	_last_good["observed_at_ms"] = _observed_at_ms
	_failure = ""
	observation_changed.emit(current_observation())

func _mark_failure(reason: String) -> void:
	_failure = reason
	observation_changed.emit(current_observation())
