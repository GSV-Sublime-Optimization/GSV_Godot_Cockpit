extends PanelContainer
class_name QuestBoard

## QuestBoard — Colony reports as active quests. Know what the ship is doing.

const REPORTS_DIR := "C:/dev/active/Kilo_Core/state/cultivation/reports"
const SPRINT_INDEX := "C:/GSV/state/autonomous-sprints"

static func reports_dir() -> String:
	var configured := OS.get_environment("GSV_KILOCORE_REPORTS_DIR").strip_edges()
	if not configured.is_empty():
		return configured
	return REPORTS_DIR if OS.has_feature("windows") else ""

static func sprints_dir() -> String:
	var configured := OS.get_environment("GSV_SPRINTS_DIR").strip_edges()
	if not configured.is_empty():
		return configured
	return SPRINT_INDEX if OS.has_feature("windows") else ""

func _ready() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "⚔ Quest Board — Colony Objectives"
	title.add_theme_font_size_override("font_size", 15)
	hdr.add_child(title)

	var refresh_btn := Button.new()
	refresh_btn.text = "↺"
	refresh_btn.pressed.connect(_populate.bind(root))
	hdr.add_child(refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "QuestList"
	scroll.add_child(list)

	_populate(root)

func _populate(root: VBoxContainer) -> void:
	# Find or create the quest list
	var scroll: ScrollContainer
	for child in root.get_children():
		if child is ScrollContainer:
			scroll = child
			break
	if not scroll:
		return
	var list: VBoxContainer
	for child in scroll.get_children():
		if child is VBoxContainer:
			list = child
			break
	if not list:
		return

	# Clear existing entries
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	# Sprint status first
	_add_sprint_status(list)

	# Cultivation reports as quests
	var reports := PackedStringArray()
	var source_dir := reports_dir()
	if not source_dir.is_empty() and DirAccess.dir_exists_absolute(source_dir):
		reports = DirAccess.get_files_at(source_dir)
	if reports.size() == 0:
		var empty := Label.new()
		empty.text = "(no reports found)"
		empty.modulate = Color(0.5, 0.5, 0.5)
		list.add_child(empty)
		return

	# Sort newest first
	var sorted := Array(reports)
	sorted.sort()
	sorted.reverse()

	var count := 0
	for fname in sorted:
		if count >= 12:
			break
		if not (fname.ends_with(".txt") or fname.ends_with(".md")):
			continue
		_add_quest_entry(list, fname)
		count += 1

func _add_sprint_status(list: VBoxContainer) -> void:
	var root_dir := sprints_dir()
	if root_dir.is_empty():
		return
	var index_file := root_dir.path_join("index.json")
	if not FileAccess.file_exists(index_file):
		return
	var f := FileAccess.open(index_file, FileAccess.READ)
	if not f:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		return
	f.close()
	var d = json.get_data()
	if typeof(d) != TYPE_DICTIONARY:
		return

	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var hdr := Label.new()
	hdr.text = "▶ AUTONOMOUS SPRINT"
	hdr.modulate = Color(0.3, 1.0, 1.0)
	hdr.add_theme_font_size_override("font_size", 13)
	vb.add_child(hdr)

	var latest = d.get("latest", {})
	if typeof(latest) == TYPE_DICTIONARY:
		var info := Label.new()
		info.text = "  cycle %s · %s UP · started %s" % [
			str(latest.get("cycle", "?")),
			str(latest.get("services_up", "?")),
			str(latest.get("ts", "")).substr(0, 16)
		]
		info.modulate = Color(0.8, 0.8, 0.8)
		vb.add_child(info)

	list.add_child(panel)

	var sep := HSeparator.new()
	list.add_child(sep)

func _add_quest_entry(list: VBoxContainer, fname: String) -> void:
	# Infer status from name
	var color := Color.WHITE
	if fname.contains("prime-conductor") or fname.contains("godot-cockpit") or fname.contains("final"):
		color = Color(0.3, 1.0, 0.3)   # green = complete
	elif fname.contains("sprint") or fname.contains("active"):
		color = Color(1.0, 1.0, 0.3)   # yellow = in progress
	elif fname.contains("gap") or fname.contains("TODO"):
		color = Color(1.0, 0.6, 0.2)   # orange = needs attention

	var row := HBoxContainer.new()
	list.add_child(row)

	var bullet := Label.new()
	bullet.text = "◆"
	bullet.modulate = color
	bullet.custom_minimum_size = Vector2(16, 0)
	row.add_child(bullet)

	var lbl := Label.new()
	# Strip timestamp prefix if present (e.g. "20260625-" style)
	var display := fname.get_basename()
	if display.length() > 9 and display.substr(0,8).is_valid_int():
		display = display.substr(9)
	lbl.text = display
	lbl.modulate = color
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
