extends SceneTree

const PROJECTION = preload("res://scripts/entity/FleetBodiesProjection.gd")
const ENTITY = preload("res://scripts/entity/EntitySession.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var empty = PROJECTION.parse_bodies("{}")
	_check(not empty.get("ok", false), "empty payload fails closed")
	_check(PROJECTION.unknown().size() == 4, "four explicit unknown bodies")
	var nodes: Array = []
	for node_id in PROJECTION.BODY_IDS:
		nodes.append({
			"body_id": node_id,
			"state": "reported_fresh",
			"age_seconds": 0,
			"identity_attested": false,
			"remote_work_admitted": false,
			"execution_authorized": false,
			"observation": {
				"memory_available_bytes": 4096,
				"system_volume_free_bytes": 8192,
				"secret": "DO_NOT_EXPOSE"
			}
		})
	var raw := {"schema": PROJECTION.SCHEMA, "entity_id": PROJECTION.ENTITY_ID, "bodies": nodes}
	var valid: Dictionary = PROJECTION.parse_bodies(JSON.stringify(raw))
	_check(valid.get("ok", false), "legitimate four-body projection admitted")
	if valid.get("ok", false):
		_check(valid["bodies"].size() == 4, "all bodies retained")
		_check(not JSON.stringify(valid).contains("DO_NOT_EXPOSE"), "unknown input fields dropped")
		_check(not valid["bodies"][0]["execution_authorized"], "zero self-authorized actions")
	nodes[1]["execution_authorized"] = true
	_check(not PROJECTION.parse_bodies(JSON.stringify(raw)).get("ok", false),
		"unauthorized actuator claim denied")
	nodes[1]["execution_authorized"] = false
	nodes[1]["body_id"] = nodes[0]["body_id"]
	_check(not PROJECTION.parse_bodies(JSON.stringify(raw)).get("ok", false),
		"duplicate body id denied")
	nodes[1]["body_id"] = PROJECTION.BODY_IDS[1]
	nodes[0]["observation"]["memory_available_bytes"] = -1
	_check(not PROJECTION.parse_bodies(JSON.stringify(raw)).get("ok", false),
		"negative resource metric denied")
	var session: Node = ENTITY.new()
	root.add_child(session)
	await process_frame
	_check(session.self_model().get("fleet_bodies", []).size() == 4,
		"same embodied session exposes four bounded body slots")
	_check(session.self_model().get("authorized_actuators", ["bad"]).is_empty(),
		"fleet sensor does not mint authority")
	session.queue_free()
	if failures.is_empty():
		print("ENTITY_FLEET_PROJECTION_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("ENTITY_FLEET_PROJECTION_FAIL: " + failure)
		quit(1)

func _check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
