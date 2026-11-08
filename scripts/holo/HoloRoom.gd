class_name HoloRoom
extends Node3D

## The holographic war room: a Camera3D looking down into a volume, the
## table, one companion body (the Mind, mounted — never forked), the layer
## stack, the war-room floor of seats, and the thought-volume.
##
## Keath's brief (2026-11-07 ~23:46 MST): the interface IS the coordinate
## transformation between the volume and the screen. The war-room direction
## is the SPIRIT (embodied agents, visible work, status cards); the hologram
## is the FORM. Combined here: the war-room's agents are the companion
## bodies / desks ringing the table; the status cards are the holographic
## layers you pull up; the crawler/spider's work is the sliceable density
## layer (Skyclaw's flickering desk + the thought-volume it feeds).
##
## Presentation / observation ONLY. No authority, no actuators, no secrets,
## no POST, no shell from Godot. The Mind (EntitySession) is mounted from
## scenes/EntitySession.tscn; the Dev-Mentor game sense is a read-only GET
## bridge in the same pattern. The Capability Atlas shelf (Slice 5) is a
## read-only graded inventory (static file + fleet-snapshot overlay).
## Terminal layers are honest PLANNED shells: they report "broker needed"
## and never fake output.
##
## Mounted by HoloTab (a lazy Main.gd tab): the room builds on first visit
## (paint-first-then-probe); senses start after first paint. The volume mesh
## is never rotated — the raymarcher marches in object space and assumes a
## translation + uniform-scale-only transform (see shaders/holo_volume.gdshader).
##
## Slice 7 (alive): the room boots as the default view with the local rig
## (MSI) selected; motion is event-driven only (the 14 s slice sweep and the
## sin(t) desk flicker are removed — the slice advances one step per
## observation, degraded amplitude is a state value); seats read live
## activity from the CHORUS feed.json smiths stream where available and are
## otherwise labelled "seen 2026-11-07"; the web nodes CHATDEV / OLLAMA /
## SKYCLAW are spine observations, not literals; selection (one model for
## rigs / services / seats / PRs / missions / Atlas entries / PUs) glides
## the camera, dims the rest to 40%, and reports to HoloTab's detail panel.

signal ledger_changed(text: String)
signal selection_changed(node: Dictionary)
signal needs_changed(items: Array)
signal tape_changed(events: Dictionary)
signal suggestions_changed(suggestions: Dictionary)
signal doors_changed(doors: Array)

const ENTITY_SESSION_SCENE: PackedScene = preload("res://scenes/EntitySession.tscn")
const HOLO_LAYER_SCRIPT: Script = preload("res://scripts/holo/HoloLayer.gd")
const SURFACE_SHADER: Shader = preload("res://shaders/holo_surface.gdshader")
const VOLUME_SHADER: Shader = preload("res://shaders/holo_volume.gdshader")
const DEV_MENTOR_BRIDGE: Script = preload("res://scripts/holo/DevMentorObservationBridge.gd")
const FLEET_READER: Script = preload("res://scripts/holo/FleetTelemetryReader.gd")
const ATLAS_READER: Script = preload("res://scripts/holo/CapabilityAtlasReader.gd")
const ATLAS_LAYER_SCRIPT: Script = preload("res://scripts/holo/CapabilityAtlasLayer.gd")
const CHORUS_READER: Script = preload("res://scripts/holo/ChorusFeedReader.gd")
const EVENTS_READER: Script = preload("res://scripts/holo/CockpitEventsReader.gd")
const PU_READER: Script = preload("res://scripts/holo/PuQueueReader.gd")
const SUGGESTIONS_READER: Script = preload("res://scripts/holo/CockpitSuggestionsReader.gd")
const SYNC_DOORS: Script = preload("res://scripts/holo/SyncDoors.gd")
const SELECTION_SCRIPT: Script = preload("res://scripts/holo/HoloSelection.gd")

const SLICE_AXES: PackedStringArray = ["time", "sense", "age"]
## Slice sweep ranges, in world units of the volume's own data axes:
## time cuts vertically (magnitude), sense cuts across sense index (x),
## age cuts across the age axis (z). The slice plane is the human's inquiry
## into the dataset embedded in the volume — a data axis, not just world_y.
## Slice 7: the slice plane is EVENT-STEPPED, not timer-swept. Each new
## observation advances it one step (16 steps across the axis range); a
## still colony holds a still plane. The old 14 s sweep is removed.
const SLICE_STEPS := 16

var _camera: Camera3D
var _camera_base: Vector3 = Vector3(0.0, 9.5, 8.5)
var _camera_target: Vector3 = Vector3(0.0, 1.0, 0.0)
var _session: Node
var _dev_mentor: Node
var _fleet_reader: Node
var _fleet: Dictionary = {}
var _atlas_reader: Node
var _atlas_layer: CapabilityAtlasLayer
var _atlas: Dictionary = {}
var _layers: Array = []
var _layer_by_id: Dictionary = {}
var _volume_mat: ShaderMaterial
var _volume_label: Label3D
var _web_instance: MeshInstance3D
var _skyclaw_desk_mat: StandardMaterial3D
var _slice_axis_index: int = 0
var _slice_step: int = 0
var _slice_dirty: bool = true
var _simulated_density: bool = false
var _mouse_pos: Vector2 = Vector2.ZERO
var _mouse_in_view: bool = false
var _model: Dictionary = {}
var _mentor_observation: Dictionary = {}
var _density: Dictionary = {}
var _seat_count: int = 0
var _chorus_reader: Node
var _chorus: Dictionary = {}
var _events_reader: Node
var _events: Dictionary = {}
var _pu_reader: Node
var _pu: Dictionary = {}
var _suggestions_reader: Node
var _suggestions: Dictionary = {}
var _selection: HoloSelection
var _selection_nodes: Array = []
var _needs_items: Array = []
var _doors: Array = []
var _seat_labels: Dictionary = {}
var _seat_mats: Dictionary = {}
var _seat_anchors: Dictionary = {}
var _gliding: bool = false
var _glide_t: float = 0.0
var _glide_from_pos: Vector3 = Vector3.ZERO
var _glide_to_pos: Vector3 = Vector3.ZERO
var _glide_from_target: Vector3 = Vector3.ZERO
var _glide_to_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_table()
	_build_companion()
	_build_monitor()
	_build_seats()
	_build_layers()
	_build_volume()
	_mount_mind()
	_mount_dev_mentor()
	_mount_fleet_reader()
	_mount_atlas_layer()
	_mount_atlas_reader()
	_mount_chorus_reader()
	_mount_events_reader()
	_mount_pu_reader()
	_mount_suggestions_reader()
	_selection = SELECTION_SCRIPT.new()
	_rebuild_density()
	_rebuild_web()
	_refresh_layer_texts()
	_rebuild_selection_nodes()
	_build_needs_items()
	_build_doors()
	# Default selection: the local rig (MSI) — never Xanadu. The camera
	# starts on it; there is no glide at boot, the boot IS the focus event.
	var default_node := HoloSelection.default_node(_selection_nodes)
	if not default_node.is_empty():
		_selection.select(default_node)
		_apply_selection_camera()
		_apply_focus_dim()
	_emit_ledger()
	_observe_after_paint()


## Slice 7: the room's _process does work ONLY while something is actually
## happening — a camera glide (click event), pointer parallax (pointer
## event), a pull animating toward its target (click event), or a slice step
## (observation event). A still colony costs ~nothing per frame: no timers,
## no sin(t), no always-on animation. If nothing happens the room goes
## honestly still.
func _process(delta: float) -> void:
	var camera_moved := false
	if _gliding:
		camera_moved = _step_glide(delta)
	elif not _selection.has_selection():
		camera_moved = _update_camera_parallax()
	if _slice_dirty:
		_update_slice_uniform()
		_slice_dirty = false
	if not _needs_frame(camera_moved):
		return
	for layer in _layers:
		(layer as HoloLayer).update_frame(delta, _camera)
	if _atlas_layer != null:
		_atlas_layer.update_frame(delta, _camera)


## True while a pull is still animating, the camera just moved (layers must
## re-billboard), or a glide is in flight. Everything else is idle.
func _needs_frame(camera_moved: bool) -> bool:
	if camera_moved or _gliding:
		return true
	for layer in _layers:
		var l := layer as HoloLayer
		if absf(l.pull - l.pull_target) > 0.001:
			return true
	if _atlas_layer != null and absf(_atlas_layer.pull - _atlas_layer.pull_target) > 0.001:
		return true
	return false


# ── Public API (called by HoloTab's buttons and pointer forwarding) ──────────

func cycle_slice_axis() -> String:
	_slice_axis_index = (_slice_axis_index + 1) % SLICE_AXES.size()
	_advance_slice()
	_emit_ledger()
	return SLICE_AXES[_slice_axis_index]


func current_slice_axis() -> String:
	return SLICE_AXES[_slice_axis_index]


func set_simulated_density(enabled: bool) -> void:
	_simulated_density = enabled
	_rebuild_density()
	_emit_ledger()


func is_simulated_density() -> bool:
	return _simulated_density


func pull_all(pulled: bool) -> void:
	for layer in _layers:
		(layer as HoloLayer).pull_target = 1.0 if pulled else 0.0
	if _atlas_layer != null:
		_atlas_layer.set_pulled(pulled)


func cycle_atlas_slice() -> String:
	if _atlas_layer == null:
		return "all"
	var view := _atlas_layer.cycle_slice_view()
	_emit_ledger()
	return view


func current_atlas_slice() -> String:
	if _atlas_layer == null:
		return "all"
	return _atlas_layer.slice_view


func pull_atlas(pulled: bool) -> void:
	if _atlas_layer != null:
		_atlas_layer.set_pulled(pulled)


func atlas_entry_count() -> int:
	if _atlas_layer == null:
		return 0
	return _atlas_layer.entry_count()


func atlas_visible_count() -> int:
	if _atlas_layer == null:
		return 0
	return _atlas_layer.visible_count()


func atlas_state() -> Dictionary:
	if _atlas_reader == null:
		return {"state": "unknown", "entries": []}
	return (_atlas_reader as CapabilityAtlasReader).current_atlas()


func pointer_moved(screen_pos: Vector2) -> void:
	_mouse_pos = screen_pos
	_mouse_in_view = true


func pointer_clicked(screen_pos: Vector2) -> void:
	_mouse_pos = screen_pos
	_mouse_in_view = true
	# Seats first (they sit in front of the table), then layers, then the
	# Atlas header — nearest hit wins. A hit SELECTS the node (camera glides,
	# room filters, detail panel reports); the layer also lifts. Clicking
	# empty space clears the selection back to the whole room.
	for seat_id in _seat_anchors.keys():
		var anchor := _seat_anchors[seat_id] as Node3D
		var seat_hit: Dictionary = HoloCoordinateStack.hit_layer(
			_camera, screen_pos, anchor, Vector2(0.6, 0.9)
		)
		if bool(seat_hit.get("hit", false)):
			select_node("seat", String(seat_id))
			return
	var entries: Array = []
	for i in _layers.size():
		var layer := _layers[i] as HoloLayer
		entries.append({"node": layer, "render_priority": layer.render_priority, "index": i})
	if _atlas_layer != null and _atlas_layer.header_node() != null:
		entries.append({"node": _atlas_layer.header_node(), "render_priority": 20, "index": _layers.size()})
	var ordered: Array = HoloCoordinateStack.sort_layers_by_depth(_camera, entries)
	for entry in ordered:
		var node := entry["node"] as Node3D
		var hit: Dictionary = HoloCoordinateStack.hit_layer(
			_camera, screen_pos, node, HoloLayer.CARD_SIZE * 0.5
		)
		if bool(hit.get("hit", false)):
			if _atlas_layer != null and node == _atlas_layer.header_node():
				_atlas_layer.toggle_pull()
				return
			var layer := node as HoloLayer
			layer.toggle_pull()
			select_node(_layer_kind(layer.layer_id), _layer_node_id(layer.layer_id))
			return
	reset_view()


func layer_count() -> int:
	return _layers.size()


func seat_count() -> int:
	return _seat_count


func camera_node() -> Camera3D:
	return _camera


func get_session() -> Node:
	return _session


func density_state() -> Dictionary:
	return _density


# ── Selection (Slice 7, design §3) ───────────────────────────────────────────

func select_node(kind: String, node_id: String) -> void:
	var node := HoloSelection.find_node(_selection_nodes, kind, node_id)
	if node.is_empty():
		return
	_selection.select(node)
	_start_glide(_focus_position(node), _focus_target(node))
	_apply_focus_dim()
	var layer_id := String(node.get("layer_id", ""))
	if not layer_id.is_empty() and _layer_by_id.has(layer_id):
		(_layer_by_id[layer_id] as HoloLayer).pull_target = 1.0
	selection_changed.emit(_selection.selected())
	_emit_ledger()


func reset_view() -> void:
	_selection.clear()
	_start_glide(_camera_base, Vector3(0.0, 1.0, 0.0))
	_apply_focus_dim()
	selection_changed.emit({})
	_emit_ledger()


func selected_node() -> Dictionary:
	return _selection.selected()


func selection_nodes() -> Array:
	return _selection_nodes.duplicate()


func needs_items() -> Array:
	return _needs_items.duplicate()


func doors() -> Array:
	return _doors.duplicate()


func current_chorus() -> Dictionary:
	return _chorus


func current_events() -> Dictionary:
	return _events


func current_pu() -> Dictionary:
	return _pu


func current_suggestions() -> Dictionary:
	return _suggestions


func _focus_position(node: Dictionary) -> Vector3:
	var focus: Vector3 = node.get("focus", HoloSelection.TABLE_FOCUS)
	return focus + Vector3(0.0, 4.5, 6.0)


func _focus_target(node: Dictionary) -> Vector3:
	return node.get("focus", HoloSelection.TABLE_FOCUS)


func _apply_selection_camera() -> void:
	if not _selection.has_selection():
		_camera.position = _camera_base
		_camera.look_at(_camera_target, Vector3.UP)
		return
	var node := _selection.selected()
	_camera.position = _focus_position(node)
	_camera.look_at(_focus_target(node), Vector3.UP)
	_camera_target = _focus_target(node)


func _start_glide(to_pos: Vector3, to_target: Vector3) -> void:
	_glide_from_pos = _camera.position
	_glide_to_pos = to_pos
	_glide_from_target = _camera_target
	_glide_to_target = to_target
	_glide_t = 0.0
	_gliding = true


func _step_glide(delta: float) -> bool:
	_glide_t += delta / 0.9
	var t := clampf(_glide_t, 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	_camera.position = _glide_from_pos.lerp(_glide_to_pos, smooth)
	var target := _glide_from_target.lerp(_glide_to_target, smooth)
	_camera.look_at(target, Vector3.UP)
	if t >= 1.0:
		_gliding = false
		_camera_target = _glide_to_target
	return true


## Non-focused layers and seats dim to 40% but stay visible — context is
## never deleted (design §3.2). Layers with no selection node (terminals,
## Mind View) dim whenever anything is selected.
func _apply_focus_dim() -> void:
	for layer in _layers:
		var l := layer as HoloLayer
		var ident := _layer_selection_id(l.layer_id)
		if ident.is_empty():
			l.set_dimmed(_selection.has_selection())
		else:
			l.set_dimmed(_selection.is_dimmed(ident))
	for seat_id in _seat_labels.keys():
		var dimmed := _selection.has_selection() and not (
			_selection.selected_kind() == "seat" and _selection.selected_id() == String(seat_id)
		)
		_apply_seat_dim(String(seat_id), dimmed)


func _apply_seat_dim(seat_id: String, dimmed: bool) -> void:
	var label := _seat_labels.get(seat_id, null) as Label3D
	if label != null:
		label.modulate = Color(0.34, 0.36, 0.4) if dimmed else Color(0.85, 0.9, 1.0)
	var stored: Dictionary = _seat_mats.get(seat_id, {})
	if stored.is_empty():
		return
	var mat := stored.get("mat", null) as StandardMaterial3D
	if mat == null:
		return
	var factor := HoloSelection.DIMMED_FACTOR if dimmed else 1.0
	mat.albedo_color = (stored.get("albedo", Color.WHITE) as Color) * factor
	mat.emission_energy_multiplier = float(stored.get("energy", 0.8)) * factor


func _layer_kind(layer_id: String) -> String:
	if layer_id.begins_with("rig-"):
		return "rig"
	return "service"


func _layer_node_id(layer_id: String) -> String:
	if layer_id.begins_with("rig-"):
		return layer_id.trim_prefix("rig-")
	match layer_id:
		"studio-health":
			return "studio"
		"gateway-health":
			return "gateway"
		"constellation":
			return "constellation"
		"fleet-bodies":
			return "fleet-bodies"
		"dev-mentor-game":
			return "dev-mentor"
	return layer_id


func _layer_selection_id(layer_id: String) -> Dictionary:
	if layer_id.begins_with("terminal-") or layer_id == "mind-view":
		return {}
	return {"kind": _layer_kind(layer_id), "id": _layer_node_id(layer_id)}


# ── Construction ─────────────────────────────────────────────────────────────

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.5, 0.7)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 20.0, 0.0)
	light.light_energy = 0.8
	light.shadow_enabled = false
	add_child(light)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = HoloCoordinateStack.DEFAULT_FOV_Y_DEGREES
	_camera.near = 0.1
	_camera.far = 100.0
	_camera.position = _camera_base
	_camera.current = true
	add_child(_camera)
	_camera.look_at(_camera_target, Vector3.UP)


func _build_table() -> void:
	var table := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(9.0, 0.2, 6.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.07, 0.12)
	mat.metallic = 0.2
	mat.roughness = 0.8
	mesh.material = mat
	table.mesh = mesh
	table.position = Vector3(0.0, -0.1, 0.0)
	add_child(table)


func _build_companion() -> void:
	# The companion body: the Mind, embodied. Capsule body + sphere head,
	# emissive cyan — the shape the human looks down on, whose internal state
	# the thought-volume above it renders as density.
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.15, 0.8, 1.0)
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.1, 0.7, 1.0)
	body_mat.emission_energy_multiplier = 1.2

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.2
	capsule.material = body_mat
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	add_child(body)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.56
	sphere.material = body_mat
	head.mesh = sphere
	head.position = Vector3(0.0, 1.85, 0.0)
	add_child(head)


func _build_monitor() -> void:
	# The central monitor: the Mind's web. A hologram quad behind the
	# companion plus a pink radial network graph (ImmediateMesh lines) whose
	# node colours are the senses' honest states, rebuilt on each observation.
	var monitor := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 2.1)
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("holo_color", Color(1.0, 0.4, 0.8))
	mat.set_shader_parameter("slice_plane", Vector4(0.0, 1.0, 0.0, -100.0))
	quad.material = mat
	monitor.mesh = quad
	monitor.position = Vector3(0.0, 2.6, -2.85)
	add_child(monitor)

	_web_instance = MeshInstance3D.new()
	_web_instance.position = Vector3.ZERO
	add_child(_web_instance)


func _build_seats() -> void:
	# The war-room floor: one desk per verified seat, ringing the table.
	# Creature posture reflects honest state; not-detected seats get an empty
	# chair with their reason on a label — never a fake creature.
	var desk_mat := StandardMaterial3D.new()
	desk_mat.albedo_color = Color(0.10, 0.12, 0.18)
	var chair_mat := StandardMaterial3D.new()
	chair_mat.albedo_color = Color(0.25, 0.25, 0.30)
	var live_mat := StandardMaterial3D.new()
	live_mat.albedo_color = Color(0.2, 0.9, 1.0)
	live_mat.emission_enabled = true
	live_mat.emission = Color(0.1, 0.7, 1.0)
	live_mat.emission_energy_multiplier = 0.8
	var dimmed_mat := StandardMaterial3D.new()
	dimmed_mat.albedo_color = Color(0.45, 0.6, 0.8)
	var degraded_mat := StandardMaterial3D.new()
	degraded_mat.albedo_color = Color(1.0, 0.9, 0.2)
	degraded_mat.emission_enabled = true
	degraded_mat.emission = Color(0.8, 0.7, 0.1)
	degraded_mat.emission_energy_multiplier = 0.8

	_skyclaw_desk_mat = StandardMaterial3D.new()
	_skyclaw_desk_mat.albedo_color = Color(0.10, 0.12, 0.18)
	_skyclaw_desk_mat.emission_enabled = true
	_skyclaw_desk_mat.emission = Color(0.8, 0.7, 0.1)
	_skyclaw_desk_mat.emission_energy_multiplier = 0.8

	var seats: Array = HoloLayerRegistry.seat_defs()
	_seat_count = seats.size()
	for i in seats.size():
		var seat: Dictionary = seats[i]
		var side := 1.0 if i % 2 == 0 else -1.0
		var col := i / 2
		var pos := Vector3(-3.5 + float(col) * 1.0, 0.0, side * 2.6)

		var desk := MeshInstance3D.new()
		var desk_mesh := BoxMesh.new()
		desk_mesh.size = Vector3(1.1, 0.08, 0.7)
		desk_mesh.material = _skyclaw_desk_mat if String(seat.get("id", "")) == "skyclaw" else desk_mat
		desk.mesh = desk_mesh
		desk.position = pos + Vector3(0.0, 0.75, 0.0)
		add_child(desk)
		_seat_anchors[String(seat.get("id", ""))] = desk

		if bool(seat.get("creature", false)):
			# One material instance per seat (not the shared base): selection
			# dimming scales this seat's material without dimming the others.
			var creature_mat: StandardMaterial3D = live_mat.duplicate()
			match String(seat.get("state", "")):
				"dimmed":
					creature_mat = dimmed_mat.duplicate()
				"degraded":
					creature_mat = degraded_mat.duplicate()
			_seat_mats[String(seat.get("id", ""))] = {
				"mat": creature_mat,
				"albedo": creature_mat.albedo_color,
				"energy": creature_mat.emission_energy_multiplier,
			}
			var body := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.22
			capsule.height = 0.7
			capsule.material = creature_mat
			body.mesh = capsule
			body.position = pos + Vector3(0.0, 1.15, side * 0.45)
			add_child(body)
			var head := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.17
			sphere.height = 0.34
			sphere.material = creature_mat
			head.mesh = sphere
			head.position = pos + Vector3(0.0, 1.65, side * 0.45)
			add_child(head)
		else:
			var chair := MeshInstance3D.new()
			var chair_mesh := BoxMesh.new()
			chair_mesh.size = Vector3(0.5, 0.5, 0.5)
			chair_mesh.material = chair_mat
			chair.mesh = chair_mesh
			chair.position = pos + Vector3(0.0, 0.4, side * 0.45)
			add_child(chair)

		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.008
		label.font_size = 16
		label.outline_size = 4
		label.modulate = Color(0.85, 0.9, 1.0)
		label.position = pos + Vector3(0.0, 2.0, 0.0)
		label.text = _seat_label_text(seat)
		add_child(label)
		_seat_labels[String(seat.get("id", ""))] = label


func _build_layers() -> void:
	for def in HoloLayerRegistry.layer_defs():
		var layer := HOLO_LAYER_SCRIPT.new() as HoloLayer
		add_child(layer)
		layer.setup(def, SURFACE_SHADER)
		_layers.append(layer)
		_layer_by_id[String(def.get("id", ""))] = layer


func _build_volume() -> void:
	# The thought-volume: a unit-ish box the raymarcher marches through.
	# NEVER rotated (the shader marches in object space; see the shader).
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.6, 2.6, 2.6)
	_volume_mat = ShaderMaterial.new()
	_volume_mat.shader = VOLUME_SHADER
	_volume_mat.set_shader_parameter("step_size", 0.02)
	_volume_mat.set_shader_parameter("slice_plane", Vector4(0.0, 1.0, 0.0, -100.0))
	mesh.material = _volume_mat
	box.mesh = mesh
	box.position = Vector3(0.0, 3.2, 0.0)
	add_child(box)

	_volume_label = Label3D.new()
	_volume_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_volume_label.pixel_size = 0.01
	_volume_label.font_size = 16
	_volume_label.outline_size = 4
	_volume_label.modulate = Color(0.9, 1.0, 1.0)
	_volume_label.position = Vector3(0.0, 4.8, 0.0)
	add_child(_volume_label)


func _mount_mind() -> void:
	# Mount, don't fork: the Mind lives in its own scene; this room only
	# observes its self-model. auto_observe is true in the scene, so the
	# senses start when the tab is first visited (paint-first-then-probe).
	_session = ENTITY_SESSION_SCENE.instantiate()
	add_child(_session)
	_session.self_model_changed.connect(_on_self_model)
	_model = _session.self_model()


func _mount_dev_mentor() -> void:
	_dev_mentor = DEV_MENTOR_BRIDGE.new()
	add_child(_dev_mentor)
	_dev_mentor.observation_changed.connect(_on_mentor_observation)
	_mentor_observation = _dev_mentor.current_observation()
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(func() -> void: _dev_mentor.observe())
	add_child(timer)


func _observe_after_paint() -> void:
	# First probe waits until frames have been painted (the 39 s lesson:
	# never probe ahead of paint). A one-shot Timer NODE (not an awaited
	# coroutine) so the probe dies with the room if the tab is freed first —
	# no resume-after-free. Dev-Mentor is slow (7.3 s probed), so its 12 s
	# async timeout runs off the paint, never blocking it.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.1
	timer.timeout.connect(_on_paint_timer)
	add_child(timer)
	timer.start()


func _on_paint_timer() -> void:
	if is_instance_valid(_dev_mentor):
		_dev_mentor.observe()
	if is_instance_valid(_fleet_reader):
		_fleet_reader.read_now()
	if is_instance_valid(_atlas_reader):
		_atlas_reader.read_now()
	if is_instance_valid(_chorus_reader):
		_chorus_reader.read_now()
	if is_instance_valid(_events_reader):
		_events_reader.read_now()
	if is_instance_valid(_pu_reader):
		_pu_reader.read_now()
	if is_instance_valid(_suggestions_reader):
		_suggestions_reader.read_now()


# ── Per-frame ────────────────────────────────────────────────────────────────

## Pointer parallax: the camera drifts with the pointer (a query, not an
## ambient animation — it moves only while the pointer moves, and never
## while a node is selected). Returns true when the camera moved.
func _update_camera_parallax() -> bool:
	if not _mouse_in_view:
		return false
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	var uv: Vector2 = _mouse_pos / size
	var next_pos := _camera_base + Vector3((uv.x - 0.5) * 1.2, (0.5 - uv.y) * 0.6, 0.0)
	if next_pos.distance_to(_camera.position) < 0.001:
		return false
	_camera.position = next_pos
	_camera.look_at(_camera_target, Vector3.UP)
	return true


## Event-stepped slice: the plane advances one of SLICE_STEPS positions per
## observation (or per Slice-button press) and then holds. No sweep.
func _update_slice_uniform() -> void:
	if _volume_mat == null:
		return
	var t := float(_slice_step % SLICE_STEPS) / float(SLICE_STEPS)
	var plane := Vector4(0.0, 1.0, 0.0, -100.0)
	match SLICE_AXES[_slice_axis_index]:
		"time":
			plane = Vector4(0.0, 1.0, 0.0, lerpf(1.9, 4.5, t))
		"sense":
			plane = Vector4(1.0, 0.0, 0.0, lerpf(-1.3, 1.3, t))
		"age":
			plane = Vector4(0.0, 0.0, 1.0, lerpf(-1.3, 1.3, t))
	_volume_mat.set_shader_parameter("slice_plane", plane)


func _advance_slice() -> void:
	_slice_step += 1
	_slice_dirty = true


# ── Observations -> layers / density / web / ledger ──────────────────────────

func _mount_fleet_reader() -> void:
	# The fleet snapshot reader: a bounded file read, never a shell. The
	# probe (fleet_feed.ps1, every 5 min) writes the snapshot; this room
	# only reads it, with caps + schema + age.
	_fleet_reader = FLEET_READER.new()
	_fleet_reader.name = "FleetTelemetryReader"
	add_child(_fleet_reader)
	_fleet_reader.telemetry_changed.connect(_on_fleet_telemetry)
	_fleet = _fleet_reader.current_telemetry()


func _mount_atlas_layer() -> void:
	# The Capability Atlas shelf: one node per graded entry, mounted under
	# the room (not a registry layer — the registry counts stay 14).
	_atlas_layer = ATLAS_LAYER_SCRIPT.new() as CapabilityAtlasLayer
	_atlas_layer.name = "CapabilityAtlasLayer"
	add_child(_atlas_layer)


func _mount_chorus_reader() -> void:
	_chorus_reader = CHORUS_READER.new()
	_chorus_reader.name = "ChorusFeedReader"
	add_child(_chorus_reader)
	_chorus_reader.feed_changed.connect(_on_chorus_feed)
	_chorus = _chorus_reader.current_feed()


func _mount_events_reader() -> void:
	_events_reader = EVENTS_READER.new()
	_events_reader.name = "CockpitEventsReader"
	add_child(_events_reader)
	_events_reader.events_changed.connect(_on_events)
	_events = _events_reader.current_events()


func _mount_pu_reader() -> void:
	_pu_reader = PU_READER.new()
	_pu_reader.name = "PuQueueReader"
	add_child(_pu_reader)
	_pu_reader.queue_changed.connect(_on_pu_queue)
	_pu = _pu_reader.current_queue()


func _mount_suggestions_reader() -> void:
	_suggestions_reader = SUGGESTIONS_READER.new()
	_suggestions_reader.name = "CockpitSuggestionsReader"
	add_child(_suggestions_reader)
	_suggestions_reader.suggestions_changed.connect(_on_suggestions)
	_suggestions = _suggestions_reader.current_suggestions()


func _mount_atlas_reader() -> void:
	# The atlas reader: the static graded file + the fleet-snapshot overlay,
	# bounded file reads with caps + schema + age. Same pattern as the fleet
	# reader; no shell, no network, no POST.
	_atlas_reader = ATLAS_READER.new()
	_atlas_reader.name = "CapabilityAtlasReader"
	add_child(_atlas_reader)
	_atlas_reader.atlas_changed.connect(_on_atlas_changed)
	_atlas = _atlas_reader.current_atlas()


func _on_atlas_changed(_atlas_dict: Dictionary) -> void:
	_atlas = _atlas_reader.current_atlas()
	if _atlas_layer != null:
		_atlas_layer.build_from(_atlas.get("entries", []))
	_emit_ledger()


func _on_fleet_telemetry(_telemetry: Dictionary) -> void:
	_fleet = _fleet_reader.current_telemetry()
	_rebuild_web()
	_refresh_layer_texts()
	_rebuild_selection_nodes()
	_build_needs_items()
	_advance_slice()
	_emit_ledger()


func _on_self_model(_model_dict: Dictionary) -> void:
	_model = _session.self_model()
	_rebuild_density()
	_rebuild_web()
	_refresh_layer_texts()
	_rebuild_selection_nodes()
	_advance_slice()
	_emit_ledger()


func _on_mentor_observation(_observation: Dictionary) -> void:
	_mentor_observation = _dev_mentor.current_observation()
	_refresh_layer_texts()
	_advance_slice()
	_emit_ledger()


func _on_chorus_feed(_feed: Dictionary) -> void:
	_chorus = _chorus_reader.current_feed()
	_refresh_seat_labels()
	_refresh_skyclaw_desk()
	_rebuild_web()
	_rebuild_selection_nodes()
	_build_needs_items()
	_advance_slice()
	_emit_ledger()


func _on_events(_events_dict: Dictionary) -> void:
	_events = _events_reader.current_events()
	_rebuild_selection_nodes()
	_advance_slice()
	tape_changed.emit(_events)
	_emit_ledger()


func _on_pu_queue(_queue: Dictionary) -> void:
	_pu = _pu_reader.current_queue()
	_rebuild_selection_nodes()
	_build_doors()
	_advance_slice()
	_emit_ledger()


func _on_suggestions(_suggestions_dict: Dictionary) -> void:
	_suggestions = _suggestions_reader.current_suggestions()
	suggestions_changed.emit(_suggestions)
	_emit_ledger()


func _rebuild_selection_nodes() -> void:
	_selection_nodes = HoloSelection.build_nodes(_fleet, _model, _chorus, _events, _atlas, _pu)
	# A selected node that vanished from the data clears back to the room.
	if _selection != null and _selection.has_selection():
		var node := HoloSelection.find_node(_selection_nodes, _selection.selected_kind(), _selection.selected_id())
		if node.is_empty():
			_selection.clear()
			_apply_focus_dim()


func _rebuild_density() -> void:
	_density = HoloDensity.build_grid(_model, _simulated_density)
	if _volume_mat != null:
		_volume_mat.set_shader_parameter("density_tex", HoloDensity.make_texture(_density["grid"]))
	if _volume_label != null:
		_volume_label.text = "THOUGHT VOLUME\n" + String(_density.get("label", ""))


func _rebuild_web() -> void:
	if _web_instance == null:
		return
	var sensor: Dictionary = _model.get("sensor", {})
	var gateway: Dictionary = _model.get("gateway", {})
	var constellation: Dictionary = _model.get("constellation", {})
	var bodies: Array = _model.get("fleet_bodies", [])
	var reported := 0
	for entry in bodies:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("state", "")) == "reported_fresh":
			reported += 1
	# Node states: senses are LIVE observations; rig nodes are snapshot
	# states (fleet_feed.ps1, <= 5 min old). CHATDEV / OLLAMA / SKYCLAW are
	# spine observations from the CHORUS feed — the hardcoded literals are
	# gone (Slice 6 §3.3). With no feed they read "unknown", never "live":
	# a live that can never turn red is wallpaper.
	var rigs: Dictionary = _fleet.get("rigs", {})
	var node_states: Array = [
		["STUDIO", String(sensor.get("state", "unknown"))],
		["GATEWAY", String(gateway.get("state", "unknown"))],
		["CONSTELLATION", String(constellation.get("state", "unknown"))],
		["FLEET", "live" if reported > 0 else "unknown"],
		["DEV-MENTOR", String(_mentor_observation.get("state", "unknown"))],
		["CHATDEV", _spine_service_state("chatdev")],
		["OLLAMA", _spine_service_state("ollama")],
		["SKYCLAW", _spine_service_state("skyclaw")],
		["MSI", String((rigs.get("msi", {}) as Dictionary).get("state", "unknown"))],
		["I3", String((rigs.get("i3", {}) as Dictionary).get("state", "unknown"))],
		["L9", String((rigs.get("l9", {}) as Dictionary).get("state", "unknown"))],
		["XANADU", String((rigs.get("xanadu", {}) as Dictionary).get("state", "unknown"))],
	]
	var center := Vector3(0.0, 2.6, -2.75)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var points: Array[Vector3] = []
	for i in node_states.size():
		var angle := float(i) * TAU / float(node_states.size()) - PI * 0.5
		points.append(center + Vector3(cos(angle) * 0.85, sin(angle) * 0.65, 0.0))
	for i in node_states.size():
		var color := _web_node_color(String(node_states[i][1]))
		_add_web_line(mesh, center, points[i], color)
		_add_web_line(mesh, points[i], points[(i + 1) % node_states.size()], color)
	mesh.surface_end()
	_web_instance.mesh = mesh


## Spine service state from the CHORUS feed: live / unavailable / unknown
## (no feed). Skyclaw's Lane B verdict was "degraded" (2026-11-07); the
## spine is the fresher source when the feed is live.
func _spine_service_state(service_name: String) -> String:
	var spine: Dictionary = _chorus.get("spine", {})
	for svc in spine.get("services", []):
		if typeof(svc) == TYPE_DICTIONARY and String(svc.get("name", "")) == service_name:
			return "live" if bool(svc.get("up", false)) else "unavailable"
	return "unknown"


func _add_web_line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b)


func _web_node_color(state: String) -> Color:
	match state:
		"live":
			return Color(0.2, 1.0, 0.8)
		"stale":
			return Color(0.8, 1.0, 0.3)
		"unavailable":
			return Color(1.0, 0.6, 0.2)
		"degraded":
			return Color(1.0, 0.9, 0.2)
		"dimmed":
			return Color(0.45, 0.6, 0.8)
		_:
			return Color(0.35, 0.35, 0.4)


## A seat's billboard line: live activity (CHORUS smiths, freshest entry
## in the last 3 h) replaces the frozen Lane B verdict; without it the seat
## is labelled with its dated evidence — "seen 2026-11-07", never live.
func _seat_label_text(seat: Dictionary) -> String:
	var seat_id := String(seat.get("id", ""))
	var line2 := String(seat.get("state", "unknown"))
	var line3 := String(seat.get("note", ""))
	var doing := _seat_doing(seat_id)
	if not doing.is_empty():
		line2 = "doing: " + String(doing.get("doing", ""))
		line3 = HoloSelection.age_text(float(doing.get("t", 0.0))) + " · " + String(doing.get("station", ""))
	else:
		line3 = String(seat.get("note", "")) + " — seen 2026-11-07"
	return "%s\n%s\n%s" % [String(seat.get("name", "?")), line2, line3]


func _seat_doing(seat_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_t := 0.0
	var now := Time.get_unix_time_from_system()
	for entry in _chorus.get("smiths", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mapped := String(HoloSelection.SMITHS_SEAT.get(String(entry.get("name", "")).to_lower(), ""))
		if mapped != seat_id:
			continue
		var t := float(entry.get("t", 0.0))
		if now - t > 10800.0:
			continue
		if t > best_t:
			best_t = t
			best = entry
	return best


func _refresh_seat_labels() -> void:
	for seat in HoloLayerRegistry.seat_defs():
		var seat_id := String(seat.get("id", ""))
		var label := _seat_labels.get(seat_id, null) as Label3D
		if label != null:
			label.text = _seat_label_text(seat)


## Skyclaw's desk amplitude is a state value, not a timer: fixed emission
## while the spine reports Skyclaw up, dim while down/unknown. Called on
## chorus feed changes — never per frame (Slice 7).
func _refresh_skyclaw_desk() -> void:
	if _skyclaw_desk_mat == null:
		return
	var state := _spine_service_state("skyclaw")
	_skyclaw_desk_mat.emission_energy_multiplier = 0.8 if state == "live" else 0.35


func _refresh_layer_texts() -> void:
	var sensor: Dictionary = _model.get("sensor", {})
	var gateway: Dictionary = _model.get("gateway", {})
	var constellation: Dictionary = _model.get("constellation", {})
	var bodies: Array = _model.get("fleet_bodies", [])
	_set_layer("studio-health", String(sensor.get("state", "unknown")), _studio_lines(sensor))
	_set_layer("gateway-health", String(gateway.get("state", "unknown")), _gateway_lines(gateway))
	_set_layer("constellation", String(constellation.get("state", "unknown")), _constellation_lines(constellation))
	var reported := 0
	for entry in bodies:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("state", "")) == "reported_fresh":
			reported += 1
	var fleet_state := "live" if reported > 0 else "unknown"
	_set_layer("fleet-bodies", fleet_state, PackedStringArray([
		"fleet bodies: %d reported fresh" % reported,
		"four-rig physical-to-Godot evidence",
	]))
	_set_layer("dev-mentor-game", String(_mentor_observation.get("state", "unknown")), _mentor_lines())
	_set_layer("terminal-msi", "planned", PackedStringArray([
		"PLANNED — broker needed",
		"MSI shell via mssh lanes only",
		"never fake output",
	]))
	_set_layer("terminal-i3", "planned", PackedStringArray([
		"PLANNED — broker needed",
		"i3 SSH hangs from session-0",
		"never fake output",
	]))
	_set_layer("terminal-l9", "planned", PackedStringArray([
		"PLANNED — broker needed",
		"L9 off tailnet",
		"never fake output",
	]))
	_set_layer("terminal-xanadu", "planned", PackedStringArray([
		"PLANNED — broker needed",
		"Xanadu SSH hangs from session-0",
		"never fake output",
	]))
	_set_layer("mind-view", "incoming", PackedStringArray([
		"INCOMING — PR #12 unmerged",
		"fleet map + transcript",
		"not built here — coordinate",
	]))
	_set_layer("rig-msi", _rig_state("msi"), _rig_lines("msi", "MSI-KATANA"))
	_set_layer("rig-i3", _rig_state("i3"), _rig_lines("i3", "DESKTOP-I3ANUVP"))
	_set_layer("rig-l9", _rig_state("l9"), _rig_lines("l9", "DESKTOP-L9V3EMB"))
	_set_layer("rig-xanadu", _rig_state("xanadu"), _rig_lines("xanadu", "Xanadu"))


func _set_layer(layer_id: String, state: String, lines: PackedStringArray) -> void:
	var layer := _layer_by_id.get(layer_id, null) as HoloLayer
	if layer == null:
		return
	layer.set_state(state)
	var title := String(HoloLayerRegistry.layer_def(layer_id).get("title", layer_id))
	layer.set_content(title, lines)


func _studio_lines(sensor: Dictionary) -> PackedStringArray:
	var state := String(sensor.get("state", "unknown"))
	if state == "live" or state == "stale":
		var counts: Dictionary = sensor.get("mission_counts", {})
		var lines := PackedStringArray([
			"missions %d/%d/%d" % [int(counts.get("awaiting", 0)), int(counts.get("running", 0)), int(counts.get("queued", 0))],
			"thermal: " + String(sensor.get("thermal_gate", "")),
		])
		# Slice 7: the 4-service colony_observation the feed already carries
		# (dispatch / lattice-model-router / NuSyQ-Hub / OpenClaw) — the
		# projection used to drop it, leaving the card at three zeros.
		var headline := String(sensor.get("colony_headline", ""))
		if not headline.is_empty():
			lines.append(headline)
		for svc in sensor.get("services", []):
			if typeof(svc) == TYPE_DICTIONARY:
				lines.append("%s %s" % [String(svc.get("id", "?")), String(svc.get("label", "?"))])
		return lines
	if state == "unavailable":
		return PackedStringArray(["UNAVAILABLE", String(sensor.get("error", ""))])
	return PackedStringArray(["unknown — not yet observed"])


func _gateway_lines(gateway: Dictionary) -> PackedStringArray:
	var state := String(gateway.get("state", "unknown"))
	if state == "live" or state == "stale":
		var lines := PackedStringArray(["status " + String(gateway.get("gateway_status", ""))])
		# Slice 7: the card grows from one word to latency (measured by the
		# bridge itself, round-trip ms) — the design's Gateway-card fix.
		var latency := int(gateway.get("latency_ms", -1))
		if latency >= 0:
			lines.append("latency %dms" % latency)
		return lines
	if state == "unavailable":
		return PackedStringArray(["UNAVAILABLE", String(gateway.get("error", ""))])
	return PackedStringArray(["unknown — not yet observed"])


func _constellation_lines(constellation: Dictionary) -> PackedStringArray:
	var state := String(constellation.get("state", "unknown"))
	if state == "live" or state == "stale":
		return PackedStringArray([
			"projects %d" % int(constellation.get("project_count", -1)),
			"age %dms" % int(constellation.get("age_ms", -1)),
		])
	if state == "unavailable":
		return PackedStringArray(["UNAVAILABLE", String(constellation.get("error", ""))])
	return PackedStringArray(["unknown — not yet observed"])


func _rig_state(rig_id: String) -> String:
	var rigs: Dictionary = _fleet.get("rigs", {})
	var rig: Dictionary = rigs.get(rig_id, {})
	return String(rig.get("state", "unknown"))


## Rig card lines from the snapshot. Missing numbers stay "-" (UNKNOWN, never
## zero); the probe's note carries the reason a rig is not live.
func _rig_lines(rig_id: String, rig_name: String) -> PackedStringArray:
	var rigs: Dictionary = _fleet.get("rigs", {})
	var rig: Dictionary = rigs.get(rig_id, {})
	var state := String(rig.get("state", "unknown"))
	if _fleet.is_empty():
		return PackedStringArray(["unknown — no snapshot yet"])
	if state == "live":
		var lines := PackedStringArray()
		var free_mb := int(rig.get("ram_free_mb", -1))
		var total_mb := int(rig.get("ram_total_mb", -1))
		if free_mb >= 0 and total_mb > 0:
			lines.append("RAM %d / %d MB free" % [free_mb, total_mb])
		else:
			lines.append("RAM -")
		var cpu := int(rig.get("cpu_load_pct", -1))
		lines.append("CPU %d%%" % cpu if cpu >= 0 else "CPU -")
		var services: Dictionary = rig.get("services", {})
		var up := 0
		for key in services.keys():
			if String(services.get(key, "")) == "up":
				up += 1
		if not services.is_empty():
			lines.append("services %d/%d up" % [up, services.size()])
		var seats := String(rig.get("seats", ""))
		if not seats.is_empty():
			lines.append("seats: " + seats)
		# Slice 7: the processes block (design §4.14) lands in the fleet
		# feed; until the feed carries it, the card says so — the rig is
		# never shown as process-checked when it was not.
		var processes: Dictionary = rig.get("processes", {})
		if processes.is_empty():
			lines.append("processes: feed predates process block")
		else:
			var names: PackedStringArray = []
			for proc_name in processes.keys():
				names.append(str(proc_name))
			lines.append("processes: " + ", ".join(names))
		var note := String(rig.get("note", ""))
		if not note.is_empty():
			lines.append(note)
		return lines
	if state == "unavailable" or state == "degraded":
		var note := String(rig.get("note", ""))
		if note.is_empty():
			note = "no live source"
		return PackedStringArray([state.to_upper(), note])
	return PackedStringArray(["unknown — not yet observed"])


func _mentor_lines() -> PackedStringArray:
	var state := String(_mentor_observation.get("state", "unknown"))
	if state == "live" or state == "stale":
		return PackedStringArray([
			"game engine: " + ("yes" if bool(_mentor_observation.get("game_engine", false)) else "no"),
			"game sessions: %d" % int(_mentor_observation.get("active_game_sessions", 0)),
			"uptime: %ds" % int(_mentor_observation.get("uptime_s", 0)),
		])
	if state == "unavailable":
		return PackedStringArray(["UNAVAILABLE", String(_mentor_observation.get("error", ""))])
	return PackedStringArray(["unknown — not yet observed"])


## "What needs you" (CHORUS pattern): severity-ranked, each item = what is
## wrong + how long noticed + measured why + copyable next move + owner.
## Severity rank: red (confirmed failure) first, then amber.
func _build_needs_items() -> void:
	var items: Array = []
	for entry in _chorus.get("doctor", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var verdict := String(entry.get("verdict", ""))
		var confirmed := verdict.begins_with("confirmed")
		var evidence: Array = entry.get("evidence", [])
		items.append({
			"severity": "red" if confirmed else "amber",
			"what": String(entry.get("key", "?")),
			"since": String(entry.get("at", "")),
			"why": verdict,
			"move": "Doctor evidence: " + ("; ".join(evidence) if not evidence.is_empty() else "no evidence recorded"),
			"owner": "Keath" if String(entry.get("key", "")).begins_with("i3:") else "MSI Claude",
		})
	var spine: Dictionary = _chorus.get("spine", {})
	for svc in spine.get("services", []):
		if typeof(svc) == TYPE_DICTIONARY and not bool(svc.get("up", true)):
			items.append({
				"severity": "red",
				"what": "spine service down: " + String(svc.get("name", "?")),
				"since": "spine feed age " + str(_chorus.get("age_ms", -1)) + " ms",
				"why": "Dev-Mentor /api/spine/services reports up=false",
				"move": "Check the service on the MSI, then re-probe the spine.",
				"owner": "MSI Claude",
			})
	for waiting in _chorus.get("prs_waiting", []):
		if typeof(waiting) != TYPE_DICTIONARY:
			continue
		items.append({
			"severity": "amber",
			"what": "PR waiting for a reviewer: " + String(waiting.get("repo", "")) + "#" + str(waiting.get("number", 0)),
			"since": "opened " + String(waiting.get("created", "")),
			"why": String(waiting.get("title", "")),
			"move": "Review " + String(waiting.get("url", "")),
			"owner": "reviewer",
		})
	var rigs: Dictionary = _fleet.get("rigs", {})
	for rig_id in ["msi", "i3", "l9", "xanadu"]:
		var rig: Dictionary = rigs.get(rig_id, {})
		var state := String(rig.get("state", "unknown"))
		if state == "stale" or state == "unavailable":
			items.append({
				"severity": "amber",
				"what": "rig " + rig_id.to_upper() + " " + state,
				"since": "fleet snapshot age " + str(_fleet.get("age_ms", -1)) + " ms",
				"why": String(rig.get("note", "no live source")),
				"move": "Wait for the next fleet snapshot (5 min) or check the rig directly.",
				"owner": "fleet feed",
			})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := 0 if String(a.get("severity", "")) == "red" else 1
		var rb := 0 if String(b.get("severity", "")) == "red" else 1
		return ra < rb
	)
	_needs_items = items
	needs_changed.emit(_needs_items)


func _build_doors() -> void:
	var facts := {
		"omnisynapse_checkout": DirAccess.dir_exists_absolute("C:/dev/active/OMNISYNAPSE"),
		"vault_newest_age": _newest_bridge_age(),
		"gitnexus_note": "process check owed via fleet feed processes block",
		"pu": _pu,
	}
	_doors = SYNC_DOORS.build_doors(facts)
	doors_changed.emit(_doors)


## Newest file age under <vault>/Bridge/live — the only vault freshness the
## room can observe without the (not installed) bridge task. Returns
## "unknown" when the directory cannot be read.
func _newest_bridge_age() -> String:
	var dir := DirAccess.open("C:/dev/vault/Bridge/live")
	if dir == null:
		return "unknown (Bridge/live unreadable)"
	var newest := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var mtime := FileAccess.get_modified_time("C:/dev/vault/Bridge/live/" + file_name)
			if mtime > newest:
				newest = mtime
		file_name = dir.get_next()
	dir.list_dir_end()
	if newest <= 0:
		return "no Bridge files found"
	var age_h := (Time.get_unix_time_from_system() - float(newest)) / 3600.0
	if age_h < 1.0:
		return "%d min old" % int(age_h * 60.0)
	if age_h < 48.0:
		return "%.1f h old" % age_h
	return "%d d old" % int(age_h / 24.0)


func _emit_ledger() -> void:
	var lines: PackedStringArray = []
	lines.append("HOLOGRAM — observation_only · actuators 0 · slice: " + SLICE_AXES[_slice_axis_index])
	if _session != null:
		lines.append(_session.status_text())
	lines.append("DENSITY " + String(_density.get("label", "—")))
	lines.append(_fleet_line())
	lines.append(_atlas_line())
	lines.append("TERMINALS broker needed (4) · MIND VIEW incoming (PR #12)")
	lines.append(_tape_line())
	lines.append(_suggestions_line())
	lines.append(SYNC_DOORS.ledger_line(_doors))
	ledger_changed.emit("\n".join(lines))


func _tape_line() -> String:
	var evs: Array = _events.get("events", [])
	if evs.is_empty():
		return "TAPE: no events yet (cockpit_events.json empty or missing)"
	var last: Dictionary = evs[0]
	return "TAPE last: %s %s#%d %s" % [
		String(last.get("kind", "?")), String(last.get("repo", "?")),
		int(last.get("number", 0)), String(last.get("at", "")),
	]


func _suggestions_line() -> String:
	var items: Array = _suggestions.get("suggestions", [])
	var open_count := 0
	for item in items:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("status", "")) == "open":
			open_count += 1
	return "SUGGESTIONS %d open / %d total (docs/suggestions/)" % [open_count, items.size()]


func _fleet_line() -> String:
	if _fleet.is_empty():
		return "FLEET snapshot: no snapshot yet"
	var state := String(_fleet.get("state", "unknown"))
	var age_ms := int(_fleet.get("age_ms", -1))
	var rigs: Dictionary = _fleet.get("rigs", {})
	var parts: PackedStringArray = []
	for rig_id in ["msi", "i3", "l9", "xanadu"]:
		var rig: Dictionary = rigs.get(rig_id, {})
		parts.append("%s %s" % [rig_id.to_upper(), String(rig.get("state", "unknown"))])
	return "FLEET snapshot %s age %dms | %s" % [state, age_ms, " · ".join(parts)]


func _atlas_line() -> String:
	if _atlas.is_empty():
		return "ATLAS: no atlas yet"
	var state := String(_atlas.get("state", "unknown"))
	var entries: Array = _atlas.get("entries", [])
	var slice := current_atlas_slice()
	return "ATLAS %s %d entries · slice: %s · live-probe: %d · unverified: %d" % [
		state, entries.size(), slice,
		int(_atlas.get("live_probe_entries", 0)), int(_atlas.get("unverified_entries", 0)),
	]
