extends VBoxContainer

## The Hologram tab (Main.gd lazy tab, built on first visit): a SubViewport
## holding the HoloRoom 3D volume, a control bar, the card action bar, and the
## bottom ledger. Also mounted on its own by HoloWarRoomApp (the standalone
## war room, with --shot / --offscreen / --quit-after).
##
## Input path (single, deliberate): the SubViewportContainer's gui_input is
## the only pointer route into the room — HoloRoom has no _input handler, so
## one click can never toggle a layer twice. Container coordinates are scaled
## to viewport coordinates (identical when the container lays the viewport out
## at the same pixel size, which stretch mode guarantees).
##
## Budget: the SubViewport renders only while visible (UPDATE_WHEN_VISIBLE);
## see HoloBudget for the rest.
##
## Ledger: the status block is REPLACED in place on every observation (it is
## a status, not a log); only order events are kept, bounded, below it. The
## ledger is the BBCode surface: external strings are escaped with
## EventStream.escape_event_text (PR #5) before they are wrapped in
## panel-authored colours. The 3D cards use Label3D (literal text), so they
## are NOT escaped — see HoloLayer.
##
## Card actions: when a seat, rig or atlas card is pulled up, "Assign to seat"
## appends one work-order line to the local outbox (WarRoomOutbox). Disabled,
## with the reason shown, when no outbox is configured or no assignable card
## is pulled up. The order's status is shown from a local channel copy when
## one is configured.

const HOLO_ROOM_SCENE: PackedScene = preload("res://scenes/HoloRoom.tscn")
const MAX_ORDER_EVENTS := 6
const STATUS_POLL_SECONDS := 10.0

var outbox: WarRoomOutbox

var _room: HoloRoom
var _container: SubViewportContainer
var _viewport: SubViewport
var _ledger: RichTextLabel
var _slice_btn: Button
var _atlas_btn: Button
var _density_btn: Button
var _pull_btn: Button
var _card_label: Label
var _seat_picker: OptionButton
var _assign_btn: Button
var _order_label: Label
var _status_timer: Timer
var _simulated: bool = false
var _pulled_all: bool = false
var _card: Dictionary = {}
var _status_block: String = ""
var _order_events: PackedStringArray = []
var _last_order_id: String = ""
var _last_order_state: String = ""
var _rendered_ledger: String = ""


func _ready() -> void:
	if outbox == null:
		outbox = WarRoomOutbox.new()

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)

	var title := Label.new()
	title.text = "HOLOGRAM — click a layer, seat or atlas card to pull it up. Esc quits."
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
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

	_container = SubViewportContainer.new()
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_container.size_flags_stretch_ratio = 3.0
	_container.stretch = true
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.handle_input_locally = true
	# Render only while the tab is on screen (budget; HoloBudget).
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_viewport)

	_room = HOLO_ROOM_SCENE.instantiate() as HoloRoom
	_viewport.add_child(_room)
	_room.ledger_changed.connect(_on_ledger_changed)
	_room.card_pulled.connect(_on_card_pulled)
	_container.gui_input.connect(_on_container_gui_input)

	_build_action_bar()

	_ledger = RichTextLabel.new()
	_ledger.bbcode_enabled = true
	_ledger.scroll_active = true
	_ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ledger.size_flags_stretch_ratio = 1.0
	_ledger.custom_minimum_size = Vector2(0, 120)
	add_child(_ledger)
	_status_block = "[color=cyan]HOLOGRAM[/color] — waiting for the first observation…"
	_render_ledger()

	_status_timer = Timer.new()
	_status_timer.wait_time = STATUS_POLL_SECONDS
	_status_timer.one_shot = false
	_status_timer.timeout.connect(_poll_order_status)
	add_child(_status_timer)
	_refresh_action_bar()


func _build_action_bar() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_card_label = Label.new()
	_card_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_label.clip_text = true
	row.add_child(_card_label)

	_seat_picker = OptionButton.new()
	for seat in HoloLayerRegistry.seat_defs():
		_seat_picker.add_item(String(seat.get("name", "?")))
		_seat_picker.set_item_metadata(_seat_picker.item_count - 1, String(seat.get("id", "")))
	row.add_child(_seat_picker)

	_assign_btn = Button.new()
	_assign_btn.text = "Assign to seat"
	_assign_btn.pressed.connect(_on_assign_pressed)
	row.add_child(_assign_btn)

	_order_label = Label.new()
	_order_label.clip_text = true
	_order_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(_order_label)


# ── Public API (tests, the standalone app) ───────────────────────────────────

func room() -> HoloRoom:
	return _room


func viewport() -> SubViewport:
	return _viewport


func ledger_text() -> String:
	return _ledger.get_parsed_text() if _ledger != null else ""


## {enabled, reason} for the Assign action, as the bar shows it.
func assign_state() -> Dictionary:
	if _assign_btn == null:
		return {"enabled": false, "reason": "not built"}
	return {"enabled": not _assign_btn.disabled, "reason": _assign_btn.tooltip_text}


func card_label_text() -> String:
	return _card_label.text if _card_label != null else ""


func order_label_text() -> String:
	return _order_label.text if _order_label != null else ""


func select_seat(seat_id: String) -> bool:
	for i in _seat_picker.item_count:
		if String(_seat_picker.get_item_metadata(i)) == seat_id:
			_seat_picker.select(i)
			return true
	return false


func selected_seat() -> String:
	if _seat_picker.selected < 0:
		return ""
	return String(_seat_picker.get_item_metadata(_seat_picker.selected))


## Press "Assign to seat" (same path as the button). Returns WarRoomOutbox's
## result, or {ok:false, reason} when the action is disabled.
func assign_pulled_card() -> Dictionary:
	_refresh_action_bar()
	if _assign_btn.disabled:
		return {"ok": false, "reason": _assign_btn.tooltip_text}
	var result := outbox.assign(selected_seat(), String(_card.get("title", "")))
	if bool(result.get("ok", false)):
		_last_order_id = String(result["id"])
		_last_order_state = ""
		_add_order_event("order %s → %s: %s (outbox; feeder relays)" % [
			_last_order_id, selected_seat(), String(_card.get("title", ""))])
		_poll_order_status()
		if not outbox.channel_path.is_empty():
			_status_timer.start()
	else:
		_add_order_event("order NOT written: " + String(result.get("reason", "?")))
		_order_label.text = "not written: " + String(result.get("reason", "?"))
	return result


## Render the HoloRoom (the SubViewport only) to a PNG. Returns an Error.
func capture_png(path: String) -> int:
	var tex := _viewport.get_texture()
	if tex == null:
		return ERR_UNAVAILABLE
	var image := tex.get_image()
	if image == null or image.is_empty():
		return ERR_UNAVAILABLE
	return image.save_png(path)


# ── Controls ─────────────────────────────────────────────────────────────────

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


func _on_assign_pressed() -> void:
	assign_pulled_card()


func _on_card_pulled(card: Dictionary) -> void:
	_card = card
	if String(card.get("kind", "")) == "seat":
		select_seat(String(card.get("id", "")))
	_refresh_action_bar()


func _refresh_action_bar() -> void:
	if _assign_btn == null:
		return
	if _card.is_empty():
		_card_label.text = "No card pulled up — click a seat, a rig or an atlas card."
	else:
		_card_label.text = "Pulled up: " + String(_card.get("title", "?"))
	var reason := ""
	var avail := outbox.availability()
	if not bool(avail.get("ok", false)):
		reason = String(avail.get("reason", "outbox unavailable"))
	elif _card.is_empty():
		reason = "pull up a seat, rig or atlas card first"
	elif not bool(_card.get("assignable", false)):
		reason = String(_card.get("reason", "this card is not a work item"))
	_assign_btn.disabled = not reason.is_empty()
	_assign_btn.tooltip_text = reason
	if _last_order_id.is_empty():
		_order_label.text = ("Assign disabled: " + reason) if not reason.is_empty() else "Assign ready (local outbox; the feeder relays)"


func _poll_order_status() -> void:
	if _last_order_id.is_empty():
		_status_timer.stop()
		return
	var status := outbox.order_status(_last_order_id)
	var state := String(status.get("state", "unknown"))
	_order_label.text = "%s: %s — %s" % [_last_order_id, state, String(status.get("detail", ""))]
	if state != _last_order_state:
		_last_order_state = state
		if state != "pending" and state != "unknown":
			_add_order_event("status %s: %s (%s)" % [_last_order_id, state, String(status.get("detail", ""))])
	if outbox.channel_path.is_empty():
		_status_timer.stop()


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


# ── Ledger ───────────────────────────────────────────────────────────────────

## The room's status block, replaced in place (external text escaped, PR #5).
func _on_ledger_changed(text: String) -> void:
	_status_block = "[color=gray]" + EventStream.escape_event_text(text) + "[/color]"
	_render_ledger()


func _add_order_event(text: String) -> void:
	_order_events.append(EventStream.escape_event_text(text))
	while _order_events.size() > MAX_ORDER_EVENTS:
		_order_events.remove_at(0)
	_render_ledger()


func _render_ledger() -> void:
	var text := _status_block
	if not _order_events.is_empty():
		text += "\n[color=cyan]ORDERS[/color]\n" + "\n".join(_order_events)
	if text == _rendered_ledger:
		return
	_rendered_ledger = text
	_ledger.clear()
	_ledger.append_text(text)
