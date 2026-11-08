extends PanelContainer
class_name ReceiptViewer

## ReceiptViewer — tails receipts.jsonl and live-sprint.log from the colony.
## Agents are nodes. Receipts are memory. This is the audit trail.

const RECEIPT_PATHS := [
	"C:/GSV/state/autonomous-sprints/current",
	"C:/dev/active/Kilo_Core/state/cultivation/reports",
]
const SPRINT_INDEX := "C:/GSV/state/autonomous-sprints/current/latest.json"

var _label: RichTextLabel
var _refresh_btn: Button
var _tail_lines: int = 30

static func receipt_dirs() -> Array[String]:
	var paths: Array[String] = []
	var sprint := OS.get_environment("GSV_SPRINT_CURRENT_DIR").strip_edges()
	var reports := OS.get_environment("GSV_KILOCORE_REPORTS_DIR").strip_edges()
	if not sprint.is_empty():
		paths.append(sprint)
	elif OS.has_feature("windows"):
		paths.append(RECEIPT_PATHS[0])
	if not reports.is_empty():
		paths.append(reports)
	elif OS.has_feature("windows"):
		paths.append(RECEIPT_PATHS[1])
	return paths

static func sprint_index_path() -> String:
	var configured := OS.get_environment("GSV_SPRINT_INDEX").strip_edges()
	if not configured.is_empty():
		return configured
	var sprint := OS.get_environment("GSV_SPRINT_CURRENT_DIR").strip_edges()
	if not sprint.is_empty():
		return sprint.path_join("latest.json")
	return SPRINT_INDEX if OS.has_feature("windows") else ""

func _ready() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "📜 Receipts / Audit Trail"
	title.add_theme_font_size_override("font_size", 15)
	hdr.add_child(title)

	_refresh_btn = Button.new()
	_refresh_btn.text = "↺"
	_refresh_btn.pressed.connect(refresh)
	hdr.add_child(_refresh_btn)

	_label = RichTextLabel.new()
	_label.scroll_following = true
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size = Vector2(0, 180)
	root.add_child(_label)

	refresh()

func refresh() -> void:
	_label.clear()

	# Sprint index
	var index_path := sprint_index_path()
	var f: FileAccess = null
	if not index_path.is_empty() and FileAccess.file_exists(index_path):
		f = FileAccess.open(index_path, FileAccess.READ)
	if f:
		var raw := f.get_as_text()
		f.close()
		var json := JSON.new()
		if json.parse(raw) == OK:
			var d = json.get_data()
			if typeof(d) == TYPE_DICTIONARY:
				_append("[color=cyan]SPRINT CYCLE %s[/color]  %d UP / %d DOWN" % [
					str(d.get("cycle", "?")),
					int(d.get("services_up", 0)),
					int(d.get("services_down", 0))
				])
				_append("  next: " + str(d.get("next_best", "")))
				_append("")

	# Scan for receipts.jsonl files
	var found_any := false
	for dir_path in receipt_dirs():
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname == "receipts.jsonl":
				_read_jsonl(dir_path + "/" + fname)
				found_any = true
			fname = dir.get_next()
		dir.list_dir_end()

		# Also scan one level deep (sprint timestamp dirs)
		dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			fname = dir.get_next()
			while fname != "":
				if dir.current_is_dir() and fname != "." and fname != "..":
					var sub: String = dir_path + "/" + fname + "/receipts/receipts.jsonl"
					if FileAccess.file_exists(sub):
						_read_jsonl(sub)
						found_any = true
				fname = dir.get_next()
			dir.list_dir_end()

	if not found_any:
		_append("[color=gray](no receipts found yet)[/color]")

func _read_jsonl(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return

	var lines: Array[String] = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			lines.append(line)
	f.close()

	_append("[color=yellow]── %s ──[/color]" % path.get_file())
	var tail := lines.slice(maxi(0, lines.size() - _tail_lines))
	for line in tail:
		var json := JSON.new()
		if json.parse(line) == OK:
			var d = json.get_data()
			if typeof(d) == TYPE_DICTIONARY:
				var kind: String = str(d.get("kind", "?"))
				var msg: String  = str(d.get("message", ""))
				var ts: String   = str(d.get("ts", "")).substr(11, 8)
				var color := "green" if kind.contains("complete") or kind == "proof" \
					else ("red" if kind.contains("error") else "white")
				_append("[color=gray]%s[/color] [color=%s]%s[/color] %s" % [ts, color, kind, msg])
		else:
			_append("[color=gray]%s[/color]" % line.substr(0, 100))

	_append("")

func _append(text: String) -> void:
	if _label:
		_label.append_text(text + "\n")
