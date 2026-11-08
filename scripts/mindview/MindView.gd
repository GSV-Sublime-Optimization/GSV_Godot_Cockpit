extends Control

## Mind View, slice 0: what the colony's Minds see and think, made visible.
## Left: the fleet as a map, with heartbeats flowing to xanadu and the Mind's attention ring on whatever it's thinking
## about. Right: the transcript, every thought or observation with its time, its Mind, its level and its reasons.
## Observation only: it reads one local feed file (written by mind_feed.py) and changes nothing. 0 actuators.

const DEFAULT_FEED := "C:/Users/Public/colony/mindview/feed.json"
const MAX_FEED_BYTES := 524288
const POLL_SECONDS := 2.0
const STALE_FEED_SECONDS := 90

const C_BG := Color("0b1020")
const C_PANEL := Color("121a30")
const C_TEXT := Color("d7e1f5")
const C_DIM := Color("7d8aa8")
const C_GREEN := Color("46d38a")
const C_RED := Color("ff5a5a")
const C_AMBER := Color("f5b041")
const C_SILENT := Color("6b7280")
const C_LINK := Color("2a3a66")
const LEVEL_COLOURS := {"calm": "46d38a", "watch": "f5b041", "alarm": "ff5a5a"}
# The Minds' own words (the triage drone and its evals use routine/notable/alarm) map onto the view's three colours.
const LEVEL_ALIASES := {"routine": "calm", "notable": "watch", "alert": "alarm", "critical": "alarm"}
const STATUS_COLOURS := {"green": C_GREEN, "red": C_RED, "silent": C_SILENT, "unknown": Color("3b4256")}

# Where each body sits on the map, as a fraction of the map area. xanadu is the hub: every heartbeat flows to it.
const LAYOUT := {
	"xanadu": Vector2(0.52, 0.50),
	"msi": Vector2(0.20, 0.24),
	"i3": Vector2(0.20, 0.78),
	"l9": Vector2(0.86, 0.50),
}

var feed_path := DEFAULT_FEED
var feed: Dictionary = {}
var feed_age_s := -1
var feed_error := "waiting for the first read"
var _poll := 0.0
var _t := 0.0
var _stars: Array[Vector3] = []

var _map: Control
var _transcript: RichTextLabel
var _thought: RichTextLabel
var _header: Label
var _footer: Label


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--feed="):
			feed_path = String(arg).trim_prefix("--feed=")
	var rng := RandomNumberGenerator.new()
	rng.seed = 144
	for i in 160:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0)))
	_build()
	_read_feed()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_header = Label.new()
	_header.position = Vector2(28, 14)
	_header.add_theme_font_size_override("font_size", 22)
	_header.add_theme_color_override("font_color", C_TEXT)
	add_child(_header)

	_map = Control.new()
	_map.draw.connect(_draw_map)
	add_child(_map)

	_thought = _rich(26)
	add_child(_thought)

	_transcript = _rich(17)
	_transcript.scroll_following = true
	add_child(_transcript)

	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 15)
	_footer.add_theme_color_override("font_color", C_DIM)
	add_child(_footer)
	resized.connect(_layout)
	_layout()


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = true
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", C_TEXT)
	return r


func _layout() -> void:
	var w := size.x
	var h := size.y
	var split := w * 0.60
	_map.position = Vector2(20, 60)
	_map.size = Vector2(split - 40, h * 0.66)
	_thought.position = Vector2(36, 60 + h * 0.66 + 8)
	_thought.size = Vector2(split - 70, h * 0.34 - 110)
	_transcript.position = Vector2(split + 10, 64)
	_transcript.size = Vector2(w - split - 34, h - 120)
	_footer.position = Vector2(28, h - 38)


func _process(delta: float) -> void:
	_t += delta
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		_read_feed()
	_map.queue_redraw()
	queue_redraw()


func _read_feed() -> void:
	if not FileAccess.file_exists(feed_path):
		feed_error = "no feed file at " + feed_path + " (is mind_feed.py running?)"
		_refresh_text()
		return
	var f := FileAccess.open(feed_path, FileAccess.READ)
	if f == null or f.get_length() > MAX_FEED_BYTES:
		feed_error = "feed unreadable or too large"
		_refresh_text()
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or String(parsed.get("schema", "")) != "colony.mindview-feed/v0":
		feed_error = "feed has an unexpected shape"
		_refresh_text()
		return
	feed = parsed
	feed_error = ""
	var at := String(feed.get("at", ""))
	var unix: float = float(Time.get_unix_time_from_datetime_string(at.trim_suffix("Z"))) if at != "" else 0.0
	feed_age_s = int(Time.get_unix_time_from_system() - unix) if unix > 0 else -1
	_refresh_text()


func _view_level(raw: Variant) -> String:
	var l := String(raw).to_lower()
	return String(LEVEL_ALIASES.get(l, l))


func _esc(s: Variant) -> String:
	# Text from the feed is data, never markup.
	return String(s).replace("[", "[lb]")


func _local_hhmm(stamp: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(stamp.trim_suffix("Z").split("+")[0])
	if unix <= 0:
		return "--:--"
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_string_from_unix_time(int(unix) + bias).substr(11, 5)


func _refresh_text() -> void:
	var live := feed_error == "" and feed_age_s >= 0 and feed_age_s < STALE_FEED_SECONDS
	var state := "LIVE" if live else ("STALE" if feed_error == "" else "NO FEED")
	_header.text = "GSV SUBLIME OPTIMIZATION · MIND VIEW    observation only · 0 actuators · feed %s%s" % [
		state, (" (%d s old)" % feed_age_s) if feed_age_s >= 0 else ""]
	var events: Array = feed.get("events", [])
	var b := PackedStringArray()
	b.append("[color=#7d8aa8]TRANSCRIPT · what the Minds noticed and thought, newest at the bottom[/color]\n")
	if events.is_empty():
		b.append("[color=#7d8aa8]Nothing yet. The Minds speak when something changes or on their schedule.[/color]")
	for e in events:
		var ev: Dictionary = e
		var level := _view_level(ev.get("level", "calm"))
		var col: String = LEVEL_COLOURS.get(level, "d7e1f5")
		var mind := String(ev.get("mind", "?"))
		var who := mind + ("" if ev.get("model") == null else " · " + String(ev.get("model")))
		b.append("\n[color=#7d8aa8]%s[/color]  [b][color=#%s]%s[/color][/b]  [color=#9fb3df]%s[/color]\n%s" % [
			_local_hhmm(String(ev.get("at", ""))), col, level.to_upper(), _esc(who), _esc(ev.get("line", ""))])
		var reasons: Array = ev.get("reasons", [])
		if not reasons.is_empty():
			b.append("\n[color=#7d8aa8]because: %s[/color]" % _esc(", ".join(PackedStringArray(reasons))))
		b.append("\n")
	_transcript.text = "".join(b)
	if events.is_empty():
		_thought.text = "[color=#7d8aa8]%s[/color]" % _esc(feed_error if feed_error != "" else "The Minds are quiet.")
	else:
		var last: Dictionary = events[-1]
		var lv := _view_level(last.get("level", "calm"))
		_thought.text = "[color=#7d8aa8]LATEST THOUGHT · %s · %s[/color]\n[color=#%s]%s[/color]" % [
			_esc(last.get("mind", "?")), _local_hhmm(String(last.get("at", ""))), LEVEL_COLOURS.get(lv, "d7e1f5"),
			_esc(last.get("line", ""))]
	_footer.text = "%s    ·    feed: %s    ·    source: xanadu heartbeats + Mind events + this rig's rotation" % [
		_esc(feed.get("screen", "")), feed_path]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	for s in _stars:
		var a := 0.25 + 0.25 * sin(_t * 0.6 + s.z * 9.0)
		draw_circle(Vector2(s.x * size.x, s.y * size.y), s.z * 1.4, Color(0.8, 0.85, 1.0, a))
	var split := size.x * 0.60
	draw_rect(Rect2(split, 52, size.x - split - 14, size.y - 100), C_PANEL)


func _body_pos(id: String) -> Vector2:
	var f: Vector2 = LAYOUT.get(id, Vector2(0.5, 0.5))
	return Vector2(f.x * _map.size.x, f.y * _map.size.y)


func _draw_map() -> void:
	var bodies: Dictionary = feed.get("bodies", {})
	var hub := _body_pos("xanadu")
	var font := ThemeDB.fallback_font
	# Links: every rig's heartbeat travels to xanadu. Packets flow only while that rig is reporting.
	for id in LAYOUT:
		if id == "xanadu":
			continue
		var p := _body_pos(id)
		var b: Dictionary = bodies.get(id, {})
		var status := String(b.get("status", "unknown"))
		_map.draw_line(p, hub, C_LINK, 3.0, true)
		if status == "green" or status == "red":
			for k in 3:
				var u := fmod(_t * 0.25 + k / 3.0, 1.0)
				_map.draw_circle(p.lerp(hub, u), 4.0, STATUS_COLOURS[status].lightened(0.3))
	# The Mind's attention: a slow pulsing ring around the body it's thinking about.
	var focus := String(feed.get("attention", ""))
	if focus in LAYOUT:
		var fp := _body_pos(focus)
		var r := 74.0 + 8.0 * sin(_t * 2.4)
		_map.draw_arc(fp, r, 0, TAU, 64, Color(0.6, 0.75, 1.0, 0.85), 3.0, true)
		_map.draw_arc(fp, r + 12.0, _t, _t + PI * 0.6, 24, Color(0.6, 0.75, 1.0, 0.5), 2.0, true)
		_map.draw_string(font, fp + Vector2(-48, -r - 12), "ATTENTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.8, 1.0))
	# Bodies.
	for id in LAYOUT:
		var p := _body_pos(id)
		var b: Dictionary = bodies.get(id, {})
		var status := String(b.get("status", "unknown"))
		var col: Color = STATUS_COLOURS.get(status, C_SILENT)
		var breathe := 1.0 + (0.06 * sin(_t * 3.0) if status == "green" else 0.0)
		_map.draw_circle(p, 52.0 * breathe, col.darkened(0.55))
		_map.draw_circle(p, 44.0 * breathe, col.darkened(0.15))
		_map.draw_string(font, p + Vector2(-40, 6), String(b.get("label", id)), HORIZONTAL_ALIGNMENT_CENTER, 80, 20, C_BG)
		var lines := PackedStringArray([
			"%s · %s" % [String(b.get("role", "")), status.to_upper()],
		])
		var failing: Array = b.get("failing", [])
		if not failing.is_empty():
			lines.append("failing: " + ", ".join(PackedStringArray(failing)))
		if b.get("age_s") != null:
			lines.append("heartbeat %d s ago" % int(b.get("age_s")))
		var detail := String(b.get("detail", ""))
		if detail != "":
			lines.append(detail)
		for i in lines.size():   # captions sit below the attention ring's widest reach (~96 px)
			_map.draw_string(font, p + Vector2(-230, 104 + i * 19), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 460, 14,
				C_RED if lines[i].begins_with("failing") else C_DIM)
