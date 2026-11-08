extends PanelContainer

## Independent review-operations instrument. Bounded local GitHub snapshot
## is read-only. No PR mutation, approval, agent dispatch, shell, or merge.
const LEDGER = preload("res://scripts/workstation/WorkbenchReviewLedger.gd")

var _data: Dictionary = {}
var _selected := -1
var _title: Label
var _source: Label
var _queue: ItemList
var _search: LineEdit
var _detail: RichTextLabel
var _open: Button
var _copy: Button
var _inspect_next: Button
var _active_rows: Array[Dictionary] = []

func _ready() -> void:
	_build()
	reload()

func _build() -> void:
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	add_child(root_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root_box.add_child(top)
	_title = Label.new()
	_title.text = "Ξ  REVIEW OPERATIONS  /  EXACT HEADS"
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", Color("#70d8e9"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var refresh := Button.new()
	refresh.text = "RELOAD LOCAL SOURCE"
	refresh.tooltip_text = "Re-read the latest externally exported GitHub queue file. No network or shell action from Godot."
	refresh.pressed.connect(reload)
	top.add_child(refresh)
	var content := HSplitContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(content)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 340
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(left)
	_source = Label.new()
	_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source.text = "No source read. Queue disabled."
	_source.add_theme_font_size_override("font_size", 11)
	_source.add_theme_color_override("font_color", Color("#d9b678"))
	left.add_child(_source)
	_search = LineEdit.new()
	_search.placeholder_text = "Filter PR number, repository, title, lane..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value): _render_queue())
	left.add_child(_search)
	_queue = ItemList.new()
	_queue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_queue.allow_reselect = true
	_queue.item_selected.connect(_select)
	left.add_child(_queue)
	_inspect_next = Button.new()
	_inspect_next.text = "NEXT HIGHEST-YIELD INVESTIGATION"
	_inspect_next.disabled = true
	_inspect_next.pressed.connect(_focus_next)
	left.add_child(_inspect_next)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 310
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 9)
	content.add_child(right)
	var heading := Label.new()
	heading.text = "REVIEW EVIDENCE  /  SEQUENTIAL ROUTE"
	heading.add_theme_color_override("font_color", Color("#fac97b"))
	right.add_child(heading)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = false
	_detail.scroll_active = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.text = "Choose an exact-head PR to inspect its prerequisites."
	right.add_child(_detail)
	_open = Button.new()
	_open.text = "OPEN VERIFIED GITHUB PR"
	_open.disabled = true
	_open.tooltip_text = "Open only the vetted github.com/GSV-Sublime-Optimization/.../pull/N URL."
	_open.pressed.connect(_open_pr)
	right.add_child(_open)
	_copy = Button.new()
	_copy.text = "COPY EXACT-HEAD REVIEW BRIEF"
	_copy.disabled = true
	_copy.tooltip_text = "Copy bounded source facts for an engineer. Never an approval or actor assignment."
	_copy.pressed.connect(_copy_brief)
	right.add_child(_copy)
	var footer := Label.new()
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.text = ("Source: read-only GitHub export via gh CLI.\n"
		+ "Lane = heuristic, NOT GSV admission. Never auto-assign an agent or merge.\n"
		+ "Actor availability is unknown unless a separately observed fresh capacity feed exists.")
	footer.add_theme_color_override("font_color", Color("#a8b5c8"))
	footer.add_theme_font_size_override("font_size", 11)
	right.add_child(footer)

func reload() -> void:
	set_data(LEDGER.read_optional())

func set_data(value: Dictionary) -> void:
	_data = value.duplicate(true)
	_selected = -1
	if _queue == null:
		return
	_render_queue()

func _render_queue() -> void:
	if _queue == null:
		return
	_queue.clear()
	_active_rows.clear()
	_selected = -1
	_open.disabled = true
	_copy.disabled = true
	_inspect_next.disabled = true
	if not _data.get("ok", false):
		_source.text = "REVIEW SOURCE UNAVAILABLE / " + String(_data.get("reason", "not_exported"))
		_detail.text = (
			"No qualified review snapshot.\n\n"
			+ "Run the READ-ONLY EXPORT_REVIEW_QUEUE.cmd first, then reload.\n"
			+ "Unknown or stale status is not an empty queue and never implies merge-readiness.\n\n"
			+ "Current source: " + String(_data.get("source_path", "unknown")).substr(0, 260))
		return
	var items: Array = _data.get("items", [])
	_source.text = ("%d sampled PRs  /  age %ds  /  read-only\n"
		+ "Unknown independent actor capacity is never scheduled automatically.") % [
		items.size(), int(_data.get("age_seconds", 0.0))]
	var term := _search.text.strip_edges().to_lower() if _search != null else ""
	for item in items:
		var lookup := (String(item["repo"]) + " " + str(item["number"]) + " "
			+ String(item["title"]) + " " + String(item["lane"])).to_lower()
		if not term.is_empty() and not lookup.contains(term):
			continue
		var line := "%03d  %s#%d   /   %s" % [
			int(item["score"]), String(item["repo"]).get_file(), int(item["number"]),
			String(item["title"]).substr(0, 37)]
		var index := _queue.add_item(line)
		_queue.set_item_tooltip_enabled(index, true)
		_queue.set_item_tooltip(index, String(item["lane"]) + " / " +
			String(item["ci"]) + " / " + String(item["head"]).substr(0, 12))
		_active_rows.append(item.duplicate(true))
	_inspect_next.disabled = _active_rows.is_empty()
	_detail.text = ("No PR selected. These entries are ranked advisory investigations, "
		+ "not inferred readiness or free agent slots. Select a PR or pick NEXT.")

func _select(index: int) -> void:
	if index < 0 or index >= _active_rows.size():
		return
	_selected = index
	_queue.select(index)
	var item: Dictionary = _active_rows[index]
	var actor := String(item.get("suggested_actor", ""))
	var head := String(item.get("head", ""))
	var blockers: Array = item.get("blockers", [])
	_detail.text = ("%s\n\n%s#%d\n\nHEAD\n%s\n\nLANE\n%s\n\n"
		+ "CI / REVIEW / CONFLICTS\n%s / %s / %s\n\n"
		+ "BASE\n%s\n\nBLOCKERS\n%s\n\n"
		+ "NEXT ACTOR SUGGESTION\n%s\n%s\n\n"
		+ "INTEGRATION RULE\n"
		+ "Exact-head GSV dry-run, independent code review, author provenance, "
		+ "owning executor/admission and fresh source required; this queue is never a merge gate.") % [
		String(item["title"]), String(item["repo"]), int(item["number"]),
		head if not head.is_empty() else "UNKNOWN: NOT OBSERVED",
		String(item["lane"]),
		String(item["ci"]), String(item["review"]), String(item["mergeable"]),
		String(item["base"]),
		"\n".join(blockers) if not blockers.is_empty() else "None observed by this bounded source",
		actor if not actor.is_empty() else "UNOBSERVED / NOT ASSIGNED",
		String(item.get("routing_reason", "no_actor_evidence"))
	]
	_open.disabled = false
	_copy.disabled = head.is_empty()

func _focus_next() -> void:
	if _active_rows.is_empty():
		return
	_select(posmod(_selected + 1, _active_rows.size()))

func _open_pr() -> void:
	if _selected < 0 or _selected >= _active_rows.size() or _open.disabled:
		return
	var item: Dictionary = _active_rows[_selected]
	var expect := "https://github.com/%s/pull/%d" % [item["repo"], item["number"]]
	if String(item["url"]) == expect:
		OS.shell_open(expect)

func _copy_brief() -> void:
	if _selected < 0 or _selected >= _active_rows.size() or _copy.disabled:
		return
	var text := LEDGER.brief(_active_rows[_selected])
	if not text.is_empty() and text.length() <= 4000:
		DisplayServer.clipboard_set(text)
