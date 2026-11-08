extends SceneTree

## End-to-end Godot scene → real local Studio, no synthetic HTTP.
## Requires a separately running Studio at 127.0.0.1:7340.
const ENTITY = preload("res://scenes/EntitySession.tscn")
const TIMEOUT_FRAMES := 360

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var body: Node = ENTITY.instantiate()
	root.add_child(body)
	var initial: Dictionary = body.self_model()
	if initial.get("schema", "") != "kilocore.entity-session.v0":
		_fail("wrong scene self-model schema")
		return
	if not initial.get("authorized_actuators", ["unexpected"]).is_empty():
		_fail("scene minted an actuator")
		return
	var observed := false
	for i in TIMEOUT_FRAMES:
		await process_frame
		var model: Dictionary = body.self_model()
		var sensor: Dictionary = model.get("sensor", {})
		if sensor.get("state", "") == "live":
			observed = true
			if sensor.get("schema", "") != "kilocore-studio.cockpit-health.v2":
				_fail("unknown observed schema")
				return
			if sensor.get("mission_counts", {}).size() != 3:
				_fail("unbounded or missing typed mission counts")
				return
			if body.recent_events().is_empty():
				_fail("state event not recorded")
				return
			break
	if not observed:
		_fail("Studio not observed within timeout")
		return
	body.queue_free()
	print("ENTITY_SCENE_LIVE_PASS")
	quit(0)

func _fail(message: String) -> void:
	printerr("ENTITY_SCENE_LIVE_FAIL: " + message)
	quit(1)
