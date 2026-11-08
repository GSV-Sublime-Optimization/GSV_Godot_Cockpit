extends VBoxContainer

## The Hologram tab (Main.gd lazy tab, built on first visit): a SubViewport
## holding the HoloRoom 3D volume, a control bar, and the bottom ledger.
##
## Input path (single, deliberate): the SubViewportContainer's gui_input is
## the only pointer route into the room — HoloRoom has no _input handler, so
## one click can never toggle a layer twice. Container coordinates are scaled
## to viewport coordinates (identical when the container lays the viewport out
## at the same pixel size, which stretch mode guarantees).
##
## The ledger is the BBCode surface: external strings are escaped with
## EventStream.escape_event_text (PR #5) before they are wrapped in
## panel-authored colours. The 3D cards use Label3D (literal text), so they
## are NOT escaped — see HoloLayer.

const HOLO_ROOM_SCENE: PackedScene = preload("res://scenes/HoloRoom.tscn")

var _room: HoloRoom
var _container: SubViewportContainer
var _viewport: SubViewport
var _ledger: RichTextLabel
var _slice_btn: Button
var _density_btn: Button
var _pull_btn: Button
var _simulated: bool = false
var _pulled_all: bool = false


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
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_viewport)

	_room = HOLO_ROOM_SCENE.instantiate() as HoloRoom
	_viewport.add_child(_room)
	_room.ledger_changed.connect(_on_ledger_changed)
	_container.gui_input.connect(_on_container_gui_input)

	_ledger = RichTextLabel.new()
	_ledger.bbcode_enabled = true
	_ledger.scroll_following = true
	_ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ledger.size_flags_stretch_ratio = 1.0
	_ledger.custom_minimum_size = Vector2(0, 120)
	add_child(_ledger)
	_ledger.append_text("[color=cyan]HOLOGRAM[/color] — waiting for the first observation…\n")


func _on_slice_pressed() -> void:
	var axis := _room.cycle_slice_axis()
	_slice_btn.text = "Slice: " + axis


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
