extends SceneTree

const SCENE = preload("res://scenes/PrimeMind.tscn")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_msec()
	var view: Control = SCENE.instantiate()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	await process_frame
	if view.get_script() == null:
		_check(false, "scene script failed to load")
		view.queue_free()
		_finish()
		return
	_check(view._feed.get("ok", false), "actual pinned fixture loaded")
	_check(view._feed.get("events", []).size() == 13, "timeline loads real snapshot")
	_check(view._selected >= 0, "latest real model thought selected")
	_check(view._selected_event().get("identity") == "model_summary",
		"default favors a real recorded model summary")
	_check(view._filtered_indices().size() == 13, "all source events visible")
	view._mind_filter = "models"
	_check(view._filtered_indices().size() < 13, "Mind lens isolates model summaries")
	view._mind_filter = "observer"
	_check(view._filtered_indices().size() < 13, "observer lens excludes models")
	view._mind_filter = "all"
	view._step(-1)
	_check(view._selected >= 0, "scrubbed event retains valid index")
	view._lens = 2
	view.queue_redraw()
	await process_frame
	_check(view._lens == 2, "vitals lens selectable")
	_check(view._error.is_empty(), "no data-load errors")
	_check(Time.get_ticks_msec() - started < 1500, "no remote call on Godot startup")
	view.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("PRIME_SCENE_PASS")
		quit(0)
	else:
		for reason in failures:
			printerr("PRIME_SCENE_FAIL: " + reason)
		quit(1)

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
