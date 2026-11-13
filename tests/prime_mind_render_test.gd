extends SceneTree

## Draw smoke: exercises real 1280x720 CanvasItem draw callbacks, not only parsing.
## Headless dummy renderer cannot supply a qualifying PNG or GPU timing.
const SCENE = preload("res://scenes/PrimeMind.tscn")

## A draw callback that hits a script error keeps running, so count errors
## and fail the smoke on any (e.g. String(null) on a work line's focus).
class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String,
			_rationale: String, _editor_notify: bool, _error_type: int,
			_script_backtrace: Array[ScriptBacktrace]) -> void:
		count += 1

var errors := ErrorCounter.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	OS.add_logger(errors)
	var surface: Control = SCENE.instantiate()
	# Disable the scene's full-rect anchoring before the manual test size.
	surface.set_anchors_preset(Control.PRESET_TOP_LEFT)
	surface.size = Vector2(1280, 720)
	root.add_child(surface)
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
	# Colony work lane and the work inspector, on the order/receipt fixture.
	surface._feed_path = "res://tests/fixtures/prime_mind_work_feed.json"
	surface._load_snapshot()
	if surface._tape.size() != 29:
		printerr("PRIME_RENDER_FAIL: work fixture did not reach the tape")
		quit(1)
		return
	for f in ["all", "work"]:
		surface._mind_filter = f
		surface._select_within_filter()
		# Every work line, including those with a null focus, through draw.
		for i in surface._filtered_indices():
			surface._selected = i
			surface.queue_redraw()
			await process_frame
	surface.queue_free()
	await process_frame
	OS.remove_logger(errors)
	if errors.count > 0:
		printerr("PRIME_RENDER_FAIL: %d script errors during draw" % errors.count)
		quit(1)
		return
	print("PRIME_HEADLESS_DRAW_PASS")
	quit(0)
