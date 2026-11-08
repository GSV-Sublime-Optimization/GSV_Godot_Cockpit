extends SceneTree

## Bakeoff rule: Esc exits the workstation. With the command palette open the
## first Esc only closes the palette; the next Esc quits even while a text
## field holds focus. Events are injected through the root viewport and the
## tree itself must stop; an embedded (non-root) workstation must not quit.
const SCENE = preload("res://scenes/ColonyWorkstation.tscn")
const QUIT_DEADLINE_FRAMES: int = 30
var failures: PackedStringArray = []
var _quit_requests: int = 0
var _frames_left: int = -1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host: Node = Node.new()
	host.name = "FixtureHost"
	root.add_child(host)
	var ui: Control = SCENE.instantiate()
	ui.auto_refresh = false  # no Studio traffic from this test
	root.add_child(ui)
	ui.quit_requested.connect(func() -> void: _quit_requests += 1)
	var field: LineEdit = LineEdit.new()
	ui.add_child(field)
	await process_frame
	_check(ui._view_ready, "workstation ready before Esc")
	# Embedded: another node is the running scene, so Esc must not quit.
	current_scene = host
	root.push_input(_escape())
	_check(_quit_requests == 0, "embedded workstation ignores Esc")
	current_scene = ui
	# Palette open with its search field focused: Esc closes it, nothing quits.
	ui._show_palette()
	await process_frame
	_check(ui._palette.visible, "command palette opened")
	root.push_input(_escape())
	await process_frame
	_check(not ui._palette.visible, "first Esc closes the command palette")
	_check(_quit_requests == 0, "closing the palette does not quit")
	if not failures.is_empty():
		_finish_failed()
		return
	# Palette closed, text field focused: Esc quits.
	field.grab_focus()
	_check(field.has_focus(), "text field holds focus before Esc")
	root.push_input(_escape())
	_check(_quit_requests == 1, "Esc requests quit while a text field has focus")
	if not failures.is_empty():
		_finish_failed()
		return
	_frames_left = QUIT_DEADLINE_FRAMES  # the tree must now stop by itself

func _process(_delta: float) -> bool:
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
			failures.append("tree still running %d frames after Esc" % QUIT_DEADLINE_FRAMES)
			_finish_failed()
	return false

func _finalize() -> void:
	if failures.is_empty() and _quit_requests == 1:
		print("WORKSTATION_ESCAPE_QUIT_PASS")

func _escape() -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	return key

func _finish_failed() -> void:
	for item in failures:
		printerr("WORKSTATION_ESCAPE_QUIT_FAIL: " + item)
	quit(1)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
