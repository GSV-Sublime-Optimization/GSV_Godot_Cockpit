extends SceneTree

## Ledger draw smoke — the #8 pattern (SceneTree script, exit 0/1).
## Exercises the real 1600x900 CanvasItem draw callbacks at the design size,
## plus the small-window guard and the missing-feed error state. A headless
## dummy renderer cannot supply a qualifying PNG or GPU timing; the real
## --shot receipt is queued in docs/mindview-muse/VERIFICATION.md.
##
## Run (queued):
##   godot --headless --path . --script res://tests/ledger_render_test.gd

const SCENE = preload("res://scenes/LedgerView.tscn")
var failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var surface: Control = SCENE.instantiate()
	# Disable the scene's full-rect anchoring before the manual test size.
	surface.set_anchors_preset(Control.PRESET_TOP_LEFT)
	surface.size = Vector2(1600, 900)
	root.add_child(surface)
	surface.queue_redraw()
	for i in 5:
		await process_frame
	if surface._feed.get("events", []).size() != 4:
		_fail("source did not reach renderer")
		_finish()
		return
	if surface._event_hitboxes.size() != 4:
		_fail("river did not lay out one hitbox per event")
		_finish()
		return
	if surface._need_hitboxes.size() != 3:
		_fail("needs-you column did not lay out three items")
		_finish()
		return
	# Draw every event as selected, so each river tower / card state is hit.
	for i in 4:
		surface._selected = i
		surface.queue_redraw()
		await process_frame
	# Small-window guard draws instead of crashing.
	surface.size = Vector2(800, 500)
	surface.queue_redraw()
	await process_frame
	surface.size = Vector2(1600, 900)
	# Missing-feed error state draws (and stays Esc-quittable by dispatch).
	surface._feed_dir = "res://tests/fixtures/does-not-exist"
	surface._load_feed()
	surface.queue_redraw()
	await process_frame
	if surface._error.is_empty():
		_fail("missing feed did not raise the error state")
		_finish()
		return
	surface.queue_free()
	await process_frame
	_finish()


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("LEDGER_HEADLESS_DRAW_PASS")
		quit(0)
	else:
		for reason in failures:
			printerr("LEDGER_RENDER_FAIL: " + reason)
		quit(1)
