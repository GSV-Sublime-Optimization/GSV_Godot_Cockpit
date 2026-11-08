extends SceneTree

const SCENE = preload("res://scenes/EntityObservationConsole.tscn")
const REQUIRED_NAMES = ["kilo-core-msi", "desktop-i3anuvp", "desktop-l9v3emb", "imac-xanadu"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var surface: Node = SCENE.instantiate()
	root.add_child(surface)
	await process_frame
	if surface._body_labels.size() != 4:
		_fail("body display missing a rig")
		return
	for key in REQUIRED_NAMES:
		if not surface._body_labels.has(key):
			_fail("body label not created for " + key)
			return
	if not surface._headline.text.contains("0 authorized actuators"):
		_fail("read-only authority label missing")
		return
	var fixture := {"phase": "observation_only", "tick": 7, "fleet_bodies": [
		{"body_id": "kilo-core-msi", "state": "reported_fresh",
			"observation": {"memory_available_bytes": 2147483648, "system_volume_free_bytes": 4294967296}},
		{"body_id": "desktop-i3anuvp", "state": "unknown"},
		{"body_id": "desktop-l9v3emb", "state": "stale", "observation": {}},
		{"body_id": "imac-xanadu", "state": "invalid"}
	]}
	surface._render_model(fixture)
	if not surface._body_labels["kilo-core-msi"].text.contains("2.0 GiB"):
		_fail("resource measurement not displayed")
		return
	if not surface._body_labels["desktop-i3anuvp"].text.contains("unknown"):
		_fail("unobserved rig falsely promoted")
		return
	if not surface._body_labels["desktop-l9v3emb"].text.contains("stale"):
		_fail("stale state hidden")
		return
	surface.queue_free()
	print("ENTITY_OBSERVATION_CONSOLE_PASS")
	quit(0)

func _fail(reason: String) -> void:
	printerr("ENTITY_OBSERVATION_CONSOLE_FAIL: " + reason)
	quit(1)
