extends SceneTree

## Godot UI -> isolated Studio (same host) -> physical fleet source receipts.
const SCENE = preload("res://scenes/ColonyWorkstation.tscn")
const TIMEOUT_FRAMES := 480

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("GSV_STUDIO_ENTITY_PORT").is_empty():
		_fail("isolated Studio endpoint not configured")
		return
	var ui: Control = SCENE.instantiate()
	root.add_child(ui)
	var observed := false
	for i in TIMEOUT_FRAMES:
		await process_frame
		if ui._status != null and ui._status.text.contains("BODIES 4/4 FRESH"):
			observed = true
			break
	if not observed:
		_fail("four real reports never reached the workstation")
		return
	if ui._rig_labels.size() != 4:
		_fail("one physical body absent from UI")
		return
	for rig_id in ui._rig_labels.keys():
		if not ui._rig_labels[rig_id].text.contains("REPORTED_FRESH"):
			_fail("body observation not displayed: " + rig_id)
			return
	if ui._client.snapshot()["authorized_actuators"].size() != 0:
		_fail("unreviewed action authority granted")
		return
	ui.queue_free()
	print("WORKSTATION_FOUR_RIG_LIVE_PASS")
	quit(0)

func _fail(reason: String) -> void:
	printerr("WORKSTATION_FOUR_RIG_LIVE_FAIL: " + reason)
	quit(1)
