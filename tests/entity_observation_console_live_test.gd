extends SceneTree

## Real physical R0 receipts -> isolated Studio HTTP -> actual Godot console.
const SCENE = preload("res://scenes/EntityObservationConsole.tscn")
const MAX_FRAMES := 480

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("GSV_STUDIO_ENTITY_PORT").is_empty():
		_fail("isolated Studio port not supplied")
		return
	var console: Node = SCENE.instantiate()
	root.add_child(console)
	var found := false
	for i in MAX_FRAMES:
		await process_frame
		if console._body_labels.size() != 4:
			continue
		var count := 0
		for row in console._body_labels.values():
			if row.text.contains("reported_fresh"):
				count += 1
		if count == 4:
			found = true
			break
	if not found:
		_fail("actual four-body console did not update from Studio")
		return
	if not console._headline.text.contains("0 authorized actuators"):
		_fail("authoritative control boundary disappeared")
		return
	console.queue_free()
	print("ENTITY_CONSOLE_FOUR_REAL_BODIES_PASS")
	quit(0)

func _fail(reason: String) -> void:
	printerr("ENTITY_CONSOLE_FOUR_REAL_BODIES_FAIL: " + reason)
	quit(1)
