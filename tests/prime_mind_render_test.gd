extends SceneTree

## Draw smoke: exercises real 1280x720 CanvasItem draw callbacks, not only parsing.
## Headless dummy renderer cannot supply a qualifying PNG or GPU timing.
const SCENE = preload("res://scenes/PrimeMind.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var surface: Control = SCENE.instantiate()
	root.add_child(surface)
	surface.size = Vector2(1280, 720)
	surface.queue_redraw()
	for i in 5:
		await process_frame
	if surface._feed.get("events", []).size() != 13:
		printerr("PRIME_RENDER_FAIL: source did not reach renderer")
		quit(1)
		return
	if surface._rig_positions(Rect2(280, 86, 700, 450)).size() != 5:
		printerr("PRIME_RENDER_FAIL: network topology incomplete")
		quit(1)
		return
	# Test actual draw callbacks at each lens and one filter, including text
	# in the source, without issuing a privileged tool request.
	for lens in [0, 1, 2]:
		surface._lens = lens
		surface.queue_redraw()
		await process_frame
	surface._mind_filter = "models"
	surface.queue_redraw()
	await process_frame
	surface.queue_free()
	await process_frame
	print("PRIME_HEADLESS_DRAW_PASS")
	quit(0)
