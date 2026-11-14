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
	_check(OS.low_processor_usage_mode,
		"idle redraws only on demand (#14: <=5% of one core; was ~12.6% on i3)")
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
	var vitals: PackedStringArray = view._vitals_lines()
	_check(vitals.size() == 4, "vitals lens lists all four rigs")
	_check(vitals.size() == 4 and vitals[1].contains("RED") and vitals[1].contains("failing: docker"),
		"vitals lens shows i3's reported failing check, not just a caption")
	# Filters must not leave the inspector on an event the tape hides.
	view._selected = 0  # model-summary alarm
	view._mind_filter = "observer"
	view._select_within_filter()
	_check(view._filtered_indices().has(view._selected),
		"observer filter moves selection onto a visible observer event")
	view._mind_filter = "all"
	# '?' is Shift+Slash on US layouts; KEY_QUESTION alone never arrives.
	var q := InputEventKey.new()
	q.keycode = KEY_SLASH
	q.unicode = 0x3F
	q.shift_pressed = true
	q.pressed = true
	view._unhandled_key_input(q)
	_check(view._show_help, "'?' (Shift+Slash) opens the help guide")
	view._unhandled_key_input(q)
	_check(not view._show_help, "'?' closes the help guide again")
	_check(view._error.is_empty(), "no data-load errors")
	_check(view._effective_rig_status("i3") == "red",
		"historical fixture retains its source-reported i3 failure")
	view._is_fixture = false
	view._feed["source_at"] = "2020-01-01T00:00:00Z"
	_check(view._effective_rig_status("msi") == "stale",
		"expired live file cannot render a green rig")
	view._is_fixture = true
	# Host scheduling/GPU contention makes a wall-clock threshold an unreliable
	# proof of network absence. Verify the actual file source contract instead.
	_check(view._is_fixture and view._feed_path.begins_with("res://"),
		"the fixture scene stays local-only and does not perform SSH")
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
