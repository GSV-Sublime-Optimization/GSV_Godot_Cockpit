class_name HoloBudget
extends RefCounted

## The war room's idle budget and its exits, in one place so the cockpit
## (Main.gd) and the standalone war room (HoloWarRoomApp) behave the same.
##
## Budget (bake-off rule: <= 5% of one core idle):
##   - Engine.max_fps 30 while focused, 10 while unfocused;
##   - OS.low_processor_usage_mode, so a still scene is not redrawn;
##   - the HoloTab SubViewport renders only when visible (UPDATE_WHEN_VISIBLE);
##   - HoloRoom stops its own _process when nothing is moving. Motion is real
##     events only (Keath's rule): a pull, a pointer move, or an observation
##     whose honest state changed.
##
## Exits: Esc quits from anywhere; --shot=PATH renders the HoloRoom to a PNG
## and quits; --quit-after=SECONDS is a hard timeout for unattended runs;
## --offscreen parks the window at (12000, 12000) for renders nobody watches.
## Flags are read from the user args (after "--") and, as a convenience,
## from the engine args too.

const ACTIVE_FPS := 30
const UNFOCUSED_FPS := 10
const OFFSCREEN_POSITION := Vector2i(12000, 12000)


static func apply() -> void:
	Engine.max_fps = ACTIVE_FPS
	OS.low_processor_usage_mode = true


static func set_focused(focused: bool) -> void:
	Engine.max_fps = ACTIVE_FPS if focused else UNFOCUSED_FPS


static func is_quit_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and key.keycode == KEY_ESCAPE


static func cmdline_args() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(OS.get_cmdline_user_args())
	out.append_array(OS.get_cmdline_args())
	return out


## "--shot=PATH" -> PATH (empty when absent or empty).
static func shot_path(args: PackedStringArray) -> String:
	return _flag_value(args, "--shot=")


## "--quit-after=SECONDS" -> seconds (0.0 when absent or not a positive number).
static func quit_after_seconds(args: PackedStringArray) -> float:
	var raw := _flag_value(args, "--quit-after=")
	if raw.is_empty() or not raw.is_valid_float():
		return 0.0
	return maxf(0.0, raw.to_float())


static func wants_offscreen(args: PackedStringArray) -> bool:
	return args.has("--offscreen")


## Windowed first (Godot 4.7.1 ignores --position on this rig), then park the
## window off-screen from code and say where it went.
static func park_offscreen() -> Vector2i:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_position(OFFSCREEN_POSITION)
	var where := DisplayServer.window_get_position()
	print("[war-room] window parked off-screen at %s" % str(where))
	return where


static func _flag_value(args: PackedStringArray, prefix: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).strip_edges()
	return ""
