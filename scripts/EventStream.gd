extends PanelContainer
class_name EventStream

## EventStream — Live colony event feed.
## Tails C:/GSV/talkback/events.jsonl and colours events by kind.
## Zero bridge overhead: reads file directly via FileAccess.

const EVENTS_FILE := "C:/GSV/talkback/events.jsonl"
const MAX_LINES   := 200
const POLL_SEC    := 3.0

var _box:    RichTextLabel
var _paused: bool = false
var _last_size: int = 0
var _timer:  Timer

static func create() -> EventStream:
	return EventStream.new()

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# Header
	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "⚡ Event Stream — Colony Nervous System"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	var pause_btn := Button.new()
	pause_btn.text = "⏸"
	pause_btn.toggled.connect(func(on): _paused = on)
	hdr.add_child(pause_btn)

	var clear_btn := Button.new()
	clear_btn.text = "🧹"
	clear_btn.pressed.connect(func(): _box.clear())
	hdr.add_child(clear_btn)

	var reload_btn := Button.new()
	reload_btn.text = "↺"
	reload_btn.pressed.connect(_full_reload)
	hdr.add_child(reload_btn)

	# Event box
	_box = RichTextLabel.new()
	_box.bbcode_enabled = true
	_box.scroll_following = true
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_box)

	# Legend
	var legend := Label.new()
	legend.text = "cyan=service  green=fix  yellow=signal  red=error  white=other"
	legend.modulate = Color(0.45, 0.45, 0.45)
	root.add_child(legend)

	_full_reload()

	_timer = Timer.new()
	_timer.wait_time = POLL_SEC
	_timer.autostart = true
	_timer.timeout.connect(_poll)
	add_child(_timer)

func _full_reload() -> void:
	_box.clear()
	_last_size = 0
	if not FileAccess.file_exists(EVENTS_FILE):
		_box.append_text("[color=yellow](no events file yet: %s)[/color]\n" % EVENTS_FILE)
		return
	var f := FileAccess.open(EVENTS_FILE, FileAccess.READ)
	if not f:
		_box.append_text("[color=red]cannot open events file[/color]\n")
		return
	# Load tail of file — last MAX_LINES lines
	var lines: PackedStringArray = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			lines.append(line)
	_last_size = f.get_length()
	f.close()
	# Show tail
	var start := maxi(0, lines.size() - MAX_LINES)
	for i in range(start, lines.size()):
		_append_event(lines[i])

func _poll() -> void:
	if _paused:
		return
	if not FileAccess.file_exists(EVENTS_FILE):
		return
	var f := FileAccess.open(EVENTS_FILE, FileAccess.READ)
	if not f:
		return
	var size := f.get_length()
	if size <= _last_size:
		f.close()
		return
	f.seek(_last_size)
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			_append_event(line)
	_last_size = size
	f.close()

func _append_event(line: String) -> void:
	var parser := JSON.new()
	var parsed: Variant = null
	if parser.parse(line) == OK:
		parsed = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		_box.append_text("[color=gray]" + line.substr(0, 120) + "[/color]\n")
		return

	var ts:   String = str(parsed.get("ts", parsed.get("timestamp", ""))).substr(11, 8)
	var kind: String = str(parsed.get("kind", parsed.get("type", parsed.get("event", "event"))))
	var msg:  String = str(parsed.get("msg", parsed.get("message", parsed.get("data", line)))).substr(0, 120)

	var color := _color_for_kind(kind)
	_box.append_text("[color=gray]%s[/color] [color=%s]%-16s[/color] %s\n" % [ts, color, kind, msg])

func _color_for_kind(kind: String) -> String:
	kind = kind.to_lower()
	if kind.contains("service") or kind.contains("flip") or kind.contains("health"):
		return "cyan"
	if kind.contains("fix") or kind.contains("patch") or kind.contains("commit"):
		return "green"
	if kind.contains("signal") or kind.contains("chug") or kind.contains("harvest"):
		return "yellow"
	if kind.contains("error") or kind.contains("fail") or kind.contains("down"):
		return "red"
	if kind.contains("sprint") or kind.contains("cycle"):
		return "magenta"
	return "white"
