extends PanelContainer

## HYPERSPACE: a genuinely 3D work-oriented colony projection.
## Every selectable mesh is bound to an observed owning source or visibly unknown rig.
## Clicking opens the real workstation resource; composing still passes through Studio.
## No canvas-generated "active agent" or synthetic work can become execution authority.

signal resource_activated(meta: Dictionary)
signal compose_requested(context: Dictionary)
signal refresh_requested

const PROJECTION = preload("res://scripts/workstation/WorkbenchSpatialProjection.gd")
const ARCH = preload("res://scripts/workstation/WorkbenchHoloArchitecture.gd")
const ATLAS = preload("res://scripts/workstation/WorkbenchAtlasBridge.gd")
const CAPSULE = preload("res://scripts/workstation/WorkbenchAgentCapsule.gd")

var _snapshot: Dictionary = {}
var _capabilities: Array[Dictionary] = []
var _atlas_source := "not_connected"
var _export_button: Button
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
var _links: Array[Dictionary] = []
var _architecture: Dictionary = {}
var _focus_button: Button
var _refresh_button: Button
var _time_slider: HSlider
var _time_check: CheckButton
var _time_label: Label
var _cinematic := false
var _focus_target := Vector3(0, 0.5, 0)
var _camera_focus := Vector3(0, 0.5, 0)
var _clock := 0.0
var _selected := ""
var _yaw := 0.0
var _pitch := 0.72
var _distance := 18.0
var _down := Vector2.ZERO
var _dragged := false
var _mouse_held := false
var _orbiting := false

func _ready() -> void:
	_build_ui()
	_build_world()
	_load_atlas()
	_update_camera()

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
	title.text = "Ξ  HYPERSPACE   /   COLONY HOLOGRAPHIC THEATRE"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#7cddf6"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_lens = OptionButton.new()
	for name in ["ALL DOMAINS", "FLEET", "PROJECTS", "MISSIONS", "SERVICES", "GAMES", "CAPABILITY ATLAS"]:
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
	var atlas_reload := Button.new()
	atlas_reload.text = "LOAD ATLAS"
	atlas_reload.tooltip_text = "Schema-pinned local snapshot; not authenticated tool admission"
	atlas_reload.pressed.connect(_load_atlas)
	header.add_child(atlas_reload)
	var reset := Button.new()
	reset.text = "RECALL ORBIT"
	reset.pressed.connect(func():
		_yaw = 0.0
		_pitch = 0.72
		_distance = 18.0
		_focus_target = Vector3(0, 0.5, 0)
		_update_camera())
	header.add_child(reset)
	var orbit := Button.new()
	orbit.text = "CINEMATIC ORBIT"
	orbit.tooltip_text = "Toggle slow presentation-only camera rotation; not a source of agent activity."
	orbit.pressed.connect(func(): _cinematic = not _cinematic)
	header.add_child(orbit)
	var observe := Button.new()
	_refresh_button = observe
	observe.text = "↻  RE-OBSERVE"
	observe.tooltip_text = "Request a fresh bounded read of the owning Studio API. Never starts a job."
	observe.pressed.connect(func(): refresh_requested.emit())
	header.add_child(observe)
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
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.disable_3d = false
	_viewport.gui_disable_input = true
	_display.add_child(_viewport)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color("#93a9bb"))
	_status.text = "AWAITING STUDIO. Grey structures are UNKNOWN, not offline."
	left.add_child(_status)
	var temporal := HBoxContainer.new()
	temporal.add_theme_constant_override("separation", 10)
	left.add_child(temporal)
	_time_check = CheckButton.new()
	_time_check.text = "4D  /  SOURCE-TIME SHEAR"
	_time_check.tooltip_text = "Slice recorded mission update timestamps only, never reconstructed past states."
	_time_check.toggled.connect(func(_active): _apply_visibility())
	temporal.add_child(_time_check)
	_time_slider = HSlider.new()
	_time_slider.min_value = 1.0
	_time_slider.max_value = 168.0
	_time_slider.step = 1.0
	_time_slider.value = 168.0
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.value_changed.connect(func(_value): _apply_visibility())
	temporal.add_child(_time_slider)
	_time_label = Label.new()
	_time_label.text = "ALL / 168h"
	_time_label.custom_minimum_size.x = 132
	temporal.add_child(_time_label)

	var side := PanelContainer.new()
	side.custom_minimum_size.x = 250
	row.add_child(side)
	var inspector := VBoxContainer.new()
	inspector.add_theme_constant_override("separation", 10)
	side.add_child(inspector)
	var subheading := Label.new()
	subheading.text = "SOURCE SIGNAL  /  OPERATIONS"
	subheading.add_theme_font_size_override("font_size", 12)
	subheading.add_theme_color_override("font_color", Color("#ffcf72"))
	inspector.add_child(subheading)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = false
	_info.scroll_active = true
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_theme_font_size_override("normal_font_size", 13)
	_info.text = "Select an object in the 3D graph to inspect its owning source and available actions."
	inspector.add_child(_info)
	_open_button = Button.new()
	_open_button.text = "OPEN SOURCE / EVIDENCE"
	_open_button.disabled = true
	_open_button.pressed.connect(_open_selected)
	inspector.add_child(_open_button)
	_compose_button = Button.new()
	_compose_button.text = "PREPARE STUDIO DIAGNOSIS"
	_compose_button.disabled = true
	_compose_button.pressed.connect(_compose_selected)
	inspector.add_child(_compose_button)
	_focus_button = Button.new()
	_focus_button.text = "DIVE INTO SELECTED SIGNAL"
	_focus_button.disabled = true
	_focus_button.pressed.connect(_focus_selected)
	inspector.add_child(_focus_button)
	var next_signal := Button.new()
	next_signal.text = "NEXT SOURCE SIGNAL   TAB"
	next_signal.pressed.connect(_focus_next)
	inspector.add_child(next_signal)
	_export_button = Button.new()
	_export_button.text = "EXPORT AGENT HANDOFF"
	_export_button.disabled = true
	_export_button.tooltip_text = "Copy and locally save versioned, bounded source context for any authorized agent"
	_export_button.pressed.connect(_export_handoff)
	inspector.add_child(_export_button)
	var instructions := Label.new()
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.text = "DRAG orbit   /   WHEEL dive   /   CLICK select   /   F focus\nTAB cycle   /   1-7 decks   /   R re-observe\nFourth dimension = source timestamp only.\nLuminous geometry is illustrative, NOT proof of live execution."
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
	_architecture = ARCH.stage(_viewport)
	_make_orbit(13.0, -4.2, Color("#57416b"))
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

func _load_atlas() -> void:
	var result: Dictionary = ATLAS.read_optional()
	_capabilities.clear()
	if result.get("ok", false):
		for item in result["entries"]:
			_capabilities.append(item.duplicate(true))
		_atlas_source = String(result.get("source", "snapshot"))
	else:
		_atlas_source = "NOT CONNECTED / " + String(result.get("reason", "unknown"))
	if _scene != null:
		_render()

func _render() -> void:
	for child in _scene.get_children():
		_scene.remove_child(child)
		child.queue_free()
	_meshes.clear()
	_links.clear()
	_graph = PROJECTION.project(_snapshot, _capabilities, _atlas_source)
	var lookup: Dictionary = {}
	for entry in _graph.get("nodes", []):
		var id: String = entry["key"]
		lookup[id] = entry
		_meshes[id] = ARCH.object(_scene, entry, PROJECTION.color_for(entry["status"]))
	for link in _graph.get("edges", []):
		var a: String = link["from"]
		var b: String = link["to"]
		if lookup.has(a) and lookup.has(b):
			var relation: Node3D = ARCH.evidence_link(_scene, lookup[a]["position"], lookup[b]["position"])
			_links.append({"root": relation, "from": a, "to": b})
	_apply_visibility()
	_refresh_inspector()

func _apply_visibility() -> void:
	if _lens == null or _time == null:
		return
	var selected_domain: String = ["all", "rig", "project", "mission", "service", "game", "capability"][_lens.selected]
	for id in _meshes:
		var item: Dictionary = _meshes[id]
		var entry: Dictionary = item["entry"]
		var domain_ok: bool = (selected_domain == "all" or entry["kind"] == selected_domain
			or (selected_domain == "game" and entry.get("game", false)))
		var time_ok := true
		if entry["kind"] == "mission" and (_time.selected > 0 or (_time_check != null and _time_check.button_pressed)):
			var stamp := String(entry.get("updated_at", ""))
			if stamp.length() < 20 or not stamp.ends_with("Z"):
				time_ok = false
			else:
				var age := Time.get_unix_time_from_system() - Time.get_unix_time_from_datetime_string(stamp)
				var maximum := 86400.0 if _time.selected == 1 else 3600.0 if _time.selected == 2 else 604800.0
				if _time_check != null and _time_check.button_pressed:
					maximum = minf(maximum, _time_slider.value * 3600.0)
				time_ok = age >= 0.0 and age <= maximum
		item["root"].visible = domain_ok and time_ok
	for link in _links:
		link["root"].visible = (_meshes.has(link["from"]) and _meshes.has(link["to"])
			and _meshes[link["from"]]["root"].visible and _meshes[link["to"]]["root"].visible)
	if _time_label != null:
		_time_label.text = ("≤%dh / RECORDS" % int(_time_slider.value)
			if _time_check.button_pressed else "ALL / 168h")
	if not _selected.is_empty() and _meshes.has(_selected) and not _meshes[_selected]["root"].visible:
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
	_status.text += "     |     ATLAS %d STATIC (%d hidden) / %s" % [
		int(_graph.get("atlas_count", 0)), int(_graph.get("atlas_omitted", 0)), _atlas_source]
	_update_label_lod()

func _update_label_lod() -> void:
	## Projection geometry is dense. Do not flood the theatre with billboards.
	## Labels reappear in the relevant lens or near focus; full facts live in inspector.
	for key in _meshes:
		var row: Dictionary = _meshes[key]
		var kind := String(row["entry"]["kind"])
		var focused: bool = key == _selected
		var context_zoom := _distance < 13.0
		var domain_only: bool = (_lens.selected == 2 and kind == "project" or
			_lens.selected == 3 and kind == "mission" or
			_lens.selected == 4 and kind == "service" or
			_lens.selected == 5 and row["entry"].get("game", false) or
			_lens.selected == 6 and kind == "capability")
		row["label"].visible = row["root"].visible and (focused or kind == "rig" or
			(domain_only and context_zoom))
		row["status_label"].visible = row["root"].visible and focused

func _update_camera() -> void:
	if _camera == null:
		return
	var center := _camera_focus
	_camera.position = center + Vector3(
		sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(center, Vector3.UP)

func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance = maxf(5.5, _distance * 0.90)
			_update_camera()
			_update_label_lod()
			_display.accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance = minf(52.0, _distance * 1.11)
			_update_camera()
			_update_label_lod()
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
	elif event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.keycode
		if code == KEY_F:
			_focus_selected()
		elif code == KEY_TAB:
			_focus_next()
		elif code == KEY_R:
			refresh_requested.emit()
		elif code >= KEY_1 and code <= KEY_6:
			_lens.select(code - KEY_1)
			_apply_visibility()
		else:
			return
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
	if not _meshes.has(key) or not _meshes[key]["root"].visible:
		return false
	_select(key)
	return true

func _select(key: String) -> void:
	_selected = key
	for id in _meshes:
		_meshes[id]["halo"].visible = id == key
	_refresh_inspector()
	_update_label_lod()

func _refresh_inspector() -> void:
	if _info == null:
		return
	if not _meshes.has(_selected):
		_info.text = "SELECT A SOURCE OBJECT\n\nRigs occupy the lower deck, projects the upper plane, missions the middle and services the outer ring.\n\nA grey rig means UNKNOWN, not OFFLINE.\n\nMission/project clicks open actual Studio-backed tabs. No agent process is attached by a visual marker."
		_open_button.disabled = true
		_compose_button.disabled = true
		_focus_button.disabled = true
		_export_button.disabled = true
		return
	var entry: Dictionary = _meshes[_selected]["entry"]
	_info.text = "%s\n\n%s\n\nSTATUS\n%s\n\nSOURCE\n%s\n\nIDENTITY\n%s" % [
		String(entry["title"]), String(entry["detail"]), String(entry["status"]).to_upper(),
		String(entry["source"]), String(entry["id"])]
	if entry.get("kind", "") == "capability":
		_info.text += "\n\nDECLARED MACHINE / GRADE / COST\n%s / %s / %s\n\nEVIDENCE\n%s\n\nNOT ADMITTED: REQUALIFY VIA OWNER" % [
			String(entry.get("machine", "unknown")), String(entry.get("grade", "D")),
			String(entry.get("cost_class", "unknown")), String(entry.get("evidence", ""))]
	if entry.has("updated_at") and not String(entry["updated_at"]).is_empty():
		_info.text += "\n\nSOURCE UPDATED\n" + String(entry["updated_at"])
	var kind := String(entry["kind"])
	_export_button.disabled = false
	_open_button.disabled = not ["rig", "project", "mission"].has(kind)
	_open_button.disabled = not ["rig", "project", "mission", "service"].has(kind)
	_compose_button.disabled = not (kind == "project" and entry.get("observed", false)) and not (
		kind == "mission" and not String(entry.get("repo", "")).is_empty())
	_focus_button.disabled = false
	if kind == "rig":
		_info.text += "\n\nPERMISSIONS\nREMOTE WORK NOT ADMITTED; identity not attested."
		if entry.get("resources", {}) is Dictionary:
			var values: Dictionary = entry.get("resources", {})
			for field in ["memory_available_bytes", "system_volume_free_bytes"]:
				var measure: Variant = values.get(field)
				if typeof(measure) == TYPE_INT or typeof(measure) == TYPE_FLOAT:
					_info.text += "\n%s  %.1f GiB (reported)" % [
						"MEM AVAILABLE" if field == "memory_available_bytes" else "SYSTEM DISK FREE",
						float(measure) / 1073741824.0]
			if values.get("age_seconds") != null:
				_info.text += "\nOBSERVATION AGE  %s seconds" % str(values["age_seconds"])
	elif kind == "mission":
		_info.text += "\n\nOWNING REPOSITORY\n" + String(entry.get("repo", "UNREPORTED"))
		_info.text += "\n\nStudio controls approval, runner, receipt and promotion."
	elif kind == "project":
		_info.text += "\n\nREPOSITORY\n" + String(entry.get("repo", ""))
		_info.text += "\n\nLaunchable game: UNVERIFIED / requires game-specific playtest evidence."
	else:
		_info.text += "\n\nThis service has a reported status; no shell or PTY is attached."

func _focus_selected() -> void:
	if not _meshes.has(_selected) or not _meshes[_selected]["root"].visible:
		return
	_focus_target = _meshes[_selected]["root"].position
	_distance = 7.4 if _meshes[_selected]["entry"]["kind"] == "rig" else 6.6
	_cinematic = false
	_update_label_lod()

func _focus_next() -> void:
	var keys: Array[String] = []
	for entry in _graph.get("nodes", []):
		var key: String = entry["key"]
		if _meshes.has(key) and _meshes[key]["root"].visible:
			keys.append(key)
	if keys.is_empty():
		return
	var index := keys.find(_selected)
	var next_key := keys[posmod(index + 1, keys.size())]
	_select(next_key)
	_focus_selected()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += minf(delta, 0.1)
	if _cinematic and not _mouse_held:
		_yaw += delta * 0.07
	_camera_focus = _camera_focus.lerp(_focus_target, clampf(delta * 5.0, 0.0, 1.0))
	_update_camera()
	for item in _architecture.get("animated", []):
		if is_instance_valid(item):
			item.rotate_y(delta * 0.10)
	for record in _meshes.values():
		var status := String(record["entry"]["status"])
		record["spin"].rotate_y(delta * (0.65 if status in ["running", "queued"] else 0.06))
		if record["halo"].visible:
			record["pulse"].scale = Vector3.ONE * (1.0 + 0.09 * sin(_clock * 2.0))

func _export_handoff() -> void:
	if not _meshes.has(_selected) or _export_button.disabled:
		return
	var item: Dictionary = _meshes[_selected]["entry"]
	var result: Dictionary = CAPSULE.build(item, _graph, _snapshot)
	if not result.get("ok", false):
		_status.text = "HANDOFF REFUSED / " + String(result.get("reason", "unknown"))
		return
	var payload := String(result["json"])
	DisplayServer.clipboard_set(payload)
	var path := "user://hyperspace-agent-handoff.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "HANDOFF COPIED / local file unavailable"
		return
	file.store_string(payload)
	file.close()
	_status.text = "HANDOFF COPIED + SAVED LOCALLY / " + ProjectSettings.globalize_path(path)

func _open_selected() -> void:
	if not _meshes.has(_selected) or _open_button.disabled:
		return
	var item: Dictionary = _meshes[_selected]["entry"]
	if item["kind"] == "service":
		resource_activated.emit({"kind": "services", "id": "services", "name": "Observed Services"})
		return
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
