extends Control

## The Ledger — Muse's Mind View bake-off entry.
## A watch-ledger of what the colony's Minds noticed: continuity across time —
## recurrence and outcomes. Not a world, not a sky, not a tape: a ledger.
##
## Reads the SHARED fixture directory directly (never a copy):
##   res://tests/fixtures/mindview-20261108/
## Observation only. Zero actuators, in code and in fact: no POST, no /act,
## no channel writes, no tasks run, no containers restarted. The next step is
## a copyable move plus an owner; the action happens elsewhere, by an agent.
##
## Exit discipline (copied from the Loom, hardened against the #12 trap):
## windowed by default, never topmost, Esc quits immediately, F11 alone is
## the only fullscreen path, and the exit handler lives in THIS scene script
## — it works in every state, including a missing or malformed feed.
## Run:  godot --path . res://scenes/LedgerView.tscn
## Shot: godot --path . res://scenes/LedgerView.tscn -- --shot=<png>

const FEED = preload("res://tools/mindview_ledger/LedgerFeed.gd")
const BG = Color("#0a0f16")
const PANEL = Color("#101a26")
const EDGE = Color("#26374b")
const INK = Color("#e8f2fa")
const MUTE = Color("#8ba1b5")
const GOLD = Color("#f8be6c")
const CYAN = Color("#54e4db")
const VIOLET = Color("#b4a3ff")
const AMBER = Color("#f8be6c")
const RED = Color("#ff738a")
const GREEN = Color("#69d7b0")
const TEAL = Color("#54e4db")
const RIG_IDS = ["msi", "i3", "l9", "xanadu"]
const RIG_NAMES = {"msi": "MSI", "i3": "I3", "l9": "L9", "xanadu": "XANADU"}
const RIG_ROLES = {"msi": "workshop", "i3": "engine room", "l9": "triage drone", "xanadu": "librarian + watchman"}
# River window: first event 05:35 → freeze 06:48 UTC = 73 minutes.
const RIVER_START_MIN := 5 * 60 + 35
const RIVER_SPAN_MIN := 73

var _feed: Dictionary = {}
var _selected := -1
var _feed_dir := FEED.FIXTURE_DIR
var _is_fixture := true
var _error := ""
var _shot_path := ""
var _phase := 0.0
var _frame_budget := 0.0
var _show_help := false
var _font: Font
var _event_hitboxes: Array[Dictionary] = []
var _need_hitboxes: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	Engine.max_fps = 30
	get_window().mode = Window.MODE_WINDOWED
	get_window().always_on_top = false
	_parse_args()
	_load_feed()
	if not _shot_path.is_empty():
		# Screenshot is a non-interactive, offscreen acceptance operation.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		call_deferred("_capture_when_ready")
	set_process(true)
	queue_redraw()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--fixture="):
			_feed_dir = arg.trim_prefix("--fixture=")
			_is_fixture = true
		elif arg.begins_with("--feed="):
			_feed_dir = arg.trim_prefix("--feed=")
			_is_fixture = false
		elif arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg == "--background":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		elif arg == "--no-animate":
			Engine.max_fps = 10
	if _feed_dir.begins_with("http:") or _feed_dir.begins_with("https:"):
		_error = "Remote URLs are not a data source"
		_feed_dir = ""


func _load_feed() -> void:
	if _feed_dir.is_empty():
		return
	_feed = FEED.load_fixture_dir(_feed_dir)
	if not _feed.get("ok", false):
		_error = String(_feed.get("reason", "Malformed source observation"))
		_selected = -1
		queue_redraw()
		return
	_error = ""
	var events: Array = _feed.get("events", [])
	_selected = events.size() - 1
	queue_redraw()


## Pure key dispatch, so the exit contract is unit-testable without quitting.
## Returns: "quit" | "fullscreen" | "step-1" | "step+1" | "reload" | "help" | "".
static func _key_action(event: InputEvent) -> String:
	if not (event is InputEventKey):
		return ""
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return ""
	match key.keycode:
		KEY_ESCAPE:
			return "quit"
		KEY_F11:
			return "fullscreen"
		KEY_LEFT:
			return "step-1"
		KEY_RIGHT:
			return "step+1"
		KEY_R:
			return "reload"
		KEY_QUESTION, KEY_F1:
			return "help"
	return ""


func _unhandled_key_input(event: InputEvent) -> void:
	match _key_action(event):
		"quit":
			get_tree().quit(0)
		"fullscreen":
			get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		"step-1":
			_step(-1)
		"step+1":
			_step(1)
		"reload":
			_load_feed()
		"help":
			_show_help = not _show_help
	queue_redraw()


func _step(direction: int) -> void:
	var events: Array = _feed.get("events", [])
	if events.is_empty():
		return
	_selected = posmod(_selected + direction, events.size())
	queue_redraw()


func _process(delta: float) -> void:
	# Fps tiers: full rate while focused, 10 fps backgrounded/minimised.
	if get_window().has_focus():
		Engine.max_fps = 30
	else:
		Engine.max_fps = 10
	_frame_budget += delta
	if _frame_budget < 0.105:
		return
	_phase += minf(_frame_budget, 0.2)
	_frame_budget = 0.0
	queue_redraw()


func _selected_event() -> Dictionary:
	var events: Array = _feed.get("events", [])
	if _selected < 0 or _selected >= events.size():
		return {}
	return events[_selected]


## Which lane a mark sits on: the event's focus when present, else the first
## rig named in its reasons, else the Mind's home rig (l9-triage-drone → l9).
func _mark_lane(e: Dictionary) -> String:
	var focus := String(e.get("focus", ""))
	if not focus.is_empty():
		return focus
	for reason in e.get("reasons", []):
		for rig in RIG_IDS:
			if String(reason).begins_with(rig + " failing"):
				return rig
	var mind := String(e.get("mind", ""))
	for rig in RIG_IDS:
		if mind.begins_with(rig):
			return rig
	return "l9"


func _level_color(level: String) -> Color:
	match level:
		"alarm":
			return RED
		"notable":
			return AMBER
		"routine":
			return TEAL
		"calm":
			return GREEN
	return MUTE


func _minutes_of(stamp: String) -> int:
	if stamp.length() < 16:
		return -1
	var hour := int(stamp.substr(11, 2))
	var minute := int(stamp.substr(14, 2))
	return hour * 60 + minute


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), BG)
	if sz.x < 930.0 or sz.y < 540.0:
		_txt(Vector2(26, 38), "THE LEDGER", 23, GOLD)
		_wrap(Vector2(26, 90), "Resize to at least 930 × 540 to read the ledger.", 38, 17, MUTE)
		return
	_draw_header(sz)
	if not _error.is_empty():
		_draw_error(sz)
		return
	var river := Rect2(18, 76, 902, 400)
	var latest := Rect2(936, 76, 646, 400)
	var needs := Rect2(18, 490, 902, 310)
	var outcomes := Rect2(936, 490, 646, 310)
	_draw_panel(river)
	_draw_panel(latest)
	_draw_panel(needs)
	_draw_panel(outcomes)
	_draw_river(river)
	_draw_latest(latest)
	_draw_needs(needs)
	_draw_outcomes(outcomes)
	_draw_footer(sz)
	if _show_help:
		_draw_help(sz)


func _draw_header(sz: Vector2) -> void:
	_txt(Vector2(22, 34), "THE LEDGER", 24, GOLD)
	_txt(Vector2(196, 34), "A WATCH-LEDGER OF WHAT THE COLONY'S MINDS NOTICED", 14, INK)
	_txt(Vector2(22, 58), "CONTINUITY ACROSS TIME — RECURRENCE AND OUTCOMES  •  EVERY CLAIM CITES ITS SOURCE", 11, MUTE)
	_txt_right(Vector2(sz.x - 578, 30), 556, FEED.FREEZE_LABEL, 14, CYAN)
	_txt_right(Vector2(sz.x - 578, 54), 556, "OBSERVATION ONLY  ·  0 ACTUATORS  ·  ESC EXIT  ·  F11 FULLSCREEN", 11, MUTE)
	draw_line(Vector2(18, 68), Vector2(sz.x - 18, 68), EDGE, 1)


func _draw_error(sz: Vector2) -> void:
	var rect := Rect2(18, 84, sz.x - 36, 220)
	_draw_panel(rect)
	_txt(rect.position + Vector2(18, 34), "FEED UNAVAILABLE — NOTHING IS FABRICATED", 16, RED)
	_wrap(rect.position + Vector2(18, 66), "The ledger could not read its source: " + _error + ". No event, heartbeat, or outcome is shown, because none was verified. Fix the feed and press R — or press ESC to close.", 108, 13, MUTE, 4)
	_txt(rect.position + Vector2(18, 190), "ESC quits even now. The exit handler does not depend on the feed.", 12, GOLD)
	_draw_footer(sz)


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL)
	draw_rect(rect, EDGE, false, 1)
	draw_line(rect.position + Vector2(1, 1), rect.position + Vector2(minf(rect.size.x, 50), 1), GOLD.darkened(0.2), 2)


func _draw_river(rect: Rect2) -> void:
	_event_hitboxes.clear()
	_txt(rect.position + Vector2(18, 30), "TIME-RIVER  ·  05:35 → 06:48 UTC (FREEZE)", 15, GOLD)
	var rows := FEED.recurrence_rows(_feed.get("events", []))
	if not rows.is_empty():
		var top: Dictionary = rows[0]
		_txt_right(Vector2(rect.position.x + 420, 30), rect.size.x - 438, "%d× IN %d MIN — SAME LINE, SAME RIG" % [int(top["count"]), int(top["span_min"])], 13, RED)
	var plot_x0 := rect.position.x + 132.0
	var plot_x1 := rect.end.x - 18.0
	var plot_w := plot_x1 - plot_x0
	var lane_h := 72.0
	var lane_gap := 6.0
	var lane_y0 := rect.position.y + 74.0
	var beats: Dictionary = _feed.get("heartbeats", {})
	for li in RIG_IDS.size():
		var rig: String = RIG_IDS[li]
		var lane_y := lane_y0 + li * (lane_h + lane_gap)
		var lane := Rect2(rect.position.x + 12, lane_y, rect.size.x - 24, lane_h)
		if li % 2 == 0:
			draw_rect(lane, Color("#0d1622"))
		_txt(Vector2(rect.position.x + 20, lane_y + 30), String(RIG_NAMES[rig]), 15, INK)
		_txt(Vector2(rect.position.x + 20, lane_y + 50), String(RIG_ROLES[rig]), 10, MUTE)
		# Baseline.
		draw_line(Vector2(plot_x0, lane_y + lane_h - 18), Vector2(plot_x1, lane_y + lane_h - 18), Color(EDGE, 0.6), 1)
		if _feed.get("missing", []).has(rig):
			_txt(Vector2(plot_x0 + 8, lane_y + 32), "— no heartbeat in fixture —", 12, MUTE)
			_txt(Vector2(plot_x0 + 8, lane_y + 50), "absence shown, not filled in", 10, MUTE)
			continue
		var beat: Dictionary = beats.get(rig, {})
		var status := "GREEN" if bool(beat.get("green", false)) else "RED"
		var status_col := GREEN if bool(beat.get("green", false)) else RED
		_txt_right(Vector2(plot_x1 - 170, lane_y + 16), 170, "%s  ·  %s" % [status, String(beat.get("at", "")).substr(11, 8)], 10, status_col)
		# Heartbeat tick: a diamond at its timestamp.
		var beat_min := _minutes_of(String(beat.get("at", "")))
		if beat_min >= 0:
			var bx := plot_x0 + float(beat_min - RIVER_START_MIN) / float(RIVER_SPAN_MIN) * plot_w
			var by := lane_y + lane_h - 18
			var diamond := PackedVector2Array([Vector2(bx, by - 9), Vector2(bx + 7, by), Vector2(bx, by + 9), Vector2(bx - 7, by)])
			draw_colored_polygon(diamond, status_col)
		# Observer note for l9 (its heartbeat arrived via msi, not directly).
		if rig == "l9" and not String(beat.get("observer", "")).is_empty():
			_txt(Vector2(plot_x0 + 8, lane_y + 16), "via observer: " + String(beat["observer"]), 10, MUTE)
	# Event marks, stacked into the recurrence tower on the i3 lane.
	var events: Array = _feed.get("events", [])
	for i in events.size():
		var e: Dictionary = events[i]
		var lane_id := _mark_lane(e)
		var li := RIG_IDS.find(lane_id)
		if li < 0:
			continue
		var lane_y := lane_y0 + li * (lane_h + lane_gap)
		var minute := _minutes_of(String(e.get("at", "")))
		if minute < 0:
			continue
		var px := plot_x0 + float(minute - RIVER_START_MIN) / float(RIVER_SPAN_MIN) * plot_w
		var base := lane_y + lane_h - 18
		var col := _level_color(String(e.get("level", "routine")))
		var tall := 52.0 if String(e.get("level", "")) == "alarm" else 36.0
		# Stacked tower: each recurrence of the same line draws one storey.
		var same := 0
		for j in range(i + 1):
			if String(events[j].get("line", "")) == String(e.get("line", "")):
				same += 1
		var storey_h := 9.0
		for s in same:
			var storey := Rect2(px - 13, base - (s + 1) * storey_h - 2, 26, storey_h - 2)
			draw_rect(storey, Color(col, 0.95 if s == same - 1 else 0.45))
			draw_rect(storey, Color(col, 0.9), false, 1)
		if i == _selected:
			draw_arc(Vector2(px, base - same * storey_h - 14), 8, 0, TAU, 24, CYAN, 2)
		_event_hitboxes.append({"index": i, "rect": Rect2(px - 16, base - tall - 22, 32, tall + 22)})
	# Time axis.
	var axis_y := rect.end.y - 14
	for tick_min in [0, 15, 30, 45, 60, 73]:
		var tx := plot_x0 + float(tick_min) / float(RIVER_SPAN_MIN) * plot_w
		var clock := "%02d:%02d" % [(RIVER_START_MIN + tick_min) / 60, (RIVER_START_MIN + tick_min) % 60]
		_txt(Vector2(tx - 16, axis_y), clock, 10, MUTE)
	_txt(Vector2(plot_x0, rect.position.y + 52), "ONE MIND · l9-triage-drone · qwen3:4b-l9fast · 4 EVENTS · 0 ROUTINE", 10, MUTE)


func _draw_latest(rect: Rect2) -> void:
	var x := rect.position.x + 18.0
	_txt(Vector2(x, rect.position.y + 30), "LATEST THOUGHT", 15, GOLD)
	var e := _selected_event()
	if e.is_empty():
		_txt(Vector2(x, rect.position.y + 80), "NO RECORDED THOUGHT", 15, AMBER)
		return
	var level := String(e.get("level", "routine"))
	var col := _level_color(level)
	_txt(Vector2(x, rect.position.y + 56), level.to_upper(), 13, col)
	_txt_right(Vector2(rect.end.x - 218, rect.position.y + 56), 200, String(e.get("at", "")).substr(0, 19).replace("T", " ") + " UTC", 11, MUTE)
	var after := _wrap(Vector2(x, rect.position.y + 96), String(e.get("line", "")), 34, 30, INK, 3)
	_txt(Vector2(x, after + 22), String(e.get("mind", "")), 14, VIOLET)
	var ms := int(e.get("ms", -1))
	var think := ("think time %d ms" % ms) if ms >= 0 else "think time not recorded"
	_txt(Vector2(x, after + 44), "model %s  ·  %s" % [String(e.get("model", "no model")), think], 12, MUTE)
	draw_line(Vector2(x, after + 64), Vector2(rect.end.x - 18, after + 64), EDGE, 1)
	_txt(Vector2(x, after + 88), "STATED REASONS", 11, CYAN)
	var reasons: PackedStringArray = e.get("reasons", PackedStringArray())
	var ry := after + 108.0
	if reasons.is_empty():
		_txt(Vector2(x, ry), "None recorded", 12, MUTE)
	else:
		for reason in reasons:
			if ry > rect.end.y - 78:
				break
			ry = _wrap(Vector2(x, ry), "•  " + reason, 58, 12, MUTE, 2) + 4
	# Recurrence context for this exact line.
	var rows := FEED.recurrence_rows(_feed.get("events", []))
	for row in rows:
		if String(row.get("line", "")) == String(e.get("line", "")):
			var nth := 0
			for j in range(_selected + 1):
				if String(_feed["events"][j].get("line", "")) == String(e.get("line", "")):
					nth += 1
			_txt(Vector2(x, rect.end.y - 52), "RECURRENCE  %d of %d noticings of this line  ·  first %s, latest %s" % [nth, int(row["count"]), String(row["first_at"]).substr(11, 5), String(row["last_at"]).substr(11, 5)], 11, RED)
			break
	_txt(Vector2(x, rect.end.y - 30), "ATTENDING  " + String(e.get("focus", "unassigned")).to_upper() + "   ·   ← → SCRUB THROUGH THE 4 EVENTS", 11, GOLD)


func _draw_needs(rect: Rect2) -> void:
	var x := rect.position.x + 18.0
	_txt(Vector2(x, rect.position.y + 30), "WHAT NEEDS YOU  —  FROM FIXTURE DATA ONLY", 15, GOLD)
	var items := FEED.needs_you_items(_feed)
	_need_hitboxes.clear()
	var y := rect.position.y + 52.0
	for item in items:
		var y_start := y
		var status := String(item.get("status", "open"))
		var col := AMBER if status == "unverified" else RED
		_txt(Vector2(x, y + 14), String(item.get("what", "")), 13, INK, rect.size.x - 120)
		_txt_right(Vector2(rect.end.x - 118, y + 14), 100, status.to_upper(), 11, col)
		y = _wrap(Vector2(x, y + 32), "Cause: " + String(item.get("cause", "")), 92, 11, MUTE, 2) + 2
		y = _wrap(Vector2(x, y), "Move: " + String(item.get("move", "")), 92, 11, CYAN, 2) + 2
		_txt(Vector2(x, y), "Owner: " + String(item.get("owner", "")) + "   ·   Source: " + String(item.get("source", "")), 10, MUTE)
		_need_hitboxes.append({"key": String(item.get("key", "")), "rect": Rect2(rect.position.x + 6, y_start, rect.size.x - 12, y - y_start + 26)})
		y += 8.0
		draw_line(Vector2(x, y), Vector2(rect.end.x - 18, y), Color(EDGE, 0.5), 1)
		y += 6.0


func _draw_outcomes(rect: Rect2) -> void:
	var x := rect.position.x + 18.0
	_txt(Vector2(x, rect.position.y + 30), "OUTCOMES  —  WHAT HAPPENED NEXT", 15, GOLD)
	var rows := FEED.outcome_rows(_feed)
	var y := rect.position.y + 52.0
	for row in rows:
		var state := String(row.get("state", ""))
		var col := GREEN if state == "aged" else RED if state == "unresolved" else MUTE
		_txt(Vector2(x, y + 14), String(row.get("what", "")), 13, INK, rect.size.x - 36)
		y = _wrap(Vector2(x, y + 36), String(row.get("outcome", "")), 88, 12, col, 2) + 6
		_txt(Vector2(x, y), "Source: " + String(row.get("source", "")), 10, MUTE)
		y += 20.0
		draw_line(Vector2(x, y), Vector2(rect.end.x - 18, y), Color(EDGE, 0.5), 1)
		y += 8.0
	_txt(Vector2(x, rect.end.y - 16), "An alarm that ages out is kept, not deleted.", 11, MUTE)


func _draw_footer(sz: Vector2) -> void:
	var y := 816.0
	if not _error.is_empty():
		_txt(Vector2(22, y + 34), "PROVENANCE: feed failed to load — nothing shown is from live data. ESC EXIT  ·  F11 FULLSCREEN  ·  R RELOAD  ·  ? HELP", 11, MUTE)
		return
	var states := FEED.unexercised_states(_feed)
	_txt(Vector2(22, y), "FIXTURE NEVER SHOWS:", 11, GOLD)
	_wrap(Vector2(196, y), "  ·  ".join(states) + ".", 132, 11, MUTE, 2)
	_txt(Vector2(22, y + 34), "PROVENANCE: " + FEED.FREEZE_LABEL + "  ·  events.jsonl (4) + heartbeat_msi / heartbeat_i3 / heartbeat_l9  ·  no live data, no probes, no LLM calls", 11, MUTE)
	_txt(Vector2(22, y + 52), "SUGGESTIONS: any agent using this entry files fixes in docs/mindview-muse/SUGGESTIONS.md  ·  ESC EXIT  ·  F11 FULLSCREEN  ·  ← → SCRUB  ·  R RELOAD  ·  ? HELP", 11, MUTE)


func _draw_help(sz: Vector2) -> void:
	var rect := Rect2(sz.x * 0.22, sz.y * 0.24, sz.x * 0.56, sz.y * 0.52)
	draw_rect(rect, Color("#0d1c2d", 0.98))
	draw_rect(rect, GOLD, false, 2)
	_txt(rect.position + Vector2(22, 35), "THE LEDGER / INPUT MANUAL", 21, GOLD)
	var lines := [
		"← / →    Move through the recorded events",
		"Mouse    Select a river mark, or a needs-you item",
		"R    Reload the local fixture directory",
		"F11    Explicit fullscreen toggle (windowed is the default)",
		"ESC    Close immediately, even if the feed is missing or bad",
		"?    Hide this guide",
		"",
		"This view observes only. It runs nothing, restarts nothing,",
		"writes nothing. The next step is a copyable move plus an",
		"owner — the action happens elsewhere, by an agent.",
	]
	for i in lines.size():
		_txt(rect.position + Vector2(24, 75 + i * 24), lines[i], 13, MUTE)


func _txt(at: Vector2, value: String, font_size: int = 13, color: Color = INK, width: float = -1) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)


func _txt_right(at: Vector2, width: float, value: String, font_size: int = 13, color: Color = INK) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_RIGHT, width, font_size, color)


func _wrap(at: Vector2, value: String, chars: int, font_size: int, color: Color, max_lines: int = 4) -> float:
	var words := value.split(" ", false)
	var line := ""
	var y := at.y
	var used := 0
	for word in words:
		if not line.is_empty() and (line.length() + 1 + word.length()) > chars:
			_txt(Vector2(at.x, y), line, font_size, color)
			y += font_size + 5
			used += 1
			line = ""
			if used >= max_lines:
				return y
		line += (" " if not line.is_empty() else "") + word
	if not line.is_empty() and used < max_lines:
		_txt(Vector2(at.x, y), line, font_size, color)
		y += font_size + 5
	return y


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p: Vector2 = event.position
		for hit in _event_hitboxes:
			if hit["rect"].has_point(p):
				_selected = int(hit["index"])
				queue_redraw()
				accept_event()
				return
		for hit in _need_hitboxes:
			if hit["rect"].has_point(p):
				var key := String(hit["key"])
				if key == "backup-claim":
					_selected = 0
				elif key == "i3-docker":
					_selected = _feed.get("events", []).size() - 1
				queue_redraw()
				accept_event()
				return


func _capture_when_ready() -> void:
	for i in 48:
		await get_tree().process_frame
	# --shot is the only output enabled inside this renderer.
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("LEDGER_SHOT_FAILED: viewport unavailable")
		get_tree().quit(7)
		return
	var rc := img.save_png(_shot_path)
	if rc != OK:
		printerr("LEDGER_SHOT_FAILED: save error " + str(rc))
		get_tree().quit(8)
		return
	print("LEDGER_SHOT_PASS: " + _shot_path)
	get_tree().quit(0)
