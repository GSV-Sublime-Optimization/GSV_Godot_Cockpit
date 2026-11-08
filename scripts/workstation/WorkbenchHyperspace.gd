extends PanelContainer

## HYPERSPACE: a genuinely 3D work-oriented colony projection.
## Every selectable mesh is bound to an observed owning source or visibly unknown rig.
## Clicking opens the real workstation resource; composing still passes through Studio.
## No canvas-generated "active agent" or synthetic work can become execution authority.

signal resource_activated(meta: Dictionary)
signal compose_requested(context: Dictionary)

const PROJECTION = preload("res://scripts/workstation/WorkbenchSpatialProjection.gd")

var _snapshot: Dictionary = {}
var _graph: Dictionary = {}
var _display: SubViewportContainer
var _viewport: SubViewport
var _scene: Node3D
var _camera: Camera3D
var _info: RichTextLabel
var _status: Label
var _lens: OptionButton
var _time: OptionButton
var _open_button: Button
var _compose_button: Button
var _meshes: Dictionary = {}
var _selected := ""
var _yaw := 0.0
var _pitch := 0.38
var _distance := 26.5
var _down := Vector2.ZERO
var _dragged := false
var _mouse_held := false
var _orbiting := false
var _directory: ItemList
var _directory_search: LineEdit
var _directory_keys: Array[String] = []
var _edge_meshes: Array[Dictionary] = []
var _pulse_nodes: Array[Dictionary] = []
var _camera_target := Vector3(0, 0.5, 0)
var _pulse_clock := 0.0
var _pulse_accum := 0.0
var _pulse_caption: Label

func _ready() -> void:
	_build_ui()
	_build_world()
	_render()
	_update_camera()
	set_process(false)

func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if _scene == null:
		return
	_render()

func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var header := HBoxContainer.new()
	left.add_child(header)
	var title := Label.new()
	title.text = "HYPERSPACE    /    SPATIAL WORK GRAPH"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#7cddf6"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_lens = OptionButton.new()
	for name in ["ALL DOMAINS", "FLEET", "PROJECTS", "MISSIONS", "SERVICES"]:
		_lens.add_item(name)
	_lens.tooltip_text = "Change the resource domain, not the underlying state."
	_lens.item_selected.connect(func(_index): _apply_visibility())
	header.add_child(_lens)
	_time = OptionButton.new()
	for name in ["ALL OBSERVED", "UPDATED ≤24H", "UPDATED ≤1H"]:
		_time.add_item(name)
	_time.tooltip_text = "Filter only missions with a real source timestamp. Never manufactures historical snapshots."
	_time.item_selected.connect(func(_index): _apply_visibility())
	header.add_child(_time)
	var reset := Button.new()
	reset.text = "RESET CAMERA"
	reset.pressed.connect(func():
		_yaw = 0.0
		_pitch = 0.38
		_distance = 26.5
		_camera_target = Vector3(0, 0.5, 0)
		_update_camera())
	header.add_child(reset)
	_display = SubViewportContainer.new()
	_display.name = "HyperspaceViewport"
	_display.stretch = true
	_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_display.custom_minimum_size = Vector2(400, 320)
	_display.focus_mode = Control.FOCUS_ALL
	_display.gui_input.connect(_on_view_input)
	left.add_child(_display)
	_viewport = SubViewport.new()
	_viewport.name = "Hyperspace3D"
	_viewport.size = Vector2i(1000, 650)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.disable_3d = false
	_viewport.gui_disable_input = true
	_display.add_child(_viewport)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color("#93a9bb"))
	_status.text = "OBSERVATION NOT RECEIVED. Grey is unknown, not offline."
	left.add_child(_status)
	var shapes := Label.new()
	shapes.text = "SHAPES   ▣ RIG / COMPUTE     ⬡ PROJECT / CODE     ◆ MISSION / WORK     △ SERVICE / INFRA"
	shapes.add_theme_font_size_override("font_size", 11)
	shapes.add_theme_color_override("font_color", Color("#91b8ca"))
	left.add_child(shapes)

	var side := PanelContainer.new()
	side.custom_minimum_size.x = 250
	row.add_child(side)
	var inspector := VBoxContainer.new()
	inspector.add_theme_constant_override("separation", 10)
	side.add_child(inspector)
	var subheading := Label.new()
	subheading.text = "SELECTED OBJECT / ACTIONS"
	subheading.add_theme_font_size_override("font_size", 12)
	subheading.add_theme_color_override("font_color", Color("#ffcf72"))
	inspector.add_child(subheading)
	var finder_title := Label.new()
	finder_title.text = "OBJECT FINDER  /  CLICK ANY NODE"
	finder_title.add_theme_color_override("font_color", Color("#7cddf6"))
	finder_title.add_theme_font_size_override("font_size", 11)
	inspector.add_child(finder_title)
	_directory_search = LineEdit.new()
	_directory_search.placeholder_text = "Search bodies, code, missions..."
	_directory_search.tooltip_text = "Filters this directory only; does not change observations."
	_directory_search.text_changed.connect(func(_query: String): _rebuild_directory())
	inspector.add_child(_directory_search)
	_directory = ItemList.new()
	_directory.name = "SourceObjectFinder"
	_directory.custom_minimum_size = Vector2(0, 164)
	_directory.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_directory.allow_reselect = true
	_directory.item_selected.connect(_on_directory_selected)
	inspector.add_child(_directory)
	var selector_tools := HBoxContainer.new()
	inspector.add_child(selector_tools)
	var previous := Button.new()
	previous.text = "◀ PREV"
	previous.pressed.connect(func(): _cycle_visible(-1))
	selector_tools.add_child(previous)
	var next_button := Button.new()
	next_button.text = "NEXT ▶"
	next_button.pressed.connect(func(): _cycle_visible(1))
	selector_tools.add_child(next_button)
	var focus_button := Button.new()
	focus_button.text = "FOCUS"
	focus_button.tooltip_text = "Move the camera target to the selected source object."
	focus_button.pressed.connect(_focus_selected)
	selector_tools.add_child(focus_button)
	_pulse_caption = Label.new()
	_pulse_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pulse_caption.add_theme_font_size_override("font_size", 11)
	_pulse_caption.add_theme_color_override("font_color", Color("#93a9bb"))
	inspector.add_child(_pulse_caption)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = false
	_info.scroll_active = true
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_theme_font_size_override("normal_font_size", 13)
	_info.text = "Select an object in the 3D graph to inspect its owning source and available actions."
	inspector.add_child(_info)
	_open_button = Button.new()
	_open_button.text = "OPEN VERIFIED RESOURCE"
	_open_button.disabled = true
	_open_button.pressed.connect(_open_selected)
	inspector.add_child(_open_button)
	_compose_button = Button.new()
	_compose_button.text = "COMPOSE STUDIO MISSION"
	_compose_button.disabled = true
	_compose_button.pressed.connect(_compose_selected)
	inspector.add_child(_compose_button)
	var instructions := Label.new()
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.text = "Finder / Prev / Next chooses ANY node; Focus re-centres. Drag to orbit, wheel to zoom, click to inspect.\nHeight = domain; shape = role; colour = reported status; links = verified repos.\nOnly source-reported RUNNING work moves. Unknown does not pulse."
	instructions.add_theme_font_size_override("font_size", 11)
	instructions.add_theme_color_override("font_color", Color("#93a9bb"))
	inspector.add_child(instructions)

func _build_world() -> void:
	_scene = Node3D.new()
	_scene.name = "SourceBoundObjects"
	_viewport.add_child(_scene)
	_camera = Camera3D.new()
	_camera.name = "OrbitCamera"
	_camera.fov = 56.0
	_camera.current = true
	_viewport.add_child(_camera)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#08101b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#648cb4")
	env.ambient_light_energy = 0.55
	world.environment = env
	_viewport.add_child(world)
	_make_orbit(7.5, 4.0, Color("#235978"))
	_make_orbit(4.7, 0.6, Color("#2b5575"))
	_make_orbit(9.5, -3.0, Color("#31415f"))
	_make_orbit(10.2, -0.1, Color("#31425a"))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 7, 6)
	lamp.light_energy = 2.0
	lamp.omni_range = 42.0
	_viewport.add_child(lamp)

func _make_orbit(radius: float, y: float, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(96):
		var a := TAU * float(i) / 96.0
		var b := TAU * float(i + 1) / 96.0
		mesh.surface_add_vertex(Vector3(cos(a) * radius, y, sin(a) * radius))
		mesh.surface_add_vertex(Vector3(cos(b) * radius, y, sin(b) * radius))
	mesh.surface_end()
	var item := MeshInstance3D.new()
	item.mesh = mesh
	_viewport.add_child(item)

func _render() -> void:
	for child in _scene.get_children():
		_scene.remove_child(child)
		child.queue_free()
	_meshes.clear()
	_edge_meshes.clear()
	_pulse_nodes.clear()
	_graph = PROJECTION.project(_snapshot)
	var nodes: Array = _graph.get("nodes", [])
	var lookup: Dictionary = {}
	for entry in nodes:
		var id: String = entry["key"]
		lookup[id] = entry
		var anchor := Node3D.new()
		anchor.name = "Object" + str(_meshes.size())
		anchor.position = entry["position"]
		_scene.add_child(anchor)
		var radius := 0.50 if entry["kind"] == "rig" else 0.37 if entry["kind"] == "mission" else 0.29
		# Geometry encodes actual domain, not a row of indistinguishable status spheres.
		var shape: Mesh
		match String(entry["kind"]):
			"rig":
				var chassis := BoxMesh.new()
				chassis.size = Vector3(0.95, 1.10, 0.67)
				shape = chassis
			"project":
				var repository := CylinderMesh.new()
				repository.top_radius = radius
				repository.bottom_radius = radius
				repository.height = 0.42
				repository.radial_segments = 6
				shape = repository
			"mission":
				var task := SphereMesh.new()
				task.radius = radius
				task.height = radius * 2.0
				task.radial_segments = 4
				task.rings = 2
				shape = task
			_:
				var antenna := CylinderMesh.new()
				antenna.top_radius = 0.06
				antenna.bottom_radius = radius
				antenna.height = 0.85
				antenna.radial_segments = 5
				shape = antenna
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = PROJECTION.color_for(entry["status"])
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 1.8
		var ball := MeshInstance3D.new()
		ball.mesh = shape
		ball.material_override = material
		anchor.add_child(ball)
		var name3d := Label3D.new()
		name3d.text = "%s  /  %s\n%s" % [
			String(entry["kind"]).to_upper(), String(entry["title"]).substr(0, 20),
			String(entry["status"]).to_upper().replace("_", " ")]
		name3d.font_size = 26
		name3d.pixel_size = 0.008
		name3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name3d.no_depth_test = true
		name3d.modulate = Color("#d9edfa")
		name3d.position = Vector3(0, radius + 0.50, 0)
		name3d.visible = entry["kind"] == "rig" or id == _selected
		anchor.add_child(name3d)
		var halo := TorusMesh.new()
		halo.inner_radius = radius * 1.5
		halo.outer_radius = radius * 1.65
		halo.rings = 16
		halo.ring_segments = 32
		var mesh_halo := MeshInstance3D.new()
		mesh_halo.mesh = halo
		var halo_mat := StandardMaterial3D.new()
		halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo_mat.albedo_color = Color("#fff0ae")
		mesh_halo.material_override = halo_mat
		mesh_halo.visible = id == _selected
		anchor.add_child(mesh_halo)
		_meshes[id] = {
			"root": anchor, "halo": mesh_halo, "label": name3d,
			"entry": entry, "body": ball, "material": material}
		if entry["kind"] == "mission" and entry["status"] == "running" and entry.get("observed", false):
			_pulse_nodes.append(_meshes[id])
	for link in _graph.get("edges", []):
		var a: String = link["from"]
		var b: String = link["to"]
		if lookup.has(a) and lookup.has(b):
			var wire := _make_edge(lookup[a]["position"], lookup[b]["position"])
			if wire != null:
				_edge_meshes.append({"node": wire, "from": a, "to": b})
	_apply_visibility()
	_refresh_inspector()
	set_process(not _pulse_nodes.is_empty())
	_request_redraw()

func _make_edge(a: Vector3, b: Vector3) -> MeshInstance3D:
	var difference := b - a
	if difference.length() < 0.01:
		return null
	var tube := CylinderMesh.new()
	tube.top_radius = 0.019
	tube.bottom_radius = 0.019
	tube.height = difference.length()
	tube.radial_segments = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#4c708e")
	var line := MeshInstance3D.new()
	line.name = "VerifiedRepoEdge"
	line.mesh = tube
	line.material_override = mat
	line.position = (a + b) * 0.5
	line.basis = Basis(Quaternion(Vector3.UP, difference.normalized()))
	_scene.add_child(line)
	return line

func _apply_visibility() -> void:
	if _lens == null or _time == null:
		return
	var selected_domain: String = ["all", "rig", "project", "mission", "service"][_lens.selected]
	for id in _meshes:
		var item: Dictionary = _meshes[id]
		var entry: Dictionary = item["entry"]
		var domain_ok: bool = selected_domain == "all" or entry["kind"] == selected_domain
		var time_ok := true
		if entry["kind"] == "mission" and _time.selected > 0:
			var stamp := String(entry.get("updated_at", ""))
			if stamp.length() < 20 or not stamp.ends_with("Z"):
				time_ok = false
			else:
				var age := Time.get_unix_time_from_system() - Time.get_unix_time_from_datetime_string(stamp)
				var maximum := 86400.0 if _time.selected == 1 else 3600.0
				time_ok = age >= 0.0 and age <= maximum
		item["root"].visible = domain_ok and time_ok
	for edge in _edge_meshes:
		edge["node"].visible = _meshes[edge["from"]]["root"].visible and _meshes[edge["to"]]["root"].visible
	if _meshes.has(_selected) and not _meshes[_selected]["root"].visible:
		_select("")
	var feeds: Dictionary = _graph.get("feeds", {})
	var shown := 0
	for item in _meshes.values():
		if item["root"].visible:
			shown += 1
	_status.text = "%d / %d source-bound objects visible     |     BODIES %s    PROJECTS %s    MISSIONS %s    SERVICES %s" % [
		shown, _meshes.size(), feeds.get("body_feed_state", "unknown"),
		feeds.get("project_feed_state", "unknown"),
		feeds.get("mission_feed_state", "unknown"),
		feeds.get("service_feed_state", "unknown")
	]
	var active := 0
	for item in _pulse_nodes:
		if item["root"].visible:
			active += 1
	_pulse_caption.text = ("%d VERIFIED RUNNING MISSION(S): MOTION TRACKS SOURCE STATE" % active) if active > 0 else (
		"QUIET: NO SOURCE-VERIFIED RUNNING MISSION. STATIC DOES NOT MEAN DEAD.")
	_rebuild_directory()
	_request_redraw()

func _update_camera() -> void:
	if _camera == null:
		return
	var center := _camera_target
	_camera.position = center + Vector3(
		sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(center, Vector3.UP)
	_request_redraw()

func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance = maxf(9.0, _distance * 0.90)
			_update_camera()
			_display.accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance = minf(65.0, _distance * 1.11)
			_update_camera()
			_display.accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_held = true
				_down = event.position
				_dragged = false
				_display.grab_focus()
			else:
				if _mouse_held and not _dragged:
					_pick(event.position)
				_mouse_held = false
				_dragged = false
			_display.accept_event()
	elif event is InputEventMouseMotion and _mouse_held:
		if event.position.distance_to(_down) > 5.0:
			_dragged = true
		if _dragged:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch + event.relative.y * 0.007, -1.1, 1.15)
			_update_camera()
		_display.accept_event()

func _pick(pointer: Vector2) -> void:
	if _camera == null or _display.size.x <= 1 or _display.size.y <= 1:
		return
	var pos := Vector2(pointer.x * _viewport.size.x / _display.size.x,
		pointer.y * _viewport.size.y / _display.size.y)
	var chosen := ""
	var nearest := 38.0
	for key in _meshes:
		var item: Dictionary = _meshes[key]
		if not item["root"].visible:
			continue
		var world_pos: Vector3 = item["root"].global_position
		if _camera.is_position_behind(world_pos):
			continue
		var screen: Vector2 = _camera.unproject_position(world_pos)
		var distance := screen.distance_to(pos)
		if distance < nearest:
			nearest = distance
			chosen = key
	_select(chosen)

func select_key(key: String) -> bool:
	if not _meshes.has(key):
		return false
	_select(key)
	return true

func _select(key: String) -> void:
	_selected = key
	for id in _meshes:
		_meshes[id]["halo"].visible = id == key
		_meshes[id]["label"].visible = (_meshes[id]["entry"]["kind"] == "rig" or id == key)
	_refresh_inspector()
	_sync_directory_selection()
	_request_redraw()

func _on_directory_selected(index: int) -> void:
	if index >= 0 and index < _directory_keys.size():
		_select(_directory_keys[index])

func _rebuild_directory() -> void:
	if _directory == null:
		return
	var query := _directory_search.text.strip_edges().to_lower() if _directory_search != null else ""
	_directory.clear()
	_directory_keys.clear()
	for key in _meshes:
		var item: Dictionary = _meshes[key]
		if not item["root"].visible:
			continue
		var entry: Dictionary = item["entry"]
		var label := "%s  %s  ·  %s" % [
			String(entry["kind"]).to_upper(), String(entry["title"]),
			String(entry["status"]).replace("_", " ").to_upper()]
		if not query.is_empty() and not label.to_lower().contains(query):
			continue
		_directory_keys.append(key)
		var index := _directory.add_item(label)
		_directory.set_item_custom_fg_color(index, PROJECTION.color_for(String(entry["status"])))
	_sync_directory_selection()

func _sync_directory_selection() -> void:
	if _directory == null:
		return
	var index := _directory_keys.find(_selected)
	if index >= 0:
		_directory.select(index)
		_directory.ensure_current_is_visible()
	else:
		_directory.deselect_all()

func _cycle_visible(direction: int) -> void:
	if _directory_keys.is_empty():
		return
	var current := _directory_keys.find(_selected)
	var next_index := posmod(current + direction, _directory_keys.size())
	_select(_directory_keys[next_index])

func _focus_selected() -> void:
	if not _meshes.has(_selected):
		return
	_camera_target = _meshes[_selected]["root"].position
	_distance = clampf(_distance, 8.0, 35.0)
	_update_camera()

func _request_redraw() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	# Only an observed RUNNING mission is animated; no synthetic "busy" decoration.
	_pulse_clock += delta
	_pulse_accum += delta
	if _pulse_accum < 0.09:
		return
	_pulse_accum = 0.0
	var visible_activity := false
	for item in _pulse_nodes:
		if not item["root"].visible:
			continue
		visible_activity = true
		item["material"].emission_energy_multiplier = 1.75 + 0.5 * sin(_pulse_clock * 3.1)
		item["body"].position.y = 0.065 * sin(_pulse_clock * 3.1)
	if visible_activity:
		_request_redraw()

func _refresh_inspector() -> void:
	if _info == null:
		return
	if not _meshes.has(_selected):
		_info.text = "SELECT A SOURCE OBJECT\n\nRigs occupy the lower deck, projects the upper plane, missions the middle and services the outer ring.\n\nA grey rig means UNKNOWN, not OFFLINE.\n\nMission/project clicks open actual Studio-backed tabs. No agent process is attached by a visual marker."
		_open_button.disabled = true
		_compose_button.disabled = true
		return
	var entry: Dictionary = _meshes[_selected]["entry"]
	_info.text = "%s\n\n%s\n\nSTATUS\n%s\n\nSOURCE\n%s\n\nIDENTITY\n%s" % [
		String(entry["title"]), String(entry["detail"]), String(entry["status"]).to_upper(),
		String(entry["source"]), String(entry["id"])]
	if entry.has("updated_at") and not String(entry["updated_at"]).is_empty():
		_info.text += "\n\nSOURCE UPDATED\n" + String(entry["updated_at"])
	var kind := String(entry["kind"])
	_open_button.disabled = not ["rig", "project", "mission"].has(kind)
	_compose_button.disabled = not (kind == "project" and entry.get("observed", false)) and not (
		kind == "mission" and not String(entry.get("repo", "")).is_empty())

func _open_selected() -> void:
	if not _meshes.has(_selected) or _open_button.disabled:
		return
	var item: Dictionary = _meshes[_selected]["entry"]
	resource_activated.emit({
		"kind": item["kind"], "id": item["id"], "name": item["title"],
		"role": item["detail"], "source": item["source"],
		"repo": item.get("repo", ""), "branch": item.get("detail", "")
	})

func _compose_selected() -> void:
	if not _meshes.has(_selected) or _compose_button.disabled:
		return
	var item: Dictionary = _meshes[_selected]["entry"]
	var path := String(item.get("repo", ""))
	var context := {"path": path, "risk": "R0"}
	if item["kind"] == "mission":
		context["title"] = "Diagnose " + String(item["title"]).substr(0, 70)
		context["objective"] = "Inspect the owning Studio mission " + String(item["id"]) + ". Identify the actual blocker and provide source-backed next steps without changing repository files."
		context["acceptance"] = "Report the original mission state and evidence\nIdentify a reproducible issue or an explicit unknown\nRecommend a scoped next mission and verification"
	else:
		context["title"] = "Inspect " + String(item["title"]).substr(0, 80)
		context["objective"] = "Inspect this source-observed repository and identify its highest-value testable improvement, its current blockers, and the safest next change without editing project files."
		context["acceptance"] = "Identify a source-backed actionable issue\nState a runnable verification procedure\nReport an explicit no-change conclusion"
	compose_requested.emit(context)
