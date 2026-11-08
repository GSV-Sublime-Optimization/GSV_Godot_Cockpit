extends VBoxContainer

## The Hologram tab (Main.gd lazy tab, built on first visit): a SubViewport
## holding the HoloRoom 3D volume, a control bar, the bottom ledger, and —
## Slice 7 — a right-hand side panel: the node rail, the selection detail,
## "What needs you", the always-visible legend, the event tape, the
## suggestions shelf, and the sync doors.
##
## Input path (single, deliberate): the SubViewportContainer's gui_input is
## the only pointer route into the room — HoloRoom has no _input handler, so
## one click can never toggle a layer twice. Container coordinates are scaled
## to viewport coordinates (identical when the container lays the viewport out
## at the same pixel size, which stretch mode guarantees).
##
## Keyboard: Esc clears the selection (whole-room view); keys 1–4 jump to
## MSI / i3 / L9 / Xanadu. Links in the detail panel open on click
## (OS.shell_open, a user gesture — the room never opens anything itself).
##
## The ledger is the BBCode surface: external strings are escaped with
## EventStream.escape_event_text (PR #5) before they are wrapped in
## panel-authored colours. The 3D cards use Label3D (literal text), so they
## are NOT escaped — see HoloLayer.

const HOLO_ROOM_SCENE: PackedScene = preload("res://scenes/HoloRoom.tscn")

## The fixed colour language (design §2), as the room actually renders it:
## live green-cyan · degraded amber · down/unavailable orange · stale
## yellow-green · unknown grey · planned grey-blue · Xanadu lilac.
const LEGEND_TEXT := """LEGEND — HOW TO READ THE COLONY
live green-cyan · degraded amber · down orange · stale yellow-green · unknown grey · planned grey-blue · Xanadu lilac
30-SECOND READ: 1 seats lit = who is working · 2 web colour = what is healthy · 3 table = what work is flowing · 4 districts bright = which rigs are fresh · 5 shelf bright = what the colony can provably do · 6 ledger bottom line = what just happened · 7 tape = what happened before
Click any node: camera glides, rest dims to 40%, detail lands here. Esc: whole room. Keys 1-4: MSI / i3 / L9 / Xanadu."""

var _room: HoloRoom
var _container: SubViewportContainer
var _viewport: SubViewport
var _ledger: RichTextLabel
var _slice_btn: Button
var _atlas_btn: Button
var _density_btn: Button
var _pull_btn: Button
var _rail: ItemList
var _detail: RichTextLabel
var _needs: RichTextLabel
var _tape: RichTextLabel
var _suggestions: RichTextLabel
var _doors: RichTextLabel
var _simulated: bool = false
var _pulled_all: bool = false
var _rail_signature: String = ""


func _ready() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)

	var title := Label.new()
	title.text = "HOLOGRAM — look down into the volume. Click a layer to pull it up; the slice cuts the thought-volume."
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	_slice_btn = Button.new()
	_slice_btn.text = "Slice: time"
	_slice_btn.pressed.connect(_on_slice_pressed)
	bar.add_child(_slice_btn)

	_atlas_btn = Button.new()
	_atlas_btn.text = "Atlas: all"
	_atlas_btn.pressed.connect(_on_atlas_pressed)
	bar.add_child(_atlas_btn)

	_density_btn = Button.new()
	_density_btn.text = "Density: live"
	_density_btn.pressed.connect(_on_density_pressed)
	bar.add_child(_density_btn)

	_pull_btn = Button.new()
	_pull_btn.text = "Pull all"
	_pull_btn.pressed.connect(_on_pull_pressed)
	bar.add_child(_pull_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset view"
	reset_btn.pressed.connect(_on_reset_pressed)
	bar.add_child(reset_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	_container = SubViewportContainer.new()
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_container.size_flags_stretch_ratio = 3.0
	_container.stretch = true
	left.add_child(_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.handle_input_locally = true
	# Slice 7 idle-CPU fix (the measured 24%-idle cause, contrib #21):
	# never UPDATE_ALWAYS. The viewport redraws while visible; the room's
	# _process early-outs when still, and the 30 fps cap + low-processor
	# mode in Main bound the rest. Loom 0.15% and HOLOMIND 0.0% prove the
	# shape; this slice adopts it and re-measures on the i3.
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_viewport)

	_room = HOLO_ROOM_SCENE.instantiate() as HoloRoom
	_viewport.add_child(_room)
	_room.ledger_changed.connect(_on_ledger_changed)
	_room.selection_changed.connect(_on_selection_changed)
	_room.needs_changed.connect(_on_needs_changed)
	_room.tape_changed.connect(_on_tape_changed)
	_room.suggestions_changed.connect(_on_suggestions_changed)
	_room.doors_changed.connect(_on_doors_changed)
	_container.gui_input.connect(_on_container_gui_input)

	_ledger = RichTextLabel.new()
	_ledger.bbcode_enabled = true
	_ledger.scroll_following = true
	_ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ledger.size_flags_stretch_ratio = 1.0
	_ledger.custom_minimum_size = Vector2(0, 120)
	left.add_child(_ledger)
	_ledger.append_text("[color=cyan]HOLOGRAM[/color] — waiting for the first observation…\n")

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(360, 0)
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(side_scroll)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)

	side.add_child(_section_label("NODE RAIL — everything selectable"))
	_rail = ItemList.new()
	_rail.custom_minimum_size = Vector2(0, 180)
	_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.item_selected.connect(_on_rail_selected)
	side.add_child(_rail)

	side.add_child(_section_label("SELECTED"))
	_detail = _panel_text(140)
	_detail.meta_clicked.connect(_on_link_clicked)
	side.add_child(_detail)

	side.add_child(_section_label("WHAT NEEDS YOU"))
	_needs = _panel_text(120)
	_needs.meta_clicked.connect(_on_link_clicked)
	side.add_child(_needs)

	side.add_child(_section_label("LEGEND"))
	var legend := Label.new()
	legend.text = LEGEND_TEXT
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.modulate = Color(0.85, 0.9, 1.0)
	side.add_child(legend)

	side.add_child(_section_label("EVENT TAPE — what just happened"))
	_tape = _panel_text(120)
	_tape.meta_clicked.connect(_on_link_clicked)
	side.add_child(_tape)

	side.add_child(_section_label("SUGGESTIONS — docs/suggestions/ via PR"))
	_suggestions = _panel_text(90)
	side.add_child(_suggestions)

	side.add_child(_section_label("DOORS — sync surfaces"))
	_doors = _panel_text(140)
	side.add_child(_doors)

	_refresh_rail()
	_on_selection_changed(_room.selected_node())
	_on_needs_changed(_room.needs_items())
	_on_doors_changed(_room.doors())
	_on_suggestions_changed(_room.current_suggestions())
	_on_tape_changed(_room.current_events())


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(0.7, 0.9, 1.0)
	return label


func _panel_text(min_height: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_following = true
	label.custom_minimum_size = Vector2(0, min_height)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return label


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_ESCAPE:
				_room.reset_view()
				get_viewport().set_input_as_handled()
			KEY_1:
				_room.select_node("rig", "msi")
				get_viewport().set_input_as_handled()
			KEY_2:
				_room.select_node("rig", "i3")
				get_viewport().set_input_as_handled()
			KEY_3:
				_room.select_node("rig", "l9")
				get_viewport().set_input_as_handled()
			KEY_4:
				_room.select_node("rig", "xanadu")
				get_viewport().set_input_as_handled()


func _on_slice_pressed() -> void:
	var axis := _room.cycle_slice_axis()
	_slice_btn.text = "Slice: " + axis


func _on_atlas_pressed() -> void:
	# Slices the Capability Atlas shelf (machine / cost class / grade);
	# the shelf itself expands when its header is pulled up.
	var view := _room.cycle_atlas_slice()
	_atlas_btn.text = "Atlas: " + view


func _on_density_pressed() -> void:
	# Local display toggle only (default live). Simulated density is a fixed
	# demo pattern, labelled SIMULATED in full — never live agent state.
	_simulated = not _simulated
	_room.set_simulated_density(_simulated)
	_density_btn.text = "Density: simulated" if _simulated else "Density: live"


func _on_pull_pressed() -> void:
	_pulled_all = not _pulled_all
	_room.pull_all(_pulled_all)
	_pull_btn.text = "Reset view" if _pulled_all else "Pull all"


func _on_reset_pressed() -> void:
	_room.reset_view()


func _on_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_room.pointer_moved(_to_viewport_coords((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_room.pointer_clicked(_to_viewport_coords(mb.position))


func _to_viewport_coords(container_pos: Vector2) -> Vector2:
	var csize: Vector2 = _container.size
	if csize.x <= 0.0 or csize.y <= 0.0:
		return container_pos
	return container_pos * Vector2(_viewport.size) / csize


## Ledger append: external text escaped (PR #5), panel colours authored here.
func _on_ledger_changed(text: String) -> void:
	if _ledger.get_parsed_text().length() > 8000:
		_ledger.clear()
	_ledger.append_text("[color=gray]" + EventStream.escape_event_text(text) + "[/color]\n")


## The node rail: one row per selectable node (rigs / services / seats /
## PRs / missions / Atlas entries / PUs). Rebuilt only when the node list
## itself changes (signature), so the selection highlight survives the
## observation ticks that refresh everything else.
func _refresh_rail() -> void:
	var nodes: Array = _room.selection_nodes()
	var signature := ""
	for node in nodes:
		if typeof(node) == TYPE_DICTIONARY:
			signature += String(node.get("kind", "")) + ":" + String(node.get("id", "")) + ";"
	if signature == _rail_signature:
		return
	_rail_signature = signature
	_rail.clear()
	for node in nodes:
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var idx := _rail.add_item("%s · %s" % [String(node.get("kind", "?")), String(node.get("title", "?"))])
		_rail.set_item_metadata(idx, {"kind": String(node.get("kind", "")), "id": String(node.get("id", ""))})


func _on_rail_selected(index: int) -> void:
	var meta: Dictionary = _rail.get_item_metadata(index)
	if meta.is_empty():
		return
	_room.select_node(String(meta.get("kind", "")), String(meta.get("id", "")))


## Detail panel: exact-head facts + deep links for the selected node, plus
## the PREFILL-ONLY compose text. External strings escaped; links are
## panel-authored [url] tags (the target comes from the node data).
func _on_selection_changed(node: Dictionary) -> void:
	_refresh_rail()
	if node.is_empty():
		_detail.clear()
		_detail.append_text("Whole room — no selection. Click a node in the volume or the rail (keys 1–4 jump to rigs). Default: MSI, the local rig — never Xanadu.\n")
		return
	var lines: PackedStringArray = HoloSelection.detail_lines(node)
	_detail.clear()
	for line in lines:
		var safe := EventStream.escape_event_text(line)
		if line.begins_with("link: "):
			var parts := line.split(" — ", false, 1)
			if parts.size() == 2 and parts[1].begins_with("http"):
				_detail.append_text("[color=cyan]%s[/color] [url=%s]%s[/url]\n" % [
					EventStream.escape_event_text(parts[0]),
					EventStream.escape_event_text(parts[1]),
					EventStream.escape_event_text(parts[1]),
				])
				continue
		_detail.append_text("[color=white]" + safe + "[/color]\n")
	_detail.append_text("\n[color=yellow]" + EventStream.escape_event_text(HoloSelection.compose_prefill(node)) + "[/color]\n")


## "What needs you": severity-ranked, each item = what + since + measured
## why + copyable next move + owner. When nothing needs you, it says so.
func _on_needs_changed(items: Array) -> void:
	_needs.clear()
	if items.is_empty():
		_needs.append_text("[color=green]Nothing needs you.[/color] The room will say so when something does.\n")
		return
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var severity := String(item.get("severity", "amber"))
		var color := "red" if severity == "red" else "yellow"
		_needs.append_text("[color=%s]● %s — %s[/color]\n" % [
			color,
			EventStream.escape_event_text(String(item.get("what", "?"))),
			EventStream.escape_event_text(String(item.get("since", ""))),
		])
		_needs.append_text("  why: " + EventStream.escape_event_text(String(item.get("why", ""))) + "\n")
		_needs.append_text("  move: " + EventStream.escape_event_text(String(item.get("move", ""))) + "\n")
		_needs.append_text("  owner: " + EventStream.escape_event_text(String(item.get("owner", ""))) + "\n")


## Event tape: newest first, at most 8 rows. Scrubbing/replay is a follow-up
## (Loom pattern); this slice shows the tail and its sources.
func _on_tape_changed(events: Dictionary) -> void:
	_tape.clear()
	var items: Array = events.get("events", [])
	if items.is_empty():
		_tape.append_text("[color=gray]Tape empty — " + EventStream.escape_event_text(String(events.get("error", "no events file yet"))) + "[/color]\n")
		return
	for event in items.slice(0, 8):
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var verdict := String(event.get("verdict", ""))
		var line := "%s %s#%d %s" % [
			String(event.get("kind", "?")),
			String(event.get("repo", "?")),
			int(event.get("number", 0)),
			String(event.get("title", "")),
		]
		if not verdict.is_empty():
			line += " [" + verdict + "]"
		line += " — " + String(event.get("actor", "")) + " " + String(event.get("at", ""))
		_tape.append_text("[color=white]" + EventStream.escape_event_text(line) + "[/color]\n")


func _on_suggestions_changed(suggestions: Dictionary) -> void:
	_suggestions.clear()
	var items: Array = suggestions.get("suggestions", [])
	var open_count := 0
	for item in items:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("status", "")) == "open":
			open_count += 1
	_suggestions.append_text("Suggest: add docs/suggestions/YYYYMMDD-<slug>.md via PR (see docs/suggestions/README.md).\n")
	if items.is_empty():
		_suggestions.append_text("[color=gray]Shelf empty — " + EventStream.escape_event_text(String(suggestions.get("error", "no suggestions file yet"))) + "[/color]\n")
		return
	_suggestions.append_text("%d open / %d total:\n" % [open_count, items.size()])
	for item in items.slice(0, 8):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_suggestions.append_text("[color=cyan]● [%s] %s[/color] (%s, %s)\n" % [
			EventStream.escape_event_text(String(item.get("status", ""))),
			EventStream.escape_event_text(String(item.get("title", ""))),
			EventStream.escape_event_text(String(item.get("author", ""))),
			EventStream.escape_event_text(String(item.get("file", ""))),
		])


func _on_doors_changed(doors: Array) -> void:
	_doors.clear()
	if doors.is_empty():
		_doors.append_text("[color=gray]No doors yet.[/color]\n")
		return
	for door in doors:
		if typeof(door) != TYPE_DICTIONARY:
			continue
		_doors.append_text("[color=cyan]%s — %s[/color]\n" % [
			EventStream.escape_event_text(String(door.get("title", "?"))),
			EventStream.escape_event_text(String(door.get("state", "unknown"))),
		])
		_doors.append_text("  " + EventStream.escape_event_text(String(door.get("detail", ""))) + "\n")


## Link click: a user gesture opens the target in the browser. The room
## never opens anything on its own, and never runs anything.
func _on_link_clicked(meta: Variant) -> void:
	var uri := String(meta)
	if uri.begins_with("http://") or uri.begins_with("https://"):
		OS.shell_open(uri)
