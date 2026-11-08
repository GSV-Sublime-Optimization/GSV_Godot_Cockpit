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
## Budget (HoloBudget): the room runs _process only while something moves,
## and something moves only on input or a real event (Keath's rule: motion =
## real events only). A pull animates until it settles; a pointer move drifts
## the camera once; an observation whose honest state CHANGED plays one slice
## sweep and a short degraded-card pulse. Then _process stops and, with
## OS.low_processor_usage_mode, a still room is not redrawn.
##
## Seats: Lane B's verdicts are one dated MSI probe (2026-11-07), so a seat
## renders "seen 11-07 (not live)", dimmed, unless a FRESH fleet snapshot
## lists its process (HoloLayerRegistry.seat_view).
##
## Pulled-up cards (a seat, a rig, an atlas entry) are offered to HoloTab via
## card_pulled; HoloTab owns the "Assign to seat" action (WarRoomOutbox).

signal ledger_changed(text: String)
## The card the human last pulled up: {kind, id, title, assignable, reason};
## {} when the pulled card was released.
signal card_pulled(card: Dictionary)

const ENTITY_SESSION_SCENE: PackedScene = preload("res://scenes/EntitySession.tscn")
const HOLO_LAYER_SCRIPT: Script = preload("res://scripts/holo/HoloLayer.gd")
const SURFACE_SHADER: Shader = preload("res://shaders/holo_surface.gdshader")
const VOLUME_SHADER: Shader = preload("res://shaders/holo_volume.gdshader")
const DEV_MENTOR_BRIDGE: Script = preload("res://scripts/holo/DevMentorObservationBridge.gd")
const FLEET_READER: Script = preload("res://scripts/holo/FleetTelemetryReader.gd")
const ATLAS_READER: Script = preload("res://scripts/holo/CapabilityAtlasReader.gd")
const ATLAS_LAYER_SCRIPT: Script = preload("res://scripts/holo/CapabilityAtlasLayer.gd")

const SLICE_AXES: PackedStringArray = ["time", "sense", "age"]
## Slice sweep ranges, in world units of the volume's own data axes:
## time cuts vertically (magnitude), sense cuts across sense index (x),
## age cuts across the age axis (z). The slice plane is the human's inquiry
## into the dataset embedded in the volume — a data axis, not just world_y.
## (Slice 4 swept continuously on a 14 s cycle; the sweep now runs once per
## input or real event — see SWEEP_SECONDS.)
## One sweep on input or on a real state change, then the slice rests at the
## start of its range (the whole volume shown).
const SWEEP_SECONDS := 3.0
## How long a real event keeps degraded cards pulsing.
const EVENT_PULSE_SECONDS := 2.0
const SEAT_HIT_HALF := Vector2(0.6, 0.45)
const ASSIGNABLE_KINDS: PackedStringArray = ["seat", "rig", "atlas"]

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
var _simulated_density: bool = false
var _mouse_pos: Vector2 = Vector2.ZERO
var _mouse_in_view: bool = false
var _model: Dictionary = {}
var _mentor_observation: Dictionary = {}
var _density: Dictionary = {}
var _seat_count: int = 0
var _seats: Array = []
var _seat_live_tokens: PackedStringArray = []
var _awake_until_msec: int = 0
var _sweep_start_msec: int = -1
var _state_signature: String = ""
var _atlas_signature: String = ""
var _pulled_card: Dictionary = {}
var _pulled_seat_id: String = ""
var _desk_rest_energy: float = 0.5
var _desk_live_mat: StandardMaterial3D
var _desk_dimmed_mat: StandardMaterial3D


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
	_rebuild_density()
	_rebuild_web()
	_refresh_layer_texts()
	_emit_ledger()
	_observe_after_paint()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var motion := now < _awake_until_msec
	var settled := true
	for layer in _layers:
		var holo := layer as HoloLayer
		holo.motion_enabled = motion
		holo.update_frame(delta, _camera)
		settled = settled and holo.is_settled()
	if _atlas_layer != null:
		_atlas_layer.motion_enabled = motion
		_atlas_layer.update_frame(delta, _camera)
		settled = settled and _atlas_layer.is_settled()
	_billboard_seat_targets()
	var sweeping := _update_slice_uniform(now)
	if _skyclaw_desk_mat != null:
		# The degraded desk pulses only while a real event is shown; at rest
		# it holds a steady glow (the verdict is dated, not a live flicker).
		if motion:
			_skyclaw_desk_mat.emission_energy_multiplier = 0.4 + 0.5 * (0.5 + 0.5 * sin(now / 180.0))
		else:
			_skyclaw_desk_mat.emission_energy_multiplier = _desk_rest_energy
	if settled and not motion and not sweeping:
		# This frame wrote the rest values; nothing moves until the next
		# input or real event wakes the room.
		set_process(false)


## Keep processing for at least `seconds` (0 = until everything settles).
func wake(seconds: float = 0.0) -> void:
	if seconds > 0.0:
		_awake_until_msec = maxi(_awake_until_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
	set_process(true)


func is_idle() -> bool:
	return not is_processing()


func start_sweep() -> void:
	_sweep_start_msec = Time.get_ticks_msec()
	wake()


# ── Public API (called by HoloTab's buttons and pointer forwarding) ──────────

func cycle_slice_axis() -> String:
	_slice_axis_index = (_slice_axis_index + 1) % SLICE_AXES.size()
	start_sweep()
	_emit_ledger()
	return SLICE_AXES[_slice_axis_index]


func current_slice_axis() -> String:
	return SLICE_AXES[_slice_axis_index]


func set_simulated_density(enabled: bool) -> void:
	_simulated_density = enabled
	_rebuild_density()
	wake()
	_emit_ledger()


func is_simulated_density() -> bool:
	return _simulated_density


func pull_all(pulled: bool) -> void:
	for layer in _layers:
		(layer as HoloLayer).pull_target = 1.0 if pulled else 0.0
	if _atlas_layer != null:
		_atlas_layer.set_pulled(pulled)
	wake()


func cycle_atlas_slice() -> String:
	if _atlas_layer == null:
		return "all"
	var view := _atlas_layer.cycle_slice_view()
	wake()
	_emit_ledger()
	return view


func current_atlas_slice() -> String:
	if _atlas_layer == null:
		return "all"
	return _atlas_layer.slice_view


func pull_atlas(pulled: bool) -> void:
	if _atlas_layer != null:
		_atlas_layer.set_pulled(pulled)
	wake()


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
	# Input is an event: drift the camera once and let the cards re-billboard
	# until they settle. No per-frame polling of the mouse.
	if _mouse_in_view and screen_pos.distance_to(_mouse_pos) < 1.0:
		return
	_mouse_pos = screen_pos
	_mouse_in_view = true
	_update_camera_parallax()
	wake()


func pointer_clicked(screen_pos: Vector2) -> void:
	_mouse_pos = screen_pos
	_mouse_in_view = true
	wake()
	# An expanded atlas shelf is the content you pulled up: its cards first.
	if _atlas_layer != null:
		var atlas_hit: Dictionary = _atlas_layer.entry_at(_camera, screen_pos)
		if not atlas_hit.is_empty():
			_set_pulled_card(_card("atlas", String(atlas_hit["id"]), String(atlas_hit["title"])))
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
			else:
				var layer := node as HoloLayer
				layer.toggle_pull()
				if layer.pull_target > 0.5:
					_set_pulled_card(_card(layer.layer_kind, layer.layer_id, layer.card_title()))
				elif String(_pulled_card.get("id", "")) == layer.layer_id:
					_set_pulled_card({})
			return
	for seat in _seats:
		var target := (seat as Dictionary)["target"] as Node3D
		var seat_hit: Dictionary = HoloCoordinateStack.hit_layer(_camera, screen_pos, target, SEAT_HIT_HALF)
		if bool(seat_hit.get("hit", false)):
			var seat_id := String((seat as Dictionary)["id"])
			if _pulled_seat_id == seat_id:
				_set_pulled_card({})
			else:
				_set_pulled_card(_card("seat", seat_id, "Seat: " + String((seat as Dictionary)["name"])))
			return


## Pull up a card by id without a pointer (tests, agents, keyboard):
## kind "seat" / "atlas" / anything else = a registry layer id.
func pull_card(kind: String, card_id: String) -> Dictionary:
	match kind:
		"seat":
			var seat := HoloLayerRegistry.seat_def(card_id)
			if seat.is_empty():
				return {}
			_set_pulled_card(_card("seat", card_id, "Seat: " + String(seat.get("name", card_id))))
		"atlas":
			var found := false
			for raw in (_atlas.get("entries", []) as Array):
				var entry := raw as Dictionary
				if String(entry.get("id", "")) == card_id:
					_set_pulled_card(_card("atlas", card_id, "Atlas: " + String(entry.get("name", card_id))))
					found = true
					break
			if not found:
				return {}
		_:
			var layer := _layer_by_id.get(card_id, null) as HoloLayer
			if layer == null:
				return {}
			layer.pull_target = 1.0
			_set_pulled_card(_card(layer.layer_kind, card_id, layer.card_title()))
	wake()
	return _pulled_card


func pulled_card() -> Dictionary:
	return _pulled_card


func _card(kind: String, card_id: String, title: String) -> Dictionary:
	var assignable := ASSIGNABLE_KINDS.has(kind)
	return {
		"kind": kind,
		"id": card_id,
		"title": title,
		"assignable": assignable,
		"reason": "" if assignable else "only seat, rig and atlas cards are work items",
	}


func _set_pulled_card(card: Dictionary) -> void:
	_pulled_card = card
	_pulled_seat_id = String(card.get("id", "")) if String(card.get("kind", "")) == "seat" else ""
	_refresh_seats()
	card_pulled.emit(card)


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
	dimmed_mat.albedo_color = Color(0.32, 0.38, 0.48)
	_desk_live_mat = live_mat
	_desk_dimmed_mat = dimmed_mat

	_skyclaw_desk_mat = StandardMaterial3D.new()
	_skyclaw_desk_mat.albedo_color = Color(0.10, 0.12, 0.18)
	_skyclaw_desk_mat.emission_enabled = true
	_skyclaw_desk_mat.emission = Color(0.8, 0.7, 0.1)
	_skyclaw_desk_mat.emission_energy_multiplier = _desk_rest_energy

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

		var creature_parts: Array = []
		if bool(seat.get("creature", false)):
			# Every creature starts dimmed: its verdict is a dated probe.
			# _refresh_seats lights it only on a fresh snapshot probe.
			var body := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.22
			capsule.height = 0.7
			body.mesh = capsule
			body.material_override = dimmed_mat
			body.position = pos + Vector3(0.0, 1.15, side * 0.45)
			add_child(body)
			var head := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.17
			sphere.height = 0.34
			head.mesh = sphere
			head.material_override = dimmed_mat
			head.position = pos + Vector3(0.0, 1.65, side * 0.45)
			add_child(head)
			creature_parts = [body, head]
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
		add_child(label)
		# The seat's pull-up target: a card-sized plane at the label, aimed at
		# the camera, hit-tested like every layer (HoloCoordinateStack).
		var target := Node3D.new()
		target.name = "SeatTarget_" + String(seat.get("id", ""))
		target.position = label.position
		add_child(target)
		_seats.append({
			"id": String(seat.get("id", "")),
			"name": String(seat.get("name", "?")),
			"def": seat,
			"label": label,
			"parts": creature_parts,
			"target": target,
		})
	_refresh_seats()


## Seat labels + creature lighting from the dated verdicts and the fresh
## snapshot's seat tokens (HoloLayerRegistry.seat_view).
func _refresh_seats() -> void:
	for seat in _seats:
		var info := seat as Dictionary
		var def: Dictionary = info["def"]
		var view := HoloLayerRegistry.seat_view(def, _seat_live_tokens)
		var label := info["label"] as Label3D
		var pulled := _pulled_seat_id == String(info["id"])
		label.text = "%s%s\n%s\n%s" % [
			"> " if pulled else "",
			String(info["name"]),
			String(view["label"]),
			String(def.get("note", "")),
		]
		label.modulate = Color(0.55, 0.6, 0.7) if bool(view["dimmed"]) else Color(0.85, 0.9, 1.0)
		if pulled:
			label.modulate = Color(1.0, 1.0, 0.7)
		label.pixel_size = 0.011 if pulled else 0.008
		for part in (info["parts"] as Array):
			(part as MeshInstance3D).material_override = _desk_live_mat if String(view["state"]) == "live" else _desk_dimmed_mat


func _billboard_seat_targets() -> void:
	for seat in _seats:
		var target := (seat as Dictionary)["target"] as Node3D
		var b := HoloCoordinateStack.billboard_basis(target.global_position, _camera.global_position)
		target.global_transform = Transform3D(b, target.global_position)


func seat_label_text(seat_id: String) -> String:
	for seat in _seats:
		if String((seat as Dictionary)["id"]) == seat_id:
			return ((seat as Dictionary)["label"] as Label3D).text
	return ""


func seat_render_state(seat_id: String) -> String:
	return String(HoloLayerRegistry.seat_view(HoloLayerRegistry.seat_def(seat_id), _seat_live_tokens)["state"])


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


# ── Per-frame ────────────────────────────────────────────────────────────────

func _update_camera_parallax() -> void:
	if not _mouse_in_view:
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var uv: Vector2 = _mouse_pos / size
	# Head movement becomes a query: a small camera drift reveals the
	# dependencies hidden behind the current layer (real parallax).
	_camera.position = _camera_base + Vector3((uv.x - 0.5) * 1.2, (0.5 - uv.y) * 0.6, 0.0)
	_camera.look_at(_camera_target, Vector3.UP)


## Returns true while a sweep is running. At rest the slice sits at the start
## of its range (whole volume shown).
func _update_slice_uniform(now_msec: int) -> bool:
	if _volume_mat == null:
		return false
	var t := 0.0
	var sweeping := false
	if _sweep_start_msec >= 0:
		t = float(now_msec - _sweep_start_msec) / (SWEEP_SECONDS * 1000.0)
		if t >= 1.0:
			t = 0.0
			_sweep_start_msec = -1
		else:
			sweeping = true
	_set_slice_plane(t)
	return sweeping


func _set_slice_plane(t: float) -> void:
	var plane := Vector4(0.0, 1.0, 0.0, -100.0)
	match SLICE_AXES[_slice_axis_index]:
		"time":
			plane = Vector4(0.0, 1.0, 0.0, lerpf(1.9, 4.5, t))
		"sense":
			plane = Vector4(1.0, 0.0, 0.0, lerpf(-1.3, 1.3, t))
		"age":
			plane = Vector4(0.0, 0.0, 1.0, lerpf(-1.3, 1.3, t))
	_volume_mat.set_shader_parameter("slice_plane", plane)


## A real event = an observation whose honest state changed. Re-reads that
## only refresh ages do not move anything.
func _note_observation() -> void:
	var sig := _current_state_signature()
	if sig == _state_signature:
		return
	_state_signature = sig
	start_sweep()
	wake(EVENT_PULSE_SECONDS)


func _current_state_signature() -> String:
	var parts: PackedStringArray = []
	for key in ["sensor", "gateway", "constellation"]:
		parts.append(String((_model.get(key, {}) as Dictionary).get("state", "unknown")))
	parts.append(String(_mentor_observation.get("state", "unknown")))
	parts.append(String(_fleet.get("state", "unknown")))
	var rigs: Dictionary = _fleet.get("rigs", {})
	for rig_id in ["msi", "i3", "l9", "xanadu"]:
		parts.append(String((rigs.get(rig_id, {}) as Dictionary).get("state", "unknown")))
	parts.append(",".join(_seat_live_tokens))
	parts.append(str(_atlas_layer.live_count() if _atlas_layer != null else 0))
	return "|".join(parts)


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
	var telemetry_state := String(_atlas.get("telemetry_state", "unknown"))
	# Rebuild the shelf only when its content changed (the 60 s poll usually
	# re-reads the same file): no node churn, no redraw, for a no-op read.
	var sig := JSON.stringify(_atlas.get("entries", [])) + "|" + telemetry_state
	if _atlas_layer != null and sig != _atlas_signature:
		_atlas_signature = sig
		_atlas_layer.build_from(_atlas.get("entries", []), telemetry_state)
		wake()
	_note_observation()
	_emit_ledger()


func _on_fleet_telemetry(_telemetry: Dictionary) -> void:
	_fleet = _fleet_reader.current_telemetry()
	_seat_live_tokens = HoloLayerRegistry.fresh_seat_tokens(_fleet)
	_refresh_seats()
	_rebuild_web()
	_refresh_layer_texts()
	_note_observation()
	_emit_ledger()


func _on_self_model(_model_dict: Dictionary) -> void:
	_model = _session.self_model()
	_rebuild_density()
	_rebuild_web()
	_refresh_layer_texts()
	_note_observation()
	_emit_ledger()


func _on_mentor_observation(_observation: Dictionary) -> void:
	_mentor_observation = _dev_mentor.current_observation()
	_refresh_layer_texts()
	_note_observation()
	_emit_ledger()


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
	# Node states: senses are LIVE observations; seat nodes are registry
	# verdicts (Lane B, 2026-11-07) — dated evidence, drawn "dimmed" (seen,
	# not live) unless a fresh snapshot probe lists the seat; rig nodes are
	# snapshot states (fleet_feed.ps1, <= 5 min old).
	var rigs: Dictionary = _fleet.get("rigs", {})
	var node_states: Array = [
		["STUDIO", String(sensor.get("state", "unknown"))],
		["GATEWAY", String(gateway.get("state", "unknown"))],
		["CONSTELLATION", String(constellation.get("state", "unknown"))],
		["FLEET", "live" if reported > 0 else "unknown"],
		["DEV-MENTOR", String(_mentor_observation.get("state", "unknown"))],
		["CHATDEV", seat_render_state("chatdev")],
		["OLLAMA", seat_render_state("ollama")],
		["SKYCLAW", seat_render_state("skyclaw")],
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
		return PackedStringArray([
			"missions %d/%d/%d" % [int(counts.get("awaiting", 0)), int(counts.get("running", 0)), int(counts.get("queued", 0))],
			"thermal: " + String(sensor.get("thermal_gate", "")),
		])
	if state == "unavailable":
		return PackedStringArray(["UNAVAILABLE", String(sensor.get("error", ""))])
	return PackedStringArray(["unknown — not yet observed"])


func _gateway_lines(gateway: Dictionary) -> PackedStringArray:
	var state := String(gateway.get("state", "unknown"))
	if state == "live" or state == "stale":
		return PackedStringArray(["status " + String(gateway.get("gateway_status", ""))])
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


func _emit_ledger() -> void:
	var lines: PackedStringArray = []
	lines.append("HOLOGRAM — observation_only · actuators 0 · slice: " + SLICE_AXES[_slice_axis_index])
	if _session != null:
		lines.append(_session.status_text())
	lines.append("DENSITY " + String(_density.get("label", "—")))
	lines.append(_fleet_line())
	lines.append(_atlas_line())
	lines.append(_seats_line())
	lines.append("TERMINALS broker needed (4) · MIND VIEW incoming (PR #12)")
	ledger_changed.emit("\n".join(lines))


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
	var live := _atlas_layer.live_count() if _atlas_layer != null else 0
	return "ATLAS %s · %d graded · %d live (fresh probe; telemetry %s) · slice: %s · unverified: %d" % [
		state, entries.size(), live, String(_atlas.get("telemetry_state", "unknown")), slice,
		int(_atlas.get("unverified_entries", 0)),
	]


func _seats_line() -> String:
	var live := 0
	var seen := 0
	var absent := 0
	for seat in HoloLayerRegistry.seat_defs():
		var view := HoloLayerRegistry.seat_view(seat, _seat_live_tokens)
		if String(view["state"]) == "live":
			live += 1
		elif String(view["state"]) == "dimmed":
			seen += 1
		else:
			absent += 1
	return "SEATS %d live (probe) · %d seen %s (not live) · %d away / not detected" % [
		live, seen, HoloLayerRegistry.SEAT_VERDICT_DATE, absent,
	]
