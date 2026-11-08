extends Control

## The war room on its own (scenes/HoloWarRoom.tscn): the Hologram tab
## without the rest of the cockpit, for agents, smoke runs and renders.
##
##   godot --path . res://scenes/HoloWarRoom.tscn -- [--offscreen] [--shot=PATH] [--quit-after=SECONDS]
##
## Exits, stated up front: Esc quits; --quit-after=SECONDS quits on a timer;
## --shot=PATH renders the HoloRoom to PATH and quits (exit 0 written,
## 1 failed or timed out, 2 no renderer, e.g. --headless).
## --offscreen parks the window at (12000, 12000) so a render steals no screen.
## Budget as in HoloBudget (30 fps focused, 10 unfocused, low-processor mode).

const HOLO_TAB_SCRIPT: Script = preload("res://scripts/holo/HoloTab.gd")
const SHOT_SETTLE_SECONDS := 1.5
const SHOT_TIMEOUT_SECONDS := 20.0

var _tab: Control
var _shot_done: bool = false


func _ready() -> void:
	var args := HoloBudget.cmdline_args()
	HoloBudget.apply()
	if HoloBudget.wants_offscreen(args):
		HoloBudget.park_offscreen()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tab = HOLO_TAB_SCRIPT.new()
	_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tab)
	print("[war-room] up — Esc quits")
	var quit_after := HoloBudget.quit_after_seconds(args)
	if quit_after > 0.0:
		print("[war-room] --quit-after=%.0f: quitting on a timer" % quit_after)
		get_tree().create_timer(quit_after).timeout.connect(func() -> void: get_tree().quit(0))
	var shot := HoloBudget.shot_path(args)
	if not shot.is_empty():
		_take_shot(shot)


func _input(event: InputEvent) -> void:
	if HoloBudget.is_quit_event(event):
		print("[war-room] Esc — quitting")
		get_viewport().set_input_as_handled()
		get_tree().quit(0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			HoloBudget.set_focused(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			HoloBudget.set_focused(false)


func tab() -> Control:
	return _tab


func _take_shot(path: String) -> void:
	get_tree().create_timer(SHOT_TIMEOUT_SECONDS).timeout.connect(func() -> void:
		if not _shot_done:
			printerr("[holo-shot] FAIL: timed out after %.0f s" % SHOT_TIMEOUT_SECONDS)
			get_tree().quit(1)
	)
	if DisplayServer.get_name() == "headless":
		_shot_done = true
		printerr("[holo-shot] FAIL: no renderer (headless); run windowed with --offscreen")
		get_tree().quit(2)
		return
	# A shot must draw even though the room is still: keep frames coming.
	OS.low_processor_usage_mode = false
	await get_tree().create_timer(SHOT_SETTLE_SECONDS).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var abs_path := path if path.is_absolute_path() else ProjectSettings.globalize_path("user://" + path)
	var err: int = _tab.capture_png(abs_path)
	_shot_done = true
	if err != OK:
		printerr("[holo-shot] FAIL: could not write %s (error %d)" % [abs_path, err])
		get_tree().quit(1)
		return
	print("[holo-shot] wrote %s" % abs_path)
	get_tree().quit(0)
