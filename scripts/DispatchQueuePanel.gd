extends PanelContainer
class_name DispatchQueuePanel

## DispatchQueuePanel — Colony task dispatch queue (:9002).
## Shows open/claimed/done tasks from kilocore-dispatch.

const DISPATCH_URL := "http://localhost:9002/queue"

var _list:   VBoxContainer
var _header: Label

static func create() -> DispatchQueuePanel:
	return DispatchQueuePanel.new()

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "📋 Dispatch Queue — :9002"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	_header = Label.new()
	_header.text = "…"
	_header.modulate = Color(0.6, 0.6, 0.6)
	hdr.add_child(_header)

	var refresh_btn := Button.new()
	refresh_btn.text = "↺"
	refresh_btn.pressed.connect(refresh)
	hdr.add_child(refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	var legend := Label.new()
	legend.text = "yellow=open  cyan=claimed  green=done  gray=other"
	legend.modulate = Color(0.4, 0.4, 0.4)
	root.add_child(legend)

	refresh()

func refresh() -> void:
	for c in _list.get_children(): c.queue_free()
	_header.text = "probing…"

	var raw := _ps_get(DISPATCH_URL)
	var tasks: Variant = null
	if not raw.is_empty():
		var parser := JSON.new()
		if parser.parse(raw) == OK:
			tasks = parser.data

	# Dispatch may return {"queue": [...]} or a bare array
	if typeof(tasks) == TYPE_DICTIONARY:
		tasks = tasks.get("queue", tasks.get("tasks", tasks.get("items", [])))
	if typeof(tasks) != TYPE_ARRAY:
		_header.text = "DOWN"
		var lbl := Label.new()
		lbl.text = "  dispatch :9002 not reachable"
		lbl.modulate = Color(1.0, 0.4, 0.4)
		_list.add_child(lbl)
		return

	_header.text = "%d tasks" % tasks.size()
	if tasks.is_empty():
		var lbl := Label.new()
		lbl.text = "  (queue empty)"
		lbl.modulate = Color(0.5, 0.5, 0.5)
		_list.add_child(lbl)
		return

	for task in tasks:
		if typeof(task) != TYPE_DICTIONARY: continue
		var status:   String = str(task.get("status",      "?"))
		var category: String = str(task.get("category",    "?"))
		var assigned: String = str(task.get("assigned_to", "?"))
		var issue:    String = str(task.get("issue",        task.get("id", "?")))

		var row := HBoxContainer.new()
		_list.add_child(row)

		var dot := Label.new()
		dot.text = "◆ "
		dot.modulate = _status_color(status)
		dot.custom_minimum_size = Vector2(18, 0)
		row.add_child(dot)

		var lbl := Label.new()
		lbl.text = "[%s] %s → %s  %s" % [status, category, assigned, issue.substr(0, 80)]
		lbl.modulate = _status_color(status)
		lbl.clip_text = true
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

func _status_color(status: String) -> Color:
	match status.to_lower():
		"open":    return Color(1.0, 1.0, 0.3)
		"claimed": return Color(0.3, 1.0, 1.0)
		"done":    return Color(0.3, 1.0, 0.3)
		_:         return Color(0.6, 0.6, 0.6)

func _ps_get(url: String) -> String:
	var output: Array = []
	var code: int
	if OS.has_feature("windows"):
		var args := ["-NoProfile", "-Command",
			"try{(Invoke-WebRequest '%s' -UseBasicParsing -TimeoutSec 4).Content}catch{''}" % url]
		code = OS.execute("pwsh", args, output, true, false)
		if code != 0:
			output.clear()
			code = OS.execute("powershell", args, output, true, false)
	else:
		code = OS.execute("curl", ["--fail", "--silent", "--max-time", "4", url], output, true, false)
	if code != 0:
		return ""
	var result := ""
	for line in output:
		result += str(line)
	return result.strip_edges()
