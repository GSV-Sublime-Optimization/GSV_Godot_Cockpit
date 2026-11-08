extends Node

## Same-host, read-only Studio observer for the DAW-style workstation.
## Actual PTY/agent attachments are NOT created by an HTTP health response.
## Separate per-resource HTTPRequest instances prevent blocking the frame loop.

signal snapshot_changed(snapshot: Dictionary)
signal mission_log_received(mission_id: String, lines: PackedStringArray, error: String)

const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")
const MISSION_CONTRACT = preload("res://scripts/workstation/WorkbenchMissionContract.gd")
const BODY_PROJECTION = preload("res://scripts/entity/FleetBodiesProjection.gd")
const HEALTH_PROJECTION = preload("res://scripts/entity/StudioHealthProjection.gd")
const RESPONSE_LIMIT := 196608

var _requests: Dictionary = {}
var _busy: Dictionary = {}
var _log_id := ""
var _bodies: Array[Dictionary] = []
var _missions: Array[Dictionary] = []
var _services: Array[Dictionary] = []
var _projects: Array[Dictionary] = []
var _projects_state := "unknown"
var _projects_at_msec := 0
var _health: Dictionary = {"state": "unknown", "error": "not_observed"}
var _body_state := "unknown"
var _mission_state := "unknown"
var _service_state := "unknown"
var _port := 7340
var _last_observed_msec := 0

func _ready() -> void:
	_bodies = BODY_PROJECTION.unknown()
	var supplied := OS.get_environment("GSV_STUDIO_ENTITY_PORT")
	if supplied.is_valid_int() and not supplied.is_empty():
		var value := int(supplied)
		if value >= 1 and value <= 65535:
			_port = value
	for kind in ["health", "bodies", "missions", "projects", "log"]:
		var request := HTTPRequest.new()
		request.name = kind.capitalize() + "Request"
		request.timeout = 24.0 if kind == "projects" else 4.0
		add_child(request)
		request.request_completed.connect(_on_request_completed.bind(kind))
		_requests[kind] = request
		_busy[kind] = false

func refresh() -> void:
	_request("health", "/api/health")
	_request("bodies", "/api/entity/bodies")
	_request("missions", "/api/missions?limit=24")
	_request("projects", "/api/projects")

func request_mission_log(mission_id: String) -> bool:
	if not CATALOG.valid_mission_id(mission_id):
		return false
	if _busy.get("log", false):
		return false
	var known := false
	for mission in _missions:
		if mission.get("id", "") == mission_id:
			known = true
			break
	if not known:
		return false
	_log_id = mission_id
	return _request("log", "/api/missions/%s/log?tail=100" % mission_id)

func snapshot() -> Dictionary:
	var bodies: Array[Dictionary] = _bodies.duplicate(true)
	if _body_state != "observed" or (
		_last_observed_msec > 0 and Time.get_ticks_msec() - _last_observed_msec > 30000
	):
		for item in bodies:
			if item.get("state", "") == "reported_fresh":
				item["state"] = "stale"
	return {
		"health": _health.duplicate(true),
		"bodies": bodies,
		"body_feed_state": _body_state,
		"missions": _missions.duplicate(true),
		"mission_feed_state": _mission_state,
		"services": _services.duplicate(true),
		"projects": _projects.duplicate(true),
		"project_feed_state": ("stale" if _projects_state == "observed" and (Time.get_ticks_msec() - _projects_at_msec > 45000) else _projects_state),
		"service_feed_state": _service_state,
		"endpoint_kind": "same_host_loopback",
		"authorized_actuators": []
	}

func _request(kind: String, path: String) -> bool:
	if _busy.get(kind, false):
		return false
	if not _requests.has(kind):
		return false
	_busy[kind] = true
	var target := "http://127.0.0.1:%d%s" % [_port, path]
	var result: int = _requests[kind].request(
		target,
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET
	)
	if result != OK:
		_busy[kind] = false
		_fail(kind, "local_request_rejected")
		return false
	return true

func _on_request_completed(result: int, status: int, _headers: PackedStringArray,
		body: PackedByteArray, kind: String) -> void:
	_busy[kind] = false
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		_fail(kind, "http_unavailable")
		return
	if body.size() > RESPONSE_LIMIT:
		_fail(kind, "payload_oversized")
		return
	var data := body.get_string_from_utf8()
	if kind == "health":
		var health: Dictionary = HEALTH_PROJECTION.parse_health(data)
		var observed: Dictionary = CATALOG.parse_services(data)
		if not health.get("ok", false) or not observed.get("ok", false):
			_fail(kind, "invalid_health_schema")
			return
		_health = health["observation"].duplicate(true)
		_services.assign(observed["services"])
		_service_state = "observed"
	elif kind == "bodies":
		var bodies: Dictionary = BODY_PROJECTION.parse_bodies(data)
		if not bodies.get("ok", false):
			_fail(kind, String(bodies.get("reason", "invalid_body_contract")))
			return
		_bodies.assign(bodies["bodies"])
		_body_state = "observed"
		_last_observed_msec = Time.get_ticks_msec()
	elif kind == "missions":
		var missions: Dictionary = CATALOG.parse_mission_list(data)
		if not missions.get("ok", false):
			_fail(kind, String(missions.get("reason", "invalid_mission_contract")))
			return
		_missions.assign(missions["missions"])
		_mission_state = "observed"
	elif kind == "projects":
		var projects: Dictionary = MISSION_CONTRACT.parse_projects(data)
		if not projects.get("ok", false):
			_fail(kind, String(projects.get("reason", "invalid_project_contract")))
			return
		_projects.assign(projects["projects"])
		_projects_state = "observed"
		_projects_at_msec = Time.get_ticks_msec()
	elif kind == "log":
		var log: Dictionary = CATALOG.parse_mission_log(data, _log_id)
		if not log.get("ok", false):
			mission_log_received.emit(_log_id, PackedStringArray(), "invalid_mission_log")
			return
		mission_log_received.emit(_log_id, log["lines"], "")
		return
	snapshot_changed.emit(snapshot())

func _fail(kind: String, reason: String) -> void:
	match kind:
		"health":
			_health = {"state": "unavailable", "error": reason}
			_service_state = "stale" if not _services.is_empty() else "unknown"
		"bodies":
			_body_state = "stale" if _last_observed_msec > 0 else "unknown"
		"missions":
			_mission_state = "stale" if not _missions.is_empty() else "unknown"
		"projects":
			_projects_state = "stale" if not _projects.is_empty() else "unknown"
		"log":
			mission_log_received.emit(_log_id, PackedStringArray(), reason)
			return
	snapshot_changed.emit(snapshot())
