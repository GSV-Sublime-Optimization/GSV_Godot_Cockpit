extends Control

## GSV Colony Workstation: modular native Godot operator surface.
## Read-only Studio sensors and bounded session traces, never direct execution.
## Legacy cockpit retained at res://scenes/Main.tscn.

const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")
const STUDIO_CLIENT = preload("res://scripts/workstation/WorkbenchStudioClient.gd")
const SESSION_PANE = preload("res://scripts/workstation/WorkbenchSessionPane.gd")
const MISSION_DESK = preload("res://scripts/workstation/WorkbenchMissionDesk.gd")
const HYPERSPACE = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
const SKIN = preload("res://scripts/workstation/WorkbenchTheme.gd")

@export var auto_refresh: bool = true

var _client: Node
var _tabs: TabContainer
var _nav: ItemList
var _nav_search: LineEdit
var _inspector: RichTextLabel
var _inspector_panel: PanelContainer
var _activity: RichTextLabel
var _activity_panel: PanelContainer
var _status: Label
var _palette: PopupPanel
var _palette_search: LineEdit
var _palette_results: ItemList
var _layout_picker: OptionButton
var _pages: Dictionary = {}
var _page_meta: Dictionary = {}
var _rig_labels: Dictionary = {}
var _rig_details: Dictionary = {}
var _mission_list: ItemList
var _mission_caption: Label
var _services_list: ItemList
var _services_caption: Label
var _fleet_caption: Label
var _snapshot: Dictionary = {}
var _events: Array[String] = []
var _palette_commands: Array[Dictionary] = []
var _selected_meta: Dictionary = {}
var _view_ready := false

func _ready() -> void:
	theme = SKIN.make_theme()
	_client = STUDIO_CLIENT.new()
	add_child(_client)
	_client.snapshot_changed.connect(_on_snapshot)
	_build_ui()
	_build_palette()
	_refresh_navigation()
	_open_resource({"kind": "fleet", "id": "fleet", "name": "Fleet"})
	_view_ready = true
	_note("Workstation opened. Source telemetry not observed yet.")
	if auto_refresh:
		var timer := Timer.new()
		timer.wait_time = 15.0
		timer.autostart = true
		timer.timeout.connect(_client.refresh)
		add_child(timer)
		call_deferred("_observe_after_paint")

func _observe_after_paint() -> void:
	for frame in 2:
		await get_tree().process_frame
	_client.refresh()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = SKIN.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var frame := VBoxContainer.new()
	frame.name = "WorkstationFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 12
	frame.offset_top = 10
	frame.offset_right = -12
	frame.offset_bottom = -8
	frame.add_theme_constant_override("separation", 9)
	add_child(frame)
	_build_topbar(frame)

	var workspace := HSplitContainer.new()
	workspace.name = "Docks"
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.split_offset = 240
	frame.add_child(workspace)
	_build_library(workspace)

	var work_right := HSplitContainer.new()
	work_right.name = "WorkspaceAndInspector"
	work_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	work_right.split_offset = -265
	workspace.add_child(work_right)

	var middle := VSplitContainer.new()
	middle.name = "WorkspaceAndActivity"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.split_offset = -155
	work_right.add_child(middle)

	_tabs = TabContainer.new()
	_tabs.name = "WorkspaceTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.drag_to_rearrange_enabled = true
	_tabs.tabs_rearrange_group = 0
	middle.add_child(_tabs)
	_tabs.get_tab_bar().tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	_tabs.get_tab_bar().close_with_middle_mouse = true
	_tabs.get_tab_bar().tab_close_pressed.connect(_close_tab)
	_tabs.tab_changed.connect(_tab_changed)

	_activity_panel = PanelContainer.new()
	_activity_panel.name = "ActivityDock"
	_activity_panel.custom_minimum_size = Vector2(0, 126)
	middle.add_child(_activity_panel)
	var activity_box := VBoxContainer.new()
	activity_box.add_theme_constant_override("separation", 4)
	_activity_panel.add_child(activity_box)
	var activity_label := Label.new()
	activity_label.text = "EVENT STRIP   /   UI actions and observation state"
	activity_label.add_theme_color_override("font_color", SKIN.GOLD)
	activity_label.add_theme_font_size_override("font_size", 12)
	activity_box.add_child(activity_label)
	_activity = RichTextLabel.new()
	_activity.bbcode_enabled = false
	_activity.scroll_following = true
	_activity.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity.add_theme_color_override("default_color", SKIN.MUTED)
	activity_box.add_child(_activity)

	_inspector_panel = PanelContainer.new()
	_inspector_panel.name = "InspectorDock"
	_inspector_panel.custom_minimum_size = Vector2(230, 0)
	work_right.add_child(_inspector_panel)
	var inspector_box := VBoxContainer.new()
	inspector_box.add_theme_constant_override("separation", 10)
	_inspector_panel.add_child(inspector_box)
	var inspector_title := Label.new()
	inspector_title.text = "INSPECTOR   /   SELECTED SOURCE"
	inspector_title.add_theme_font_size_override("font_size", 12)
	inspector_title.add_theme_color_override("font_color", SKIN.CYAN)
	inspector_box.add_child(inspector_title)
	_inspector = RichTextLabel.new()
	_inspector.bbcode_enabled = false
	_inspector.fit_content = false
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_box.add_child(_inspector)
	var inspector_refresh := Button.new()
	inspector_refresh.text = "REFRESH SOURCE"
	inspector_refresh.pressed.connect(_refresh_sources)
	inspector_box.add_child(inspector_refresh)

	var footer := HBoxContainer.new()
	frame.add_child(footer)
	var help := Label.new()
	help.text = "Ctrl+K  palette    Ctrl+Tab  switch    Ctrl+W  close    F5  observe    F6  inspector    F7  events"
	help.add_theme_color_override("font_color", SKIN.MUTED)
	help.add_theme_font_size_override("font_size", 11)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	var boundary := Label.new()
	boundary.text = "R0 / OBSERVE ONLY"
	boundary.add_theme_color_override("font_color", SKIN.GOLD)
	boundary.add_theme_font_size_override("font_size", 11)
	footer.add_child(boundary)

func _build_topbar(frame: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.name = "TransportBar"
	bar.add_theme_constant_override("separation", 10)
	frame.add_child(bar)
	var glyph := Label.new()
	glyph.text = "Ξ"
	glyph.add_theme_font_size_override("font_size", 29)
	glyph.add_theme_color_override("font_color", SKIN.CYAN)
	bar.add_child(glyph)
	var branding := VBoxContainer.new()
	branding.add_theme_constant_override("separation", 1)
	bar.add_child(branding)
	var title := Label.new()
	title.text = "NUSYQ  /  COLONY WORKSTATION"
	title.add_theme_font_size_override("font_size", 17)
	branding.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "ONE ENTITY · FOUR BODIES · MANY TOOLS"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", SKIN.MUTED)
	branding.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_status = Label.new()
	_status.text = "STUDIO NOT OBSERVED   |   0/4 FRESH"
	_status.add_theme_color_override("font_color", SKIN.GOLD)
	_status.add_theme_font_size_override("font_size", 11)
	bar.add_child(_status)
	_layout_picker = OptionButton.new()
	for name in ["COLONY", "FOCUS", "PLAYTEST"]:
		_layout_picker.add_item(name)
	_layout_picker.tooltip_text = "Change dock visibility and emphasis, not agent permissions."
	_layout_picker.item_selected.connect(_apply_layout)
	bar.add_child(_layout_picker)
	var refresh := Button.new()
	refresh.text = "OBSERVE  F5"
	refresh.pressed.connect(_refresh_sources)
	bar.add_child(refresh)
	var space_btn := Button.new()
	space_btn.text = "HYPERSPACE  3D"
	space_btn.tooltip_text = "Explore actual fleet, project, mission and service observations as a navigable 3D graph"
	space_btn.pressed.connect(func(): _open_resource({"kind": "hyperspace", "id": "hyperspace", "name": "Hyperspace"}))
	bar.add_child(space_btn)
	var factory_btn := Button.new()
	factory_btn.text = "BUILD SOFTWARE"
	factory_btn.tooltip_text = "Compose an owner-backed Studio mission, not a shell"
	factory_btn.pressed.connect(func(): _open_resource({"kind": "factory", "id": "factory", "name": "Software Factory"}))
	bar.add_child(factory_btn)
	var palette_btn := Button.new()
	palette_btn.text = "JUMP  Ctrl+K"
	palette_btn.pressed.connect(_show_palette)
	bar.add_child(palette_btn)

func _build_library(parent: HSplitContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "LibraryDock"
	panel.custom_minimum_size = Vector2(210, 0)
	parent.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)
	var h := Label.new()
	h.text = "LIBRARY   /   ALL SURFACES"
	h.add_theme_color_override("font_color", SKIN.CYAN)
	h.add_theme_font_size_override("font_size", 12)
	layout.add_child(h)
	_nav_search = LineEdit.new()
	_nav_search.placeholder_text = "Filter rigs, agents, tools..."
	_nav_search.clear_button_enabled = true
	_nav_search.text_changed.connect(func(_text): _refresh_navigation())
	layout.add_child(_nav_search)
	_nav = ItemList.new()
	_nav.name = "SurfaceLibrary"
	_nav.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nav.allow_reselect = true
	_nav.item_selected.connect(_on_navigation)
	layout.add_child(_nav)
	var nav_foot := Label.new()
	nav_foot.text = "Catalogue ≠ an active session"
	nav_foot.add_theme_color_override("font_color", SKIN.MUTED)
	nav_foot.add_theme_font_size_override("font_size", 11)
	layout.add_child(nav_foot)

func _refresh_navigation() -> void:
	if _nav == null:
		return
	var needle := _nav_search.text.strip_edges().to_lower() if _nav_search != null else ""
	_nav.clear()
	var groups := [
		{"name": "WORKSPACES", "entries": [
			{"kind": "fleet", "id": "fleet", "name": "Fleet / bodies"},
			{"kind": "hyperspace", "id": "hyperspace", "name": "Hyperspace / 3D source graph"},
			{"kind": "factory", "id": "factory", "name": "Software factory / build"},
			{"kind": "sessions", "id": "sessions", "name": "Observed missions"},
			{"kind": "services", "id": "services", "name": "Colony services"},
			{"kind": "projects", "id": "projects", "name": "Project constellation"},
			{"kind": "games", "id": "games", "name": "Game laboratory"},
			{"kind": "legacy", "id": "legacy", "name": "Legacy cockpit"}]},
		{"name": "RIGS", "entries": _catalogue_group(CATALOG.RIGS, "rig")},
		{"name": "AGENTS / HARNESSES", "entries": _catalogue_group(CATALOG.AGENTS, "agent")},
		{"name": "PROJECTS", "entries": _catalogue_group(CATALOG.PROJECTS, "project")},
		{"name": "GAMES", "entries": _catalogue_group(CATALOG.GAMES, "game")}
	]
	for group in groups:
		var visible: Array = []
		for item in group["entries"]:
			var display := String(item.get("name", ""))
			if needle.is_empty() or display.to_lower().contains(needle) or String(item.get("role", "")).to_lower().contains(needle):
				visible.append(item)
		if visible.is_empty():
			continue
		var heading: int = _nav.add_item(String(group["name"]))
		_nav.set_item_disabled(heading, true)
		for item in visible:
			var idx: int = _nav.add_item("  " + String(item.get("name", "")))
			_nav.set_item_metadata(idx, item.duplicate(true))
	if needle.is_empty() and _snapshot.get("mission_feed_state", "") == "observed":
		var missions: Array = _snapshot.get("missions", [])
		if not missions.is_empty():
			var heading: int = _nav.add_item("LIVE STUDIO MISSIONS")
			_nav.set_item_disabled(heading, true)
			for mission in missions.slice(0, 12):
				var item: Dictionary = mission.duplicate(true)
				item["kind"] = "mission"
				item["name"] = mission.get("title", "Mission")
				var idx := _nav.add_item("  " + String(item["name"]).substr(0, 27))
				_nav.set_item_metadata(idx, item)

func _catalogue_group(source: Array, kind: String) -> Array:
	var out: Array = []
	for original in source:
		var item: Dictionary = original.duplicate(true)
		item["kind"] = kind
		out.append(item)
	return out

func _on_navigation(index: int) -> void:
	var metadata: Variant = _nav.get_item_metadata(index)
	if typeof(metadata) == TYPE_DICTIONARY:
		_open_resource(metadata)

func _open_resource(meta: Dictionary) -> void:
	var kind := String(meta.get("kind", ""))
	var id := String(meta.get("id", ""))
	var title := String(meta.get("name", id))
	var key := kind + ":" + id
	match kind:
		"hyperspace":
			_open_tab(key, "HYPERSPACE", meta, _make_hyperspace)
		"factory":
			_open_tab(key, "FACTORY", meta, _make_factory)
		"fleet":
			_open_tab(key, "FLEET", meta, _make_fleet)
		"sessions":
			_open_tab(key, "SESSIONS", meta, _make_sessions)
		"services":
			_open_tab(key, "SERVICES", meta, _make_services)
		"projects", "games":
			_open_tab(key, title.to_upper(), meta, _make_collection.bind(kind))
		"mission":
			var pane: PanelContainer = SESSION_PANE.new()
			var entry := meta.duplicate(true)
			entry["session_kind"] = "mission_log"
			pane.configure(entry, _client)
			_open_tab(key, title.substr(0, 25), meta, func() -> Control: return pane)
		"agent":
			var pane: PanelContainer = SESSION_PANE.new()
			pane.configure(meta, _client)
			_open_tab(key, title.to_upper(), meta, func() -> Control: return pane)
		"rig":
			_open_tab(key, title.to_upper(), meta, _make_rig.bind(meta))
		"project", "game":
			_open_tab(key, title.to_upper(), meta, _make_detail.bind(meta))
		"legacy":
			_open_tab(key, "LEGACY", meta, _make_legacy)
		_:
			return
	_select_inspector(meta)

func _open_tab(key: String, label: String, meta: Dictionary, maker: Callable) -> void:
	if _pages.has(key) and is_instance_valid(_pages[key]):
		_tabs.current_tab = _tabs.get_tab_idx_from_control(_pages[key])
		return
	var panel := PanelContainer.new()
	panel.name = "Workspace" + str(_tabs.get_tab_count())
	panel.set_meta("workstation_key", key)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(panel)
	var idx := _tabs.get_tab_count() - 1
	_tabs.set_tab_title(idx, label)
	var content: Control = maker.call()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	_pages[key] = panel
	_page_meta[key] = meta.duplicate(true)
	_tabs.current_tab = idx
	_note("Opened " + label + " (local UI tab, not a terminal attachment).")

func _close_tab(idx: int) -> void:
	if idx < 0 or idx >= _tabs.get_tab_count():
		return
	var panel: Control = _tabs.get_tab_control(idx)
	if panel == null:
		return
	var key := String(panel.get_meta("workstation_key", ""))
	if key == "fleet:fleet":
		return
	_pages.erase(key)
	_page_meta.erase(key)
	_tabs.remove_child(panel)
	panel.queue_free()
	_note("Closed a local workspace tab. No remote process was stopped.")
	if _tabs.get_tab_count() == 0:
		_open_resource({"kind": "fleet", "id": "fleet", "name": "Fleet"})

func _tab_changed(idx: int) -> void:
	if idx < 0:
		return
	var panel: Control = _tabs.get_tab_control(idx)
	if panel == null:
		return
	var key := String(panel.get_meta("workstation_key", ""))
	if _page_meta.has(key):
		_select_inspector(_page_meta[key])

func _make_hyperspace() -> Control:
	var space: PanelContainer = HYPERSPACE.new()
	space.resource_activated.connect(_open_resource)
	space.compose_requested.connect(_compose_from_space)
	_client.snapshot_changed.connect(space.set_snapshot)
	space.set_snapshot(_snapshot)
	return space

func _compose_from_space(context: Dictionary) -> void:
	_open_resource({"kind": "factory", "id": "factory", "name": "Software Factory"})
	var page: Control = _pages.get("factory:factory", null)
	if page == null or page.get_child_count() == 0:
		return
	var desk: Node = page.get_child(0)
	desk.apply_context(context)
	_note("Hyperspace sent source context to the Factory. Studio will requalify the selected project.")

func _make_factory() -> Control:
	var desk: PanelContainer = MISSION_DESK.new()
	desk.mission_submitted.connect(func(id: String, state: String):
		_note("Studio acknowledged mission %s (%s). Refreshing index; approval remains Studio-owned." % [id, state])
		_client.refresh()
	)
	desk.mission_view_requested.connect(_open_observed_mission)
	return desk

func _open_observed_mission(id: String) -> void:
	if _snapshot.get("mission_feed_state", "unknown") == "observed":
		for mission in _snapshot.get("missions", []):
			if String(mission.get("id", "")) == id:
				var item: Dictionary = mission.duplicate(true)
				item["kind"] = "mission"
				item["name"] = mission.get("title", "Mission")
				_open_resource(item)
				return
	_note("Mission not yet verified in Studio index; requesting a fresh observation.")
	_client.refresh()

func _make_fleet() -> Control:
	var scroll := ScrollContainer.new()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 13)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var title := Label.new()
	title.text = "FLEET  /  ONE IDENTITY, FOUR PHYSICAL BODIES"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", SKIN.CYAN)
	body.add_child(title)
	_fleet_caption = Label.new()
	_fleet_caption.text = "Awaiting a source-stamped Studio report. Unknown is not offline."
	_fleet_caption.add_theme_color_override("font_color", SKIN.MUTED)
	body.add_child(_fleet_caption)
	var cards := GridContainer.new()
	cards.columns = 2
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	body.add_child(cards)
	for rig in CATALOG.RIGS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(250, 148)
		cards.add_child(card)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 7)
		card.add_child(content)
		var name := Label.new()
		name.text = String(rig["name"]) + "   /   " + String(rig["role"])
		name.add_theme_font_size_override("font_size", 16)
		content.add_child(name)
		var summary := Label.new()
		summary.text = "UNKNOWN  ·  no validated Studio report"
		summary.add_theme_color_override("font_color", SKIN.GOLD)
		content.add_child(summary)
		_rig_labels[rig["id"]] = summary
		var details := Label.new()
		details.text = "Memory / disk: unknown"
		details.add_theme_font_size_override("font_size", 12)
		content.add_child(details)
		_rig_details[rig["id"]] = details
		var open_rig := Button.new()
		open_rig.text = "INSPECT BODY"
		open_rig.pressed.connect(_open_resource.bind({
			"kind": "rig", "id": rig["id"], "name": rig["name"], "role": rig["role"]
		}))
		content.add_child(open_rig)
	var note := Label.new()
	note.text = "Topology, reachability, activity, authentication and task admission are different signals."
	note.add_theme_color_override("font_color", SKIN.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	_update_fleet()
	return scroll

func _make_rig(rig: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = String(rig.get("name", "?")) + "   /   BODY INSPECTOR"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", SKIN.CYAN)
	box.add_child(title)
	var content := RichTextLabel.new()
	content.name = "RigDetail"
	content.bbcode_enabled = false
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)
	box.set_meta("rig_label", content)
	box.set_meta("rig_id", rig.get("id", ""))
	_update_rig_text(box)
	return box

func _make_sessions() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	var title := Label.new()
	title.text = "SESSIONS  /  REAL MISSION LOGS AND ATTACHABLE SURFACES"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", SKIN.CYAN)
	box.add_child(title)
	_mission_caption = Label.new()
	_mission_caption.text = "Awaiting mission index. Agent runtime catalogue is not a PTY list."
	_mission_caption.add_theme_color_override("font_color", SKIN.MUTED)
	box.add_child(_mission_caption)
	var button := Button.new()
	button.text = "OBSERVE CURRENT STUDIO MISSIONS"
	button.pressed.connect(_refresh_sources)
	box.add_child(button)
	_mission_list = ItemList.new()
	_mission_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mission_list.item_activated.connect(_activate_mission)
	_mission_list.item_selected.connect(_activate_mission)
	box.add_child(_mission_list)
	var note := Label.new()
	note.text = "Select a mission to open a read-only log tab. Runtime PTY attachment requires its owning harness's verified transport."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", SKIN.GOLD)
	box.add_child(note)
	_update_missions()
	return box

func _activate_mission(index: int) -> void:
	if _mission_list == null or index < 0:
		return
	var item: Variant = _mission_list.get_item_metadata(index)
	if typeof(item) == TYPE_DICTIONARY:
		var mission: Dictionary = item.duplicate(true)
		mission["kind"] = "mission"
		mission["name"] = mission.get("title", "Mission")
		_open_resource(mission)

func _make_services() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "COLONY SERVICES  /  OBSERVED THROUGH STUDIO"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", SKIN.CYAN)
	box.add_child(title)
	_services_caption = Label.new()
	_services_caption.text = "Service readiness is unknown until the owning observation arrives."
	_services_caption.add_theme_color_override("font_color", SKIN.MUTED)
	box.add_child(_services_caption)
	_services_list = ItemList.new()
	_services_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_services_list)
	_update_services()
	return box

func _make_collection(kind: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = ("GAMES" if kind == "games" else "PROJECTS") + "   /   NAVIGATION LIBRARY"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", SKIN.CYAN)
	box.add_child(heading)
	var note := Label.new()
	note.text = "These are catalogued projects, not proof of an installed build or a ready-to-play release."
	note.add_theme_color_override("font_color", SKIN.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var entries: Array = CATALOG.GAMES if kind == "games" else CATALOG.PROJECTS
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in entries:
		var idx: int = list.add_item(String(entry["name"]) + "   ·   " + String(entry["role"]))
		var item: Dictionary = entry.duplicate(true)
		item["kind"] = "game" if kind == "games" else "project"
		list.set_item_metadata(idx, item)
	list.item_activated.connect(func(idx):
		var item: Variant = list.get_item_metadata(idx)
		if typeof(item) == TYPE_DICTIONARY:
			_open_resource(item)
	)
	box.add_child(list)
	return box

func _make_detail(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = String(entry.get("name", "")) + "   /   " + String(entry.get("kind", "")).to_upper()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", SKIN.CYAN)
	box.add_child(title)
	var description := Label.new()
	description.text = String(entry.get("role", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	var status := Label.new()
	status.text = "CATALOGUED · no live session, build or executable has been qualified for this tab."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", SKIN.GOLD)
	box.add_child(status)
	var help := Label.new()
	help.text = (
		"Integration path: attach a typed, source-stamped build/agent/session resource through its owning service. "
		+ "Only then enable launch, controls, playtest evidence and process lifecycle actions."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	return box

func _make_legacy() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var h := Label.new()
	h.text = "LEGACY COCKPIT  /  PRESERVED"
	h.add_theme_font_size_override("font_size", 20)
	box.add_child(h)
	var info := Label.new()
	info.text = "The existing 13-panel Godot cockpit has not been removed or reimplemented. Its bridge calls may block while tabs load. Switch explicitly."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var button := Button.new()
	button.text = "OPEN LEGACY SCENE"
	button.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	)
	box.add_child(button)
	return box

func _on_snapshot(next: Dictionary) -> void:
	_snapshot = next.duplicate(true)
	_update_fleet()
	_update_missions()
	_update_services()
	_refresh_navigation()
	var fresh := 0
	for report in next.get("bodies", []):
		if report.get("state", "") == "reported_fresh":
			fresh += 1
	var studio_state := String(next.get("health", {}).get("state", "unknown")).to_upper()
	_status.text = "STUDIO %s   |   BODIES %d/4 FRESH" % [studio_state, fresh]
	_status.add_theme_color_override("font_color", SKIN.GREEN if studio_state == "LIVE" else SKIN.GOLD)
	_note("Observation updated: Studio %s; %d/4 fresh bodies; mission index %s." % [
		studio_state, fresh, next.get("mission_feed_state", "unknown")
	])

func _update_fleet() -> void:
	if _fleet_caption != null:
		var state := String(_snapshot.get("body_feed_state", "unknown"))
		_fleet_caption.text = "Fleet observations: " + state + "  ·  source: KiloCore Studio  ·  reported ≠ admitted"
	for report in _snapshot.get("bodies", []):
		var node_id: String = String(report.get("body_id", ""))
		if not _rig_labels.has(node_id):
			continue
		var state: String = String(report.get("state", "unknown"))
		var label: Label = _rig_labels[node_id]
		label.text = state.to_upper() + "   ·   READ-ONLY"
		label.add_theme_color_override("font_color", SKIN.GREEN if state == "reported_fresh" else SKIN.GOLD)
		var obs: Dictionary = report.get("observation", {})
		var memory: Variant = obs.get("memory_available_bytes")
		var disk: Variant = obs.get("system_volume_free_bytes")
		var details: Label = _rig_details[node_id]
		details.text = "Available RAM %s   /   system free %s" % [
			_gib(memory), _gib(disk)
		]
	for key in _pages:
		if key.begins_with("rig:"):
			var panel: Control = _pages[key]
			if is_instance_valid(panel) and panel.get_child_count() > 0:
				_update_rig_text(panel.get_child(0))

func _update_rig_text(container: Control) -> void:
	var id: String = String(container.get_meta("rig_id", ""))
	var detail: RichTextLabel = container.get_meta("rig_label", null)
	if detail == null:
		return
	var status := "unknown"
	var obs: Dictionary = {}
	for report in _snapshot.get("bodies", []):
		if report.get("body_id", "") == id:
			status = String(report.get("state", "unknown"))
			obs = report.get("observation", {})
	var text := "OBSERVATION STATE  :  %s\n" % status.to_upper()
	text += "RAM AVAILABLE      :  %s\n" % _gib(obs.get("memory_available_bytes"))
	text += "SYSTEM DISK FREE   :  %s\n" % _gib(obs.get("system_volume_free_bytes"))
	text += "EXECUTION ADMITTED :  NO, not through this view\n"
	text += "SOURCE             :  KiloCore Studio body projection\n\n"
	text += "A hostname or recent OS measurement is not proof of model readiness, interactive desktop, active agent or scheduling authority.\n"
	detail.text = text

func _update_missions() -> void:
	if _mission_list == null:
		return
	_mission_list.clear()
	var status := String(_snapshot.get("mission_feed_state", "unknown"))
	var missions: Array = _snapshot.get("missions", [])
	if _mission_caption != null:
		_mission_caption.text = "%d Studio missions  ·  feed %s  ·  read-only traces" % [missions.size(), status]
	for item in missions:
		var idx: int = _mission_list.add_item("[%s / %s] %s" % [
			item.get("risk", "?"), item.get("status", "?"), item.get("title", "Untitled")
		])
		_mission_list.set_item_metadata(idx, item.duplicate(true))

func _update_services() -> void:
	if _services_list == null:
		return
	_services_list.clear()
	var state := String(_snapshot.get("service_feed_state", "unknown"))
	var services: Array = _snapshot.get("services", [])
	if _services_caption != null:
		_services_caption.text = "%d observed service records  ·  source state %s" % [services.size(), state]
	for item in services:
		_services_list.add_item("%s   /   %s" % [item.get("name", ""), item.get("status", "unknown")])

func _gib(value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "unknown"
	return "%.1f GiB" % (float(value) / 1073741824.0)

func _select_inspector(meta: Dictionary) -> void:
	_selected_meta = meta.duplicate(true)
	if _inspector == null:
		return
	var title := String(meta.get("name", meta.get("id", "UNSELECTED")))
	var kind := String(meta.get("kind", "unknown"))
	var output := title + "\n\nTYPE         " + kind.to_upper() + "\n"
	output += "SOURCE       "
	match kind:
		"mission":
			output += "Studio observed mission\n"
			output += "STATE        " + String(meta.get("status", "unknown")) + "\n"
			output += "RISK         " + String(meta.get("risk", "unknown")) + "\n"
			output += "ATTACH       Read-only log only\n"
		"rig":
			output += "Studio fleet OS report\n"
			output += "ATTACH       Not authorized\n"
		"agent":
			output += "Declared catalogue\n"
			output += "SESSION      Unobserved\n"
			output += "ATTACH       Unavailable\n"
		_:
			output += "Local navigation catalogue\n"
	output += "\nThis inspector shows source and permission truth. A catalogue entry is not a live process or runnable tool.\n"
	_inspector.text = output

func _refresh_sources() -> void:
	_note("Operator requested a bounded, read-only Studio refresh.")
	_client.refresh()

func _note(message: String) -> void:
	var time := Time.get_time_string_from_system()
	_events.append("[%s] %s" % [time, message.substr(0, 240)])
	if _events.size() > 100:
		_events.pop_front()
	if _activity != null:
		_activity.text = "\n".join(_events)

func _apply_layout(index: int) -> void:
	match index:
		0:
			_inspector_panel.visible = true
			_activity_panel.visible = true
		1:
			_inspector_panel.visible = false
			_activity_panel.visible = false
		2:
			_inspector_panel.visible = false
			_activity_panel.visible = true
			_open_resource({"kind": "games", "id": "games", "name": "Game Lab"})
	_note("Local workspace layout changed. Remote sessions were not altered.")

func _build_palette() -> void:
	_palette_commands = [
		{"id": "fleet", "label": "Fleet overview"},
		{"id": "factory", "label": "Build software via Studio mission"},
		{"id": "sessions", "label": "Observed mission sessions"},
		{"id": "services", "label": "Observed colony services"},
		{"id": "projects", "label": "Project constellation"},
		{"id": "games", "label": "Game laboratory"},
		{"id": "refresh", "label": "Refresh Studio sensors"},
		{"id": "inspector", "label": "Toggle inspector dock"},
		{"id": "activity", "label": "Toggle activity strip"},
		{"id": "legacy", "label": "Legacy cockpit"},
	]
	_palette = PopupPanel.new()
	_palette.name = "CommandPalette"
	_palette.min_size = Vector2i(475, 350)
	add_child(_palette)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_palette.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_right = -14
	content.offset_top = 14
	content.offset_bottom = -14
	var title := Label.new()
	title.text = "COMMAND PALETTE   /   Ctrl+K"
	title.add_theme_color_override("font_color", SKIN.CYAN)
	content.add_child(title)
	_palette_search = LineEdit.new()
	_palette_search.placeholder_text = "Search known UI actions..."
	_palette_search.text_changed.connect(func(_text): _fill_palette())
	_palette_search.text_submitted.connect(func(_text): _choose_palette(0))
	content.add_child(_palette_search)
	_palette_results = ItemList.new()
	_palette_results.custom_minimum_size = Vector2(0, 260)
	_palette_results.item_activated.connect(_choose_palette)
	content.add_child(_palette_results)
	_fill_palette()

func _show_palette() -> void:
	_palette_search.text = ""
	_fill_palette()
	_palette.popup_centered(Vector2i(520, 390))
	_palette_search.grab_focus()

func _fill_palette() -> void:
	if _palette_results == null:
		return
	_palette_results.clear()
	var search := _palette_search.text.strip_edges().to_lower()
	for item in _palette_commands:
		if search.is_empty() or String(item["label"]).to_lower().contains(search):
			var idx := _palette_results.add_item(String(item["label"]))
			_palette_results.set_item_metadata(idx, item["id"])
	if _palette_results.item_count > 0:
		_palette_results.select(0)

func _choose_palette(index: int) -> void:
	if index < 0 or index >= _palette_results.item_count:
		return
	var action := String(_palette_results.get_item_metadata(index))
	_palette.hide()
	match action:
		"factory", "fleet", "sessions", "services", "projects", "games", "legacy":
			var label := action.capitalize()
			_open_resource({"kind": action, "id": action, "name": label})
		"refresh":
			_refresh_sources()
		"inspector":
			_inspector_panel.visible = not _inspector_panel.visible
		"activity":
			_activity_panel.visible = not _activity_panel.visible

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var handled := true
	if (key.ctrl_pressed or key.meta_pressed) and key.keycode == KEY_K:
		_show_palette()
	elif key.keycode == KEY_F5:
		_refresh_sources()
	elif key.keycode == KEY_F6:
		_inspector_panel.visible = not _inspector_panel.visible
	elif key.keycode == KEY_F7:
		_activity_panel.visible = not _activity_panel.visible
	elif key.ctrl_pressed and key.keycode == KEY_W:
		_close_tab(_tabs.current_tab)
	elif key.ctrl_pressed and key.keycode == KEY_TAB:
		var direction := -1 if key.shift_pressed else 1
		if _tabs.get_tab_count() > 0:
			_tabs.current_tab = posmod(_tabs.current_tab + direction, _tabs.get_tab_count())
	elif key.ctrl_pressed and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var desired := key.keycode - KEY_1
		if desired < _tabs.get_tab_count():
			_tabs.current_tab = desired
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
