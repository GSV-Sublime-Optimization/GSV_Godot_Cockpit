extends Control

## ΞNuSyQ-Prime / Cognitive Loom
## One Mind View bakeoff entry; intentionally not an agent runtime.
## Only source-attributed observations, never private internal thought.
const CONTRACT = preload("res://tools/prime_mind/FeedContract.gd")
const BG = Color("#080e18")
const PANEL = Color("#111c2b")
const EDGE = Color("#26374b")
const INK = Color("#e5f3fc")
const MUTE = Color("#879caf")
const CYAN = Color("#54e4db")
const VIOLET = Color("#b4a3ff")
const AMBER = Color("#f8be6c")
const RED = Color("#ff738a")
const GREEN = Color("#69d7b0")
const RIG_IDS = ["msi", "i3", "l9", "xanadu"]
const RIG_NAMES = ["MSI", "I3", "L9", "XANADU"]

var _feed: Dictionary = {}
var _selected := -1
var _mind_filter := "all"
var _lens := 0
var _replaying := false
var _phase := 0.0
var _frame_budget := 0.0
var _play_clock := 0.0
var _is_fixture := true
var _feed_path := "res://tests/fixtures/prime_mind_feed.json"
var _error := ""
var _shot_path := ""
var _frame_number := 0
var _tick_hitboxes: Array[Rect2] = []
var _mind_hitboxes: Array[Dictionary] = []
var _lens_hitboxes: Array[Rect2] = []
var _rig_hitboxes: Array[Dictionary] = []
var _focus_override := ""
var _show_help := false
var _font: Font
var _last_mtime := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	Engine.max_fps = 24
	# Only render frames when the canvas asks for it (#14 idle budget: <=5% of one core).
	OS.low_processor_usage_mode = true
	get_window().mode = Window.MODE_WINDOWED
	get_window().always_on_top = false
	_parse_args()
	_load_snapshot()
	if not _is_fixture:
		var timer := Timer.new()
		timer.wait_time = 15.0
		timer.autostart = true
		timer.timeout.connect(_load_snapshot)
		add_child(timer)
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
			_feed_path = arg.trim_prefix("--fixture=")
			_is_fixture = true
		elif arg.begins_with("--feed="):
			_feed_path = arg.trim_prefix("--feed=")
			_is_fixture = false
		elif arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg == "--background":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		elif arg == "--no-animate":
			Engine.max_fps = 10
	# Snapshot import remains strictly local. No HTTP, ssh, API, shell or tokens.
	if _feed_path.begins_with("http:") or _feed_path.begins_with("https:"):
		_error = "Remote URLs are not a data source"
		_feed_path = ""

func _load_snapshot() -> void:
	if _feed_path.is_empty():
		return
	if not FileAccess.file_exists(_feed_path):
		_error = "No local feed. Source is unavailable."
		if not _is_fixture:
			_feed.clear()
		queue_redraw()
		return
	var file := FileAccess.open(_feed_path, FileAccess.READ)
	if file == null:
		_error = "Feed is not readable."
		queue_redraw()
		return
	if file.get_length() > CONTRACT.MAX_BYTES:
		file.close()
		_error = "Feed exceeds acceptance budget"
		queue_redraw()
		return
	var result: Dictionary = CONTRACT.parse_text(
		file.get_as_text(), "PINNED_SHARED_SNAPSHOT" if _is_fixture else "LOCAL_UNVERIFIED"
	)
	file.close()
	if not result.get("ok", false):
		_error = String(result.get("reason", "Malformed source observation"))
		queue_redraw()
		return
	var old_stamp := String(_feed.get("source_at", ""))
	_feed = result
	_error = ""
	if _selected < 0 or old_stamp != String(_feed["source_at"]):
		_choose_latest_mind()
	queue_redraw()

func _choose_latest_mind() -> void:
	var events: Array = _feed.get("events", [])
	_selected = events.size() - 1
	for i in range(events.size() - 1, -1, -1):
		if events[i].get("identity") == "model_summary":
			_selected = i
			break

func _process(delta: float) -> void:
	_frame_budget += delta
	_play_clock += delta
	if _replaying and _play_clock > 2.4:
		_play_clock = 0.0
		_step(1)
	if _frame_budget < 0.105:
		return
	_phase += minf(_frame_budget, 0.2)
	_frame_budget = 0.0
	queue_redraw()

func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), BG)
	_draw_grid(sz)
	if sz.x < 930.0 or sz.y < 540.0:
		_txt(Vector2(26, 38), "COGNITIVE LOOM", 23, CYAN)
		_wrap(Vector2(26, 90), "Resize to at least 930 × 540 to inspect the complete fleet and thought timeline.", 38, 17, MUTE)
		return
	var bottom := sz.y - 166
	var left := Rect2(18, 86, 248, bottom - 98)
	var core := Rect2(278, 86, sz.x - 579, bottom - 98)
	var right := Rect2(sz.x - 289, 86, 270, bottom - 98)
	var tape := Rect2(18, sz.y - 155, sz.x - 36, 139)
	_draw_header(sz)
	_draw_panel(left)
	_draw_panel(core)
	_draw_panel(right)
	_draw_panel(tape)
	_draw_minds(left)
	_draw_core(core)
	_draw_inspector(right)
	_draw_tape(tape)
	if _show_help:
		_draw_help(sz)

func _draw_grid(sz: Vector2) -> void:
	for x in range(0, int(sz.x), 45):
		draw_line(Vector2(x, 0), Vector2(x, sz.y), Color("#15263b", 0.3), 1)
	for y in range(0, int(sz.y), 45):
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color("#15263b", 0.3), 1)

func _draw_header(sz: Vector2) -> void:
	_txt(Vector2(22, 32), "Ξ  N U S Y Q", 22, INK)
	_txt(Vector2(194, 32), "P R I M E   /   C O G N I T I V E   L O O M", 14, CYAN)
	_txt(Vector2(22, 59), "THOUGHTS AS EVIDENCE   •   ATTENTION AS GEOMETRY   •   ZERO ACTUATORS", 11, MUTE)
	var state := CONTRACT.source_state(_feed, _is_fixture)
	if not _error.is_empty():
		state = "INVALID: " + _error
	var state_color := AMBER if state != "OBSERVED" else GREEN
	_txt(Vector2(sz.x - 420, 31), state, 15, state_color, 397)
	_txt(Vector2(sz.x - 420, 57), "ESC EXIT  ·  SPACE REPLAY  ·  ← → SCRUB  ·  ? HELP", 11, MUTE)
	draw_line(Vector2(18, 72), Vector2(sz.x - 18, 72), EDGE, 1)

func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL)
	draw_rect(rect, EDGE, false, 1)
	draw_line(rect.position + Vector2(1, 1), rect.position + Vector2(minf(rect.size.x, 50), 1), CYAN.darkened(0.2), 2)

func _draw_minds(rect: Rect2) -> void:
	_mind_hitboxes.clear()
	_txt(rect.position + Vector2(16, 31), "MINDS / SIGNAL ROUTING", 14, CYAN)
	_txt(rect.position + Vector2(16, 56), "Select source • filter evidence", 11, MUTE)
	var events: Array = _feed.get("events", [])
	var options := [
		{"id": "all", "title": "ALL INPUTS", "subtitle": "%d retained signals" % events.size()},
		{"id": "models", "title": "MODEL THOUGHTS", "subtitle": "Reported summaries only"},
		{"id": "observer", "title": "SYSTEM OBSERVER", "subtitle": "Rules, not a model"}
	]
	var y := rect.position.y + 77.0
	for option in options:
		var hit := Rect2(rect.position.x + 12, y, rect.size.x - 24, 54)
		var chosen: bool = option["id"] == _mind_filter
		if chosen:
			draw_rect(hit, Color("#20364a"))
			draw_rect(hit, CYAN.darkened(0.2), false, 1)
		_txt(hit.position + Vector2(12, 20), option["title"], 13, INK if chosen else MUTE)
		_txt(hit.position + Vector2(12, 39), option["subtitle"], 10, CYAN if chosen else MUTE)
		_mind_hitboxes.append({"id": option["id"], "rect": hit})
		y += 60.0
	y += 14.0
	_txt(Vector2(rect.position.x + 16, y), "CURRENT OBSERVED MINDS", 11, AMBER)
	y += 22.0
	var names: Dictionary = {}
	for e in events:
		if e["identity"] == "model_summary":
			names[e["mind"]] = true
	if names.is_empty():
		_txt(Vector2(rect.position.x + 16, y + 8), "No model observations", 13, MUTE)
	else:
		for name in names.keys():
			_txt(Vector2(rect.position.x + 16, y + 12), "◉  " + String(name), 12, VIOLET, rect.size.x - 28)
			y += 27.0
	var bottom := rect.end.y - 86
	_txt(Vector2(rect.position.x + 16, bottom), "SENSORIAL TRUTH", 11, CYAN)
	_wrap(Vector2(rect.position.x + 16, bottom + 15), "An observer line is not thinking. A model summary is not private reasoning. Silent data stays silent.", 31, 11, MUTE)

func _rig_positions(rect: Rect2) -> Dictionary:
	var c := rect.position + Vector2(rect.size.x * 0.50, rect.size.y * 0.45)
	return {
		"msi": rect.position + Vector2(rect.size.x * 0.19, rect.size.y * 0.45),
		"i3": rect.position + Vector2(rect.size.x * 0.80, rect.size.y * 0.45),
		"l9": rect.position + Vector2(rect.size.x * 0.50, rect.size.y * 0.18),
		"xanadu": rect.position + Vector2(rect.size.x * 0.50, rect.size.y * 0.72),
		"kernel": c
	}

func _selected_event() -> Dictionary:
	var events: Array = _feed.get("events", [])
	if _selected < 0 or _selected >= events.size():
		return {}
	return events[_selected]

func _draw_core(rect: Rect2) -> void:
	_rig_hitboxes.clear()
	_lens_hitboxes.clear()
	_txt(rect.position + Vector2(18, 31), "ATTENTION FIELD", 15, CYAN)
	var labels := ["1 · PULSE", "2 · CAUSES", "3 · VITALS"]
	var lx := rect.end.x - 250.0
	for i in 3:
		var hit := Rect2(lx + i * 83, rect.position.y + 11, 77, 29)
		_lens_hitboxes.append(hit)
		draw_rect(hit, Color("#29445c") if _lens == i else Color("#162536"))
		draw_rect(hit, CYAN if _lens == i else EDGE, false, 1)
		_txt(hit.position + Vector2(7, 19), labels[i], 10, INK if _lens == i else MUTE, 73)
	var pos := _rig_positions(rect)
	var center: Vector2 = pos["kernel"]
	var evidence := _selected_event()
	var attention := _focus_override if not _focus_override.is_empty() else String(evidence.get("focus", ""))
	for n in [0, 1, 2, 3]:
		var radius := 34.0 + float(n) * 24.0
		draw_arc(center, radius, 0, TAU, 60, Color(CYAN, 0.12 + float(n) * 0.035), 1)
	var phase := _phase * 0.6
	draw_arc(center, 69, phase, phase + PI * 0.6, 32, Color(CYAN, 0.7), 2)
	draw_arc(center, 94, -phase * 0.7, -phase * 0.7 + PI * 0.45, 30, Color(VIOLET, 0.53), 1.5)
	for id in RIG_IDS:
		var p: Vector2 = pos[id]
		var focused: bool = attention == id
		var status := _effective_rig_status(id)
		var node_color := _health_color(status)
		var weight := 2.2 if focused else 1.0
		draw_line(center, p, Color(node_color, 0.6 if focused else 0.18), weight)
		if focused:
			for k in 3:
				draw_arc(p, 26 + k * 11 + sin(_phase * 2.0) * 3, 0, TAU, 48, Color(CYAN, 0.34 / float(k + 1)), 2)
		draw_circle(p, 31 if focused else 26, Color(node_color, 0.08))
		draw_circle(p, 20 if focused else 17, Color(node_color, 0.15))
		draw_arc(p, 20, 0, TAU, 32, node_color, 2 if focused else 1)
		draw_circle(p, 4, node_color)
		var label: String = RIG_NAMES[RIG_IDS.find(id)]
		_txt(p + Vector2(-32, 39), label, 13, INK if focused else MUTE, 80)
		_txt(p + Vector2(-32, 53), status.to_upper(), 9, node_color, 80)
		_rig_hitboxes.append({"id": id, "rect": Rect2(p - Vector2(33, 33), Vector2(66, 76))})
	draw_circle(center, 30, Color("#1b3843"))
	draw_arc(center, 30, 0, TAU, 48, CYAN, 2)
	draw_circle(center, 5, CYAN)
	_txt(center + Vector2(-26, 50), "MIND", 12, CYAN)
	# The wave is a visualization of the recorded event's presence/level,
	# not a learned embedding, hidden thought vector, or neural activation.
	if _lens == 0:
		var waveform := PackedVector2Array()
		var high := rect.end.y - 66.0
		var line := String(evidence.get("line", ""))
		var energy := clampf(float(line.length()) / 130.0, 0.2, 1.0)
		for j in range(90):
			var fx := float(j) / 89.0
			var amplitude := sin(fx * 10.0 * PI + phase * 2.0) * 13.0 * energy
			amplitude += sin(fx * 29.0 * PI - phase) * 3.0 * energy
			waveform.append(Vector2(rect.position.x + 22 + fx * (rect.size.x - 44), high + amplitude))
		draw_polyline(waveform, Color(CYAN, 0.68), 1.7)
		_txt(rect.position + Vector2(20, rect.size.y - 19), "RECORDED SIGNAL • ILLUSTRATIVE WAVE, NOT NEURAL STATE", 10, MUTE)
	elif _lens == 1:
		var reasons: PackedStringArray = evidence.get("reasons", PackedStringArray())
		var start := rect.position + Vector2(24, rect.size.y - 72)
		_txt(start, "REASON LINKS  /  SOURCE-DECLARED ONLY", 11, AMBER)
		for i in mini(2, reasons.size()):
			_txt(start + Vector2(0, 17 + i * 15), "· " + reasons[i], 11, MUTE, rect.size.x - 43)
	else:
		_txt(rect.position + Vector2(20, rect.size.y - 68), "VITALS LENS  /  HEARTBEAT STATE + CAPTURE AGE", 11, AMBER)
		var rows := _vitals_lines()
		var col_w := (rect.size.x - 40.0) / 2.0
		for i in rows.size():
			var at := rect.position + Vector2(20 + (i % 2) * col_w, rect.size.y - 48 + (i / 2) * 17)
			var tint := CYAN if _focus_override == RIG_IDS[i] else MUTE
			_txt(at, rows[i], 11, tint, col_w - 8)
	# Source integrity marker deliberately visible near the field.
	_txt(rect.position + Vector2(18, 55), "4 RIGS · 0 ACTUATORS · SELECT A NODE TO INSPECT", 10, MUTE)

## One line per rig for the vitals lens: reported status, heartbeat age at
## capture and failing checks, straight from the feed's body map.
func _vitals_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var bodies: Dictionary = _feed.get("bodies", {})
	for i in RIG_IDS.size():
		var id: String = RIG_IDS[i]
		var b: Dictionary = bodies.get(id, {})
		var age: int = int(b.get("age_s", -1))
		var failing: PackedStringArray = b.get("failing", PackedStringArray())
		var parts := [RIG_NAMES[i], _effective_rig_status(id).to_upper(),
			("hb %d s old at capture" % age) if age >= 0 else "no heartbeat age",
			("failing: " + ", ".join(failing)) if not failing.is_empty() else "no failing checks"]
		out.append("  ·  ".join(parts))
	return out

func _effective_rig_status(id: String) -> String:
	if not _feed.get("ok", false):
		return "unknown"
	# Do not retain a green rig ornament when the *local source* expired.
	if not _is_fixture and (
			not _error.is_empty()
			or CONTRACT.source_state(_feed, false) != "OBSERVED"):
		return "stale"
	return String(_feed.get("bodies", {}).get(id, {}).get("status", "unknown"))

func _health_color(state: String) -> Color:
	match state:
		"green": return GREEN
		"red": return RED
		"silent", "stale": return AMBER
		_: return MUTE

func _draw_inspector(rect: Rect2) -> void:
	var x := rect.position.x + 14.0
	var y := rect.position.y
	_txt(Vector2(x, y + 30), "THOUGHT / EVIDENCE", 14, CYAN)
	var e := _selected_event()
	if e.is_empty():
		_txt(Vector2(x, y + 67), "NO RECORDED THOUGHT", 15, AMBER)
		_wrap(Vector2(x, y + 91), "No event is available to inspect. The interface does not fabricate one.", 31, 12, MUTE)
		return
	var level := String(e.get("level", "routine"))
	var c := RED if level == "alarm" else AMBER if level == "notable" else CYAN
	_txt(Vector2(x, y + 60), level.to_upper() + "  /  " + String(e.get("identity", "")).to_upper(), 12, c, rect.size.x - 24)
	_txt(Vector2(x, y + 82), String(e.get("mind", "unknown")), 15, INK, rect.size.x - 25)
	_txt(Vector2(x, y + 102), String(e.get("model", "NO MODEL") if e.get("model") != null else "DETERMINISTIC OBSERVER"), 11, VIOLET, rect.size.x - 25)
	_txt(Vector2(x, y + 122), String(e.get("at", "")).substr(0, 19).replace("T", "  ") + " UTC", 10, MUTE)
	draw_line(Vector2(x, y + 137), Vector2(rect.end.x - 12, y + 137), EDGE)
	_txt(Vector2(x, y + 159), "RECORDED SUMMARY", 11, AMBER)
	var summary: String = String(e.get("line", ""))
	var after := _wrap(Vector2(x, y + 177), summary, 27, 13, INK, 5)
	var why_y := minf(after + 18, rect.end.y - 110)
	_txt(Vector2(x, why_y), "STATED REASONS", 11, CYAN)
	var reasons: PackedStringArray = e.get("reasons", PackedStringArray())
	if reasons.is_empty():
		_txt(Vector2(x, why_y + 20), "None recorded", 12, MUTE)
	else:
		var offset := why_y + 18.0
		for reason in reasons.slice(0, 3):
			offset = _wrap(Vector2(x, offset), "• " + reason, 29, 11, MUTE, 2) + 6
	_txt(Vector2(x, rect.end.y - 40), "ATTENDING   " + String(e.get("focus", "unassigned")).to_upper(), 12, CYAN)
	_txt(Vector2(x, rect.end.y - 20), "No hidden reasoning is inferred.", 10, MUTE)

func _filtered_indices() -> Array[int]:
	var all: Array = _feed.get("events", [])
	var out: Array[int] = []
	for i in all.size():
		var label := String(all[i].get("identity", "monitor"))
		if _mind_filter == "models" and label != "model_summary":
			continue
		if _mind_filter == "observer" and label != "monitor":
			continue
		out.append(i)
	return out

func _draw_tape(rect: Rect2) -> void:
	_tick_hitboxes.clear()
	_txt(rect.position + Vector2(15, 25), "THOUGHT TAPE / CAUSAL SEQUENCER", 15, CYAN)
	_txt(rect.position + Vector2(390, 25), "←  →  SCRUB    SPACE  PLAY / PAUSE", 11, MUTE)
	_txt(Vector2(rect.end.x - 152, rect.position.y + 25), "SPACE : " + ("PLAYING" if _replaying else "PAUSED"), 11, AMBER)
	var indices := _filtered_indices()
	if indices.is_empty():
		_txt(rect.position + Vector2(17, 80), "No events in this lens. Source uncertainty is preserved.", 13, MUTE)
		return
	var base_x := rect.position.x + 19.0
	var span := rect.size.x - 38.0
	var cell := span / float(indices.size())
	var baseline := rect.end.y - 42.0
	draw_line(Vector2(base_x, baseline), Vector2(base_x + span, baseline), EDGE, 1)
	for j in indices.size():
		var index := indices[j]
		var e: Dictionary = _feed["events"][index]
		var px := base_x + (j + 0.5) * cell
		var col := RED if e["level"] == "alarm" else VIOLET if e["identity"] == "model_summary" else AMBER
		var bar_height := 36.0 if e["identity"] == "model_summary" else 23.0
		if e["level"] == "alarm":
			bar_height += 10
		var selected := index == _selected
		draw_rect(Rect2(px - maxf(2, cell * 0.18), baseline - bar_height, maxf(4, cell * 0.36), bar_height),
			Color(col, 0.9 if selected else 0.5))
		if selected:
			draw_arc(Vector2(px, baseline - bar_height - 9), 7, 0, TAU, 24, CYAN, 2)
			draw_line(Vector2(px, baseline - bar_height - 24), Vector2(px, baseline - bar_height - 10), CYAN, 1.3)
		var hit := Rect2(base_x + j * cell, rect.position.y + 35, cell, rect.size.y - 48)
		_tick_hitboxes.append(hit)
		if j % maxi(1, int(ceil(float(indices.size()) / 9.0))) == 0:
			var clock := String(e.get("at", "")).substr(11, 5)
			_txt(Vector2(px - 16, baseline + 19), clock, 10, MUTE)
	_txt(rect.position + Vector2(17, rect.size.y - 10), "GOLD = MONITOR    VIOLET = MODEL SUMMARY    RED = ALARM    BLUE RING = SELECTED", 10, MUTE)

func _draw_help(sz: Vector2) -> void:
	var rect := Rect2(sz.x * 0.20, sz.y * 0.22, sz.x * 0.60, sz.y * 0.56)
	draw_rect(rect, Color("#0d1c2d", 0.98))
	draw_rect(rect, CYAN, false, 2)
	_txt(rect.position + Vector2(22, 35), "COGNITIVE LOOM / INPUT MANUAL", 21, CYAN)
	var lines := [
		"← / →    Move through recorded events",
		"SPACE    Replay the event tape, locally only",
		"1 / 2 / 3    Pulse, reasons, or fleet-vitals lens",
		"M    Cycle: all / model summaries / observers",
		"Mouse    Select rig, event or Mind source",
		"R    Reload the local snapshot",
		"F11    Explicit fullscreen toggle",
		"ESC    Close immediately, even if source unavailable",
		"?    Hide this guide",
		"",
		"Replay is a presentation tool, not execution.",
		"Mind summaries do not reveal hidden private reasoning."
	]
	for i in lines.size():
		_txt(rect.position + Vector2(24, 75 + i * 24), lines[i], 13, MUTE)

func _txt(at: Vector2, value: String, font_size: int = 13, color: Color = INK, width: float = -1) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

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
		for option in _mind_hitboxes:
			if option["rect"].has_point(p):
				_mind_filter = String(option["id"])
				_focus_override = ""
				_select_within_filter()
				queue_redraw()
				accept_event()
				return
		for i in _lens_hitboxes.size():
			if _lens_hitboxes[i].has_point(p):
				_lens = i
				queue_redraw()
				accept_event()
				return
		for rig in _rig_hitboxes:
			if rig["rect"].has_point(p):
				_focus_override = String(rig["id"])
				queue_redraw()
				accept_event()
				return
		var indices := _filtered_indices()
		for i in _tick_hitboxes.size():
			if _tick_hitboxes[i].has_point(p) and i < indices.size():
				_selected = indices[i]
				_focus_override = ""
				_replaying = false
				queue_redraw()
				accept_event()
				return

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# '?' arrives as Shift+Slash on most layouts, so match the character too.
	if event.keycode == KEY_F1 or event.keycode == KEY_QUESTION or event.unicode == 0x3F:
		_show_help = not _show_help
		queue_redraw()
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit(0)
		KEY_LEFT:
			_step(-1)
		KEY_RIGHT:
			_step(1)
		KEY_SPACE:
			_replaying = not _replaying
			_play_clock = 0
		KEY_1, KEY_2, KEY_3:
			_lens = event.keycode - KEY_1
		KEY_M:
			var filters := ["all", "models", "observer"]
			_mind_filter = filters[(filters.find(_mind_filter) + 1) % filters.size()]
			_select_within_filter()
		KEY_R:
			_load_snapshot()
		KEY_F11:
			get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	queue_redraw()

## Keep the inspector on an event the active filter actually shows.
func _select_within_filter() -> void:
	var visible := _filtered_indices()
	if visible.has(_selected):
		return
	_selected = visible[visible.size() - 1] if not visible.is_empty() else -1
	_focus_override = ""

func _step(direction: int) -> void:
	var visible := _filtered_indices()
	if visible.is_empty():
		return
	var current := visible.find(_selected)
	_selected = visible[posmod(current + direction, visible.size())]
	_focus_override = ""
	queue_redraw()

func _capture_when_ready() -> void:
	for i in 48:
		await get_tree().process_frame
	# --shot is the only output enabled inside this renderer.
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("PRIME_SHOT_FAILED: viewport unavailable")
		get_tree().quit(7)
		return
	var rc := img.save_png(_shot_path)
	if rc != OK:
		printerr("PRIME_SHOT_FAILED: save error " + str(rc))
		get_tree().quit(8)
		return
	print("PRIME_SHOT_PASS: " + _shot_path)
	get_tree().quit(0)
