extends SceneTree

## Ledger scene test — the #8 pattern (SceneTree script, exit 0/1).
## Instantiates the real scene against the real shared fixture and checks the
## derived state the drawing depends on, plus the exit contract: Esc maps to
## "quit" through the pure _key_action dispatch, in every state — including
## a missing/bad feed, where the scene still loads and still quits.
##
## Run (queued — see docs/mindview-muse/VERIFICATION.md):
##   godot --headless --path . --script res://tests/ledger_scene_test.gd

const SCENE = preload("res://scenes/LedgerView.tscn")
const VIEW = preload("res://scripts/LedgerView.gd")
var failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var view: Control = SCENE.instantiate()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	await process_frame
	if view.get_script() == null:
		_check(false, "scene script failed to load")
		view.queue_free()
		_finish()
		return
	_check(view._feed.get("ok", false), "shared fixture loaded by the scene")
	_check(view._feed.get("events", []).size() == 4, "scene holds the 4 fixture events")
	_check(view._selected == 3, "latest event selected by default")
	var latest := view._selected_event()
	_check(String(latest.get("line", "")) == "i3 failing: docker", "latest thought is the 06:36 docker line")
	_check(int(latest.get("ms", -1)) == 16578, "latest think time 16578 ms carried through")
	_check(view._mark_lane(view._feed["events"][0]) == "i3", "05:35 alarm marks on the i3 lane (first rig named in its reasons)")
	_check(view._mark_lane(latest) == "i3", "notable events mark on the i3 lane (focus)")
	_check(view._error.is_empty(), "no data-load errors")
	_check(get_window().mode == Window.MODE_WINDOWED, "windowed by default, never fullscreen")
	_check(not get_window().always_on_top, "never topmost")
	# Exit contract, exercised without quitting: the pure dispatch.
	_check(VIEW._key_action(_fake_key(KEY_ESCAPE)) == "quit", "Esc maps to quit")
	_check(VIEW._key_action(_fake_key(KEY_F11)) == "fullscreen", "F11 alone maps to fullscreen toggle")
	_check(VIEW._key_action(_fake_key(KEY_LEFT)) == "step-1", "Left steps back through events")
	_check(VIEW._key_action(_fake_key(KEY_RIGHT)) == "step+1", "Right steps forward through events")
	_check(VIEW._key_action(_fake_key(KEY_R)) == "reload", "R reloads the feed")
	var echo := _fake_key(KEY_ESCAPE)
	echo.echo = true
	_check(VIEW._key_action(echo).is_empty(), "key echo never quits (held Esc cannot double-fire)")
	_check(VIEW._key_action(_fake_key(KEY_A)).is_empty(), "unbound keys do nothing")
	# Scrubbing wraps and stays in range.
	view._step(1)
	_check(view._selected == 0, "stepping past the latest wraps to the first event")
	view._step(-1)
	_check(view._selected == 3, "stepping back from the first wraps to the latest")
	# Missing feed: the scene still loads, still reports the error, and the
	# exit dispatch is unchanged — Esc quits even with no data at all.
	view._feed_dir = "res://tests/fixtures/does-not-exist"
	view._load_feed()
	await process_frame
	_check(not view._error.is_empty(), "missing feed reported, not silently rendered")
	_check(view._selected == -1, "no event selected when the feed is missing")
	_check(VIEW._key_action(_fake_key(KEY_ESCAPE)) == "quit", "Esc still maps to quit with a missing feed")
	view.queue_free()
	await process_frame
	_finish()


func _fake_key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = false
	return event


func _finish() -> void:
	if failures.is_empty():
		print("LEDGER_SCENE_PASS")
		quit(0)
	else:
		for reason in failures:
			printerr("LEDGER_SCENE_FAIL: " + reason)
		quit(1)


func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
