extends SceneTree

## Bakeoff rule: Esc quits the standalone observation console, even with a
## text field focused. The EntitySession embedded inside the console must not
## fire its own quit path; the console, as the running scene, owns the exit.
const SCENE = preload("res://scenes/EntityObservationConsole.tscn")
const QUIT_DEADLINE_FRAMES: int = 30
var failures: PackedStringArray = []
var _console_quits: int = 0
var _session_quits: int = 0
var _frames_left: int = -1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var console: Control = SCENE.instantiate()
	root.add_child(console)
	console.quit_requested.connect(func() -> void: _console_quits += 1)
	var session: Node = console._entity
	_check(session != null, "console embeds an entity session")
	if session != null:
		session.quit_requested.connect(func() -> void: _session_quits += 1)
	var field: LineEdit = LineEdit.new()
	console.add_child(field)
	await process_frame
	current_scene = console
	field.grab_focus()
	_check(field.has_focus(), "text field holds focus before Esc")
	root.push_input(_escape())
	_check(_console_quits == 1, "Esc requests quit from the console while a field has focus")
	_check(_session_quits == 0, "embedded session does not fire its own quit")
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
	if failures.is_empty() and _console_quits == 1:
		print("ENTITY_CONSOLE_ESCAPE_QUIT_PASS")

func _escape() -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	return key

func _finish_failed() -> void:
	for item in failures:
		printerr("ENTITY_CONSOLE_ESCAPE_QUIT_FAIL: " + item)
	quit(1)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
