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
	await _check_work_tape(view)
	view.queue_free()
	await process_frame
	_finish()

## The tape carries colony work in its own lane, filter and inspector.
func _check_work_tape(view: Control) -> void:
	view._feed_path = "res://tests/fixtures/prime_mind_work_feed.json"
	view._is_fixture = true
	view._selected = -1
	view._load_snapshot()
	_check(view._error.is_empty(), "work fixture loads: " + view._error)
	_check(view._feed.get("events", []).size() == 13, "thought events unchanged by work")
	_check(view._tape.size() == 29, "tape merges 13 thoughts and 16 work lines")
	var ordered := true
	for i in range(1, view._tape.size()):
		if String(view._tape[i]["at"]).substr(0, 19) < String(view._tape[i - 1]["at"]).substr(0, 19):
			ordered = false
	_check(ordered, "merged tape is in time order")
	_check(view._selected_event().get("identity") == "model_summary",
		"default selection is still the latest model thought, not work")
	view._mind_filter = "models"
	var models: int = view._filtered_indices().size()
	view._mind_filter = "observer"
	var observers: int = view._filtered_indices().size()
	view._mind_filter = "work"
	var work: Array[int] = view._filtered_indices()
	_check(work.size() == 16, "work filter shows exactly the 16 work lines")
	_check(models + observers + work.size() == 29, "models, observers and work partition the tape")
	for i in work:
		_check(view._tape[i]["identity"] == "work", "work filter holds only work")
	view._select_within_filter()
	_check(view._selected_event().get("identity") == "work", "work filter selects a work line")
	var reported := -1
	var linked := -1
	for i in work:
		var e: Dictionary = view._tape[i]
		if e.get("receipt") == "reported" and reported < 0:
			reported = i
		if e.get("receipt") == "linked":
			linked = i
	_check(reported >= 0 and view.work_status_text(view._tape[reported]).contains("REPORTED"),
		"done without link reads REPORTED")
	_check(linked >= 0 and view.work_status_text(view._tape[linked]).contains("LINKED")
		and not view.work_status_text(view._tape[linked]).contains("VERIF"),
		"done with link reads LINKED and never VERIFIED")
	for target in [reported, linked, work[0]]:
		view._selected = target
		view.queue_redraw()
		await process_frame
	_check(view._selected_event().get("kind") == "order", "first work line is an order")
	_check(view.focus_of({"focus": null}) == "" and view.focus_of({}) == ""
		and view.focus_of(view._tape[work[3]]) == "i3",
		"null focus (orders, receipts) is safe; a rig change attends its rig")
	var m := InputEventKey.new()
	m.keycode = KEY_M
	m.pressed = true
	view._mind_filter = "observer"
	view._unhandled_key_input(m)
	_check(view._mind_filter == "work", "M cycles observer -> work")
	view._unhandled_key_input(m)
	_check(view._mind_filter == "all", "M cycles work -> all")

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
