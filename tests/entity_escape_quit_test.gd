extends SceneTree

## Bakeoff rule: Esc quits the running entry, even with a text field focused.
## Injects a real InputEventKey through the root viewport and requires the
## tree itself to stop; an embedded (non-root) instance must not quit its host.
const SCENE = preload("res://scenes/EntitySession.tscn")
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
	var session: Node = SCENE.instantiate()
	session.auto_observe = false  # no Studio/Gateway traffic from this test
	root.add_child(session)
	session.quit_requested.connect(func() -> void: _quit_requests += 1)
	var field: LineEdit = LineEdit.new()
	root.add_child(field)
	await process_frame
	# Embedded: some other node is the running scene, so Esc must not quit.
	current_scene = host
	root.push_input(_escape())
	_check(_quit_requests == 0, "embedded session ignores Esc")
	if not failures.is_empty():
		_finish_failed()
		return
	# Running scene root, with a text field holding focus.
	current_scene = session
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
		print("ENTITY_ESCAPE_QUIT_PASS")

func _escape() -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	return key

func _finish_failed() -> void:
	for item in failures:
		printerr("ENTITY_ESCAPE_QUIT_FAIL: " + item)
	quit(1)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
