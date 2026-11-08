extends Node

## Opt-in, asynchronous Godot sensory channel for Studio's *local* R0
## fleet-body endpoint. Never calls SSH, OpenClaw, Hermes or a shell.
signal bodies_changed(bodies: Array)

const PROJECTION = preload("res://scripts/entity/FleetBodiesProjection.gd")
const MAX_BYTES := 65536
const HTTP_TIMEOUT_SECONDS := 4.0
const DEFAULT_STALE_MSEC := 15000

var _request: HTTPRequest
var _pending := false
var _observed_msec := 0
var _has_good := false
var _failure := "not_observed"
var _body_reports: Array[Dictionary] = []

func _ready() -> void:
	_body_reports = PROJECTION.unknown()
	_request = HTTPRequest.new()
	_request.timeout = HTTP_TIMEOUT_SECONDS
	add_child(_request)
	_request.request_completed.connect(_completed)

func observe() -> bool:
	if _pending:
		return false
	var port := 7340
	# Development-only override, always loopback; cannot name remote hosts.
	var override := OS.get_environment("GSV_STUDIO_ENTITY_PORT")
	if not override.is_empty() and override.is_valid_int():
		var n := int(override)
		if n >= 1 and n <= 65535:
			port = n
	_pending = true
	var status := _request.request(
		"http://127.0.0.1:%d/api/entity/bodies" % port,
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET
	)
	if status != OK:
		_pending = false
		_mark_failure("local_request_failed")
		return false
	return true

func current_bodies() -> Array[Dictionary]:
	var out := _body_reports.duplicate(true)
	var expired := _has_good and Time.get_ticks_msec() - _observed_msec > DEFAULT_STALE_MSEC
	if not _has_good or expired or not _failure.is_empty():
		for entry in out:
			if entry.get("state", "") == "reported_fresh":
				entry["state"] = "stale" if expired else "unknown"
	return out

func _completed(result: int, status: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		_mark_failure("local_studio_fleet_unavailable")
		return
	if bytes.size() > MAX_BYTES:
		_mark_failure("fleet_response_oversized")
		return
	var parsed: Dictionary = PROJECTION.parse_bodies(bytes.get_string_from_utf8())
	if not parsed.get("ok", false):
		_mark_failure(String(parsed.get("reason", "fleet_contract_invalid")))
		return
	_body_reports = parsed["bodies"].duplicate(true)
	_has_good = true
	_observed_msec = Time.get_ticks_msec()
	_failure = ""
	bodies_changed.emit(current_bodies())

func _mark_failure(reason: String) -> void:
	_failure = reason
	bodies_changed.emit(current_bodies())
