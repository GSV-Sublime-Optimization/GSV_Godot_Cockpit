extends SceneTree

## Real Godot scene -> isolated Studio HTTP -> four physical receipt files.
## Run ONLY against the optional local test server; never fake a live result.
const SCENE = preload("res://scenes/EntitySession.tscn")
const MAX_FRAMES := 480

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("GSV_STUDIO_ENTITY_PORT").is_empty():
		_fail("live test port not configured")
		return
	var entity: Node = SCENE.instantiate()
	root.add_child(entity)
	var observed := false
	for i in MAX_FRAMES:
		await process_frame
		var model: Dictionary = entity.self_model()
		var reports: Array = model.get("fleet_bodies", [])
		if reports.size() != 4:
			continue
		var count := 0
		for report in reports:
			if report.get("state", "") == "reported_fresh":
				count += 1
			if report.get("execution_authorized", true) != false:
				_fail("an observation granted action authority")
				return
		if count == 4:
			observed = true
			if model.get("authorized_actuators", ["unsafe"]).size() != 0:
				_fail("entity session granted hidden actuator")
				return
			if entity.recent_events().is_empty():
				_fail("live body report missing event trace")
				return
			break
	entity.queue_free()
	if not observed:
		_fail("four live OS observations did not reach the scene")
		return
	print("ENTITY_FOUR_BODIES_LIVE_PASS")
	quit(0)

func _fail(reason: String) -> void:
	printerr("ENTITY_FOUR_BODIES_LIVE_FAIL: " + reason)
	quit(1)
