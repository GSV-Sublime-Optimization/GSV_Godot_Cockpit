extends Node3D

## HOLOMIND, Mind View bakeoff entry #1 (i3 Claude). A holographic table you look into.
## Layer 0 SHIP: the fleet as glowing districts; heartbeats travel as light to the library (xanadu).
## Layer 1 CONSTELLATION: every service as a star above its rig; failing ones flicker red.
## Layer 2 MEMORY: past thoughts as holo-cards spiralling upward and fading with age.
## The Mind: a glyph that glides to what it's attending to, raises a card with its newest thought, then puts it away.
## Rules: windowed, never topmost, Esc quits; read-only (one local feed file); 0 actuators; capped frame rate.
## Smoke mode: --fixture=<feed.json> --shot=<png> renders one still for judging, then quits.

const HOLO := preload("res://shaders/holo.gdshader")
const DEFAULT_FEED := "C:/Users/Public/colony/mindview/feed.json"
const MAX_FEED_BYTES := 524288
const LAYER_Y: Array[float] = [0.0, 2.3, 4.6]
const LAYER_NAMES: Array[String] = ["SHIP", "CONSTELLATION", "MEMORY"]
const BODY_PLACES := {
	"xanadu": Vector3(0, 0, 0), "msi": Vector3(-3.6, 0, -2.2), "i3": Vector3(-3.6, 0, 2.4), "l9": Vector3(3.9, 0, 0.2),
}
const BODY_TITLES := {"xanadu": "LIBRARY", "msi": "WORKSHOP", "i3": "ENGINE ROOM", "l9": "HANGAR"}
const C_CALM := Color(0.35, 0.95, 0.65)
const C_WATCH := Color(1.0, 0.72, 0.25)
const C_ALARM := Color(1.0, 0.33, 0.33)
const C_IDLE := Color(0.45, 0.55, 0.75)
const C_HOLO := Color(0.35, 0.75, 1.0)
const LEVEL_ALIASES := {"routine": "calm", "notable": "watch", "alert": "alarm", "critical": "alarm"}

var feed_path: String = DEFAULT_FEED
var shot_path: String = ""
var feed: Dictionary = {}
var feed_note: String = "waiting for the feed"
var focus_layer: int = -1
var background: bool = false

var _cam: Camera3D
var _yaw: float = 0.55
var _pitch: float = 0.62
var _dist: float = 13.5
var _drag: bool = false
var _t: float = 0.0
var _poll: float = 0.0
var _bodies: Dictionary = {}          # id -> {node, mat, label}
var _layer_roots: Array[Node3D] = []
var _packets: Array[Dictionary] = []  # {mesh, from, to, u, speed}
var _stars: Node3D
var _memory: Node3D
var _mind: Node3D
var _mind_target: Vector3 = Vector3(0, 1.2, 0)
var _card: Node3D
var _card_label: Label3D
var _last_event_key: String = ""
var _term: Node3D
var _term_label: Label3D
var _term_focus: String = ""
var _term_shown: float = 0.0   # 0 = put away, 1 = fully raised
var _hud: Label
var _subtitle: Label
var _frames: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--feed=") or arg.begins_with("--fixture="):
			feed_path = arg.get_slice("=", 1)
		elif arg.begins_with("--shot="):
			shot_path = arg.get_slice("=", 1)
		elif arg == "--background":
			background = true
	Engine.max_fps = 30
	get_window().always_on_top = false
	# Renders and measurements must never take focus from whatever the person at the machine is doing.
	if background or shot_path != "":
		get_window().unfocusable = true
	_build_room()
	_build_layers()
	_build_mind()
	_build_hud()
	_read_feed()


# ------------------------------------------------------------------ building

func _holo(color: Color, strength: float = 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HOLO
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("strength", strength)
	return m


func _mesh(mesh: Mesh, mat: Material, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _label(text: String, size: int, color: Color, at: Vector3, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at
	parent.add_child(l)
	return l


func _build_room() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.02, 0.045)
	e.glow_enabled = true
	e.glow_intensity = 1.1
	e.glow_bloom = 0.25
	env.environment = e
	add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	# The holotable: a base disc, rings and a radial grid.
	var table := Node3D.new()
	add_child(table)
	var disc := CylinderMesh.new()
	disc.top_radius = 6.4
	disc.bottom_radius = 6.6
	disc.height = 0.08
	_mesh(disc, _holo(C_HOLO, 0.35), Vector3(0, -0.45, 0), table)
	for r: float in [2.0, 4.0, 6.0]:
		var ring := TorusMesh.new()
		ring.inner_radius = r - 0.015
		ring.outer_radius = r + 0.015
		_mesh(ring, _holo(C_HOLO, 0.5), Vector3(0, -0.4, 0), table)
	# The holographic column: three faint layer planes.
	for i in LAYER_Y.size():
		var root := Node3D.new()
		root.position.y = LAYER_Y[i]
		add_child(root)
		_layer_roots.append(root)
		var plane := TorusMesh.new()
		plane.inner_radius = 6.0
		plane.outer_radius = 6.05
		_mesh(plane, _holo(C_HOLO, 0.25), Vector3.ZERO, root)
		_label("%d · %s" % [i, LAYER_NAMES[i]], 44, Color(0.55, 0.75, 1.0, 0.8), Vector3(-6.3, 0.25, -3.4), root)


func _build_layers() -> void:
	var ship: Node3D = _layer_roots[0]
	for id: String in BODY_PLACES:
		var p: Vector3 = BODY_PLACES[id]
		var mesh: Mesh
		if id == "xanadu":
			var s := SphereMesh.new()
			s.radius = 0.85
			s.height = 1.7
			mesh = s
		else:
			var prism := PrismMesh.new()
			prism.size = Vector3(1.3, 1.2, 1.3)
			mesh = prism
		var mat := _holo(C_IDLE, 0.9)
		var node := _mesh(mesh, mat, p, ship)
		var label := _label("%s\n%s" % [id.to_upper(), BODY_TITLES[id]], 40, Color(0.85, 0.92, 1.0), p + Vector3(0, -1.05, 0), ship)
		_bodies[id] = {"node": node, "mat": mat, "label": label}
		if id != "xanadu":
			var beam := ImmediateMesh.new()
			beam.surface_begin(Mesh.PRIMITIVE_LINES)
			beam.surface_add_vertex(p)
			beam.surface_add_vertex(Vector3.ZERO)
			beam.surface_end()
			_mesh(beam, _holo(C_HOLO, 0.7), Vector3.ZERO, ship)
			for k in 3:
				var dot := SphereMesh.new()
				dot.radius = 0.07
				dot.height = 0.14
				var pk := _mesh(dot, _holo(Color(0.7, 0.95, 1.0), 1.6), p, ship)
				_packets.append({"mesh": pk, "from": p, "to": Vector3.ZERO, "u": k / 3.0, "id": id})
	_stars = Node3D.new()
	_layer_roots[1].add_child(_stars)
	_memory = Node3D.new()
	_layer_roots[2].add_child(_memory)


func _build_mind() -> void:
	_mind = Node3D.new()
	add_child(_mind)
	var core := PrismMesh.new()
	core.size = Vector3(0.8, 1.0, 0.8)
	var top := _mesh(core, _holo(Color(0.9, 0.95, 1.0), 1.4), Vector3(0, 0.35, 0), _mind)
	var bottom := _mesh(core, _holo(Color(0.9, 0.95, 1.0), 1.4), Vector3(0, -0.35, 0), _mind)
	bottom.rotation.z = PI
	top.name = "top"
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.8, 1.0)
	glow.light_energy = 2.0
	glow.omni_range = 4.0
	_mind.add_child(glow)
	for r: float in [1.0, 1.35]:
		var ring := TorusMesh.new()
		ring.inner_radius = r - 0.02
		ring.outer_radius = r + 0.02
		var rm := _mesh(ring, _holo(Color(0.75, 0.9, 1.0), 0.9), Vector3.ZERO, _mind)
		rm.name = "ring%d" % int(r * 100)
	_card = Node3D.new()
	add_child(_card)
	var panel := QuadMesh.new()
	panel.size = Vector2(4.4, 1.5)
	var pm := _mesh(panel, _holo(C_HOLO, 0.35), Vector3.ZERO, _card)
	pm.name = "panel"
	_card_label = Label3D.new()
	_card_label.font_size = 34
	_card_label.pixel_size = 0.0055
	_card_label.width = 760
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_label.position = Vector3(0, 0, 0.02)
	_card_label.no_depth_test = true
	_card_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # the raised thought always faces you
	_card.add_child(_card_label)
	_card.scale = Vector3.ONE * 0.01
	# The terminal the Mind brings up beside whatever it's attending to: that rig's live status, as a console.
	_term = Node3D.new()
	add_child(_term)
	var tq := QuadMesh.new()
	tq.size = Vector2(3.6, 2.2)
	_mesh(tq, _holo(Color(0.3, 1.0, 0.7), 0.22), Vector3.ZERO, _term)
	_term_label = Label3D.new()
	_term_label.font_size = 26
	_term_label.pixel_size = 0.0052
	_term_label.width = 640
	_term_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_term_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_term_label.modulate = Color(0.55, 1.0, 0.75)
	_term_label.position = Vector3(0, 0, 0.02)
	_term_label.no_depth_test = true
	_term_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # console text always reads flat to the viewer
	_term.add_child(_term_label)
	_term.scale = Vector3.ONE * 0.01


func _term_text(id: String) -> String:
	var b: Dictionary = (feed.get("bodies", {}) as Dictionary).get(id, {})
	var lines := PackedStringArray()
	lines.append("$ heartbeat %s   # %s" % [id, String(BODY_TITLES.get(id, ""))])
	lines.append("status   %s" % String(b.get("status", "unknown")).to_upper())
	var failing: Array = b.get("failing", [])
	for n: Variant in failing:
		lines.append("check    %-14s FAIL" % String(n))
	if failing.is_empty():
		lines.append("checks   all passing")
	if b.get("age_s") != null:
		lines.append("last     %d s ago" % int(b.get("age_s")))
	for part in String(b.get("detail", "")).split("; ", false):
		lines.append("vitals   " + part)
	lines.append("$ _")
	return "\n".join(lines)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 12)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0))
	layer.add_child(_hud)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_subtitle)


# ------------------------------------------------------------------ data

func _level(raw: Variant) -> String:
	var l := String(raw).to_lower()
	return String(LEVEL_ALIASES.get(l, l))


func _level_color(level: String) -> Color:
	match level:
		"alarm": return C_ALARM
		"watch": return C_WATCH
		_: return C_CALM


func _read_feed() -> void:
	if not FileAccess.file_exists(feed_path):
		feed_note = "no feed at " + feed_path
		return
	var f := FileAccess.open(feed_path, FileAccess.READ)
	if f == null or f.get_length() > MAX_FEED_BYTES:
		feed_note = "feed unreadable or too large"
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or String((parsed as Dictionary).get("schema", "")) != "colony.mindview-feed/v0":
		feed_note = "feed has an unexpected shape"
		return
	var fresh := parsed as Dictionary
	if not feed.is_empty() and String(fresh.get("at", "")) == String(feed.get("at", "")):
		return   # nothing new: don't rebuild the scene
	feed = fresh
	feed_note = "feed " + String(feed.get("at", "?"))
	_apply_feed()


func _apply_feed() -> void:
	var bodies: Dictionary = feed.get("bodies", {})
	for id: String in _bodies:
		var b: Dictionary = bodies.get(id, {})
		var status := String(b.get("status", "unknown"))
		var col := C_IDLE
		if status == "green":
			col = C_CALM
		elif status == "red":
			col = C_ALARM
		var mat: ShaderMaterial = (_bodies[id] as Dictionary)["mat"]
		mat.set_shader_parameter("tint", col)
		var label: Label3D = (_bodies[id] as Dictionary)["label"]
		var failing: Array = b.get("failing", [])
		label.text = "%s · %s\n%s%s" % [id.to_upper(), BODY_TITLES[id], status.to_upper(),
			("\n" + ", ".join(PackedStringArray(failing))) if not failing.is_empty() else ""]
		label.modulate = col.lightened(0.3)
	_rebuild_stars(bodies)
	_rebuild_memory()
	var events: Array = feed.get("events", [])
	if not events.is_empty():
		var last: Dictionary = events[-1]
		var key := String(last.get("at", "")) + String(last.get("line", ""))
		if key != _last_event_key:
			_last_event_key = key
			_raise_card(last)


func _rebuild_stars(bodies: Dictionary) -> void:
	for c in _stars.get_children():
		c.queue_free()
	for id: String in BODY_PLACES:
		var host: Vector3 = BODY_PLACES[id]
		var b: Dictionary = bodies.get(id, {})
		var failing: Array = b.get("failing", [])
		var names := PackedStringArray()
		for n: Variant in failing:
			names.append(String(n))
		var detail := String(b.get("detail", ""))
		if names.is_empty() and detail == "":
			continue
		# Stars: one per failing check (red), plus one calm star for the rig's vital signs.
		var all := names.duplicate()
		all.append("vitals")
		for i in all.size():
			var ang := TAU * float(i) / float(all.size()) + host.x
			var at := host + Vector3(cos(ang) * 0.9, 0.0, sin(ang) * 0.9)
			var bad := all[i] != "vitals"
			var star := SphereMesh.new()
			star.radius = 0.12 if bad else 0.09
			star.height = star.radius * 2.0
			_mesh(star, _holo(C_ALARM if bad else C_CALM, 1.5), at, _stars)
			var thread := ImmediateMesh.new()
			thread.surface_begin(Mesh.PRIMITIVE_LINES)
			thread.surface_add_vertex(at)
			thread.surface_add_vertex(host + Vector3(0, -LAYER_Y[1] + 0.6, 0))
			thread.surface_end()
			_mesh(thread, _holo(C_HOLO, 0.25), Vector3.ZERO, _stars)
			var tag := _label(all[i] if bad else "vitals", 20, (C_ALARM if bad else C_CALM).lightened(0.3), at + Vector3(0, 0.26, 0), _stars)
			tag.no_depth_test = false
			if not bad:
				tag.set_meta("detail", detail)   # full vitals appear when the constellation layer is focused (key 2)


func _rebuild_memory() -> void:
	for c in _memory.get_children():
		c.queue_free()
	var events: Array = feed.get("events", [])
	# Memory: the last 7 thoughts as small cards on a rising spiral, older ones higher and fainter.
	var n := mini(events.size() - 1, 7)
	for i in n:
		var e: Dictionary = events[events.size() - 2 - i]
		var ang := PI * 0.85 + float(i) * 0.62
		var at := Vector3(cos(ang) * 4.6, 0.15 + float(i) * 0.32, sin(ang) * 4.6)
		var fade := 1.0 - float(i) / 8.0
		var card := QuadMesh.new()
		card.size = Vector2(2.4, 0.42)
		var mi := _mesh(card, _holo(_level_color(_level(e.get("level", ""))), 0.28 * fade), at, _memory)
		mi.look_at_from_position(at, Vector3(0, at.y, 0), Vector3.UP)
		var lbl := _label(String(e.get("line", "")).left(40), 30, Color(0.8, 0.9, 1.0, 0.35 + 0.6 * fade), at, _memory)
		lbl.no_depth_test = false


func _raise_card(e: Dictionary) -> void:
	var focus := String(e.get("focus", feed.get("attention", "xanadu")))
	var host: Vector3 = BODY_PLACES.get(focus, Vector3.ZERO)
	_mind_target = host + Vector3(0, 2.6, 0)   # lifted clear of the rig it's watching
	if focus != _term_focus:
		_term_focus = focus
		_term_shown = 0.0   # the old terminal is put away; the new one rises
	_term_label.text = _term_text(focus)
	var level := _level(e.get("level", ""))
	var who := String(e.get("mind", "?"))
	var model: Variant = e.get("model")
	_card_label.text = "%s%s · %s\n%s" % [who, ("" if model == null else " (" + String(model) + ")"), level.to_upper(), String(e.get("line", ""))]
	_card_label.modulate = _level_color(level).lightened(0.35)
	(_card.get_node("panel") as MeshInstance3D).material_override = _holo(_level_color(level), 0.3)
	_card.scale = Vector3.ONE * 0.01   # it rises from nothing
	_subtitle.text = "“%s”  — %s" % [String(e.get("line", "")), who]


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	# Budget: 30 fps while someone is looking at it, 10 fps in the background (brief: <=5% of one core idle).
	Engine.max_fps = 30 if ((get_window().has_focus() and not background) or shot_path != "") else 10
	_poll -= delta
	if _poll <= 0.0 and shot_path == "":
		_poll = 3.0
		_read_feed()
	# Camera orbit (slow drift unless the person is dragging).
	if not _drag:
		_yaw += delta * 0.05
	_cam.position = Vector3(cos(_yaw) * cos(_pitch), sin(_pitch), sin(_yaw) * cos(_pitch)) * _dist + Vector3(0, 1.6, 0)
	_cam.look_at(Vector3(0, 1.8, 0), Vector3.UP)
	# Bodies breathe; the library turns.
	for id: String in _bodies:
		var n: MeshInstance3D = (_bodies[id] as Dictionary)["node"]
		n.rotation.y += delta * (0.4 if id == "xanadu" else 0.2)
	# Heartbeat packets flow to the library while their rig reports.
	var bodies: Dictionary = feed.get("bodies", {})
	for pk: Dictionary in _packets:
		var st := String((bodies.get(pk["id"], {}) as Dictionary).get("status", "unknown"))
		var m: MeshInstance3D = pk["mesh"]
		m.visible = st == "green" or st == "red"
		pk["u"] = fmod(float(pk["u"]) + delta * 0.22, 1.0)
		m.position = (pk["from"] as Vector3).lerp(pk["to"] as Vector3, float(pk["u"]))
	# The Mind glides to its attention, rings turning; its card rises beside it.
	_mind.position = _mind.position.lerp(_mind_target + Vector3(0, 0.12 * sin(_t * 1.7), 0), clampf(delta * 1.6, 0.0, 1.0))
	for c in _mind.get_children():
		if String(c.name).begins_with("ring"):
			(c as Node3D).rotate_object_local(Vector3(1, 0, 0) if String(c.name) == "ring100" else Vector3(0, 0, 1), delta * 0.9)
	_card.position = _mind.position + Vector3(0, 1.6, 0)
	if _cam.position.distance_to(_card.position) > 0.01:
		_card.look_at(_cam.position, Vector3.UP)
		_card.rotate_object_local(Vector3.UP, PI)
	_card.scale = _card.scale.lerp(Vector3.ONE, clampf(delta * 2.2, 0.0, 1.0))
	_memory.rotation.y += delta * 0.03
	# The terminal rises beside the Mind's attention, facing you, and folds away when attention moves.
	if _term_focus != "":
		_term_shown = minf(1.0, _term_shown + delta * 0.8)
		var host: Vector3 = BODY_PLACES.get(_term_focus, Vector3.ZERO)
		var side := (_cam.position - host).cross(Vector3.UP).normalized()
		_term.position = host + side * 3.3 + Vector3(0, 1.0 + 1.2 * _term_shown, 0)
		if _cam.position.distance_to(_term.position) > 0.01:
			_term.look_at(_cam.position, Vector3.UP)   # squarely facing the viewer
			_term.rotate_object_local(Vector3.UP, PI)
		_term.scale = Vector3(1.0, maxf(0.01, _term_shown), 1.0)
	# Layer focus: the chosen layer bright, others dim.
	for i in _layer_roots.size():
		_layer_roots[i].visible = focus_layer < 0 or focus_layer == i or i == 0
	for c in _stars.get_children():
		if c is Label3D and c.has_meta("detail"):
			(c as Label3D).text = String(c.get_meta("detail")) if focus_layer == 1 else "vitals"
	var vp := get_viewport().get_visible_rect().size
	_subtitle.position = Vector2(vp.x * 0.1, vp.y - 90)
	_subtitle.size = Vector2(vp.x * 0.8, 70)
	_hud.text = "HOLOMIND · Mind View bakeoff entry #1 (i3 Claude) · observation only · 0 actuators · %s\n%s · drag: orbit · wheel: zoom · 1/2/3: layer · 0: all · F11: fullscreen · Esc: quit" % [
		feed_note, ("layer " + LAYER_NAMES[focus_layer]) if focus_layer >= 0 else "all layers"]
	if shot_path != "" and _t > 4.0:
		_shoot()


func _shoot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("HOLOMIND_SHOT ", shot_path, " ", img.get_width(), "x", img.get_height(), " frames=", _frames)
	get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			get_tree().quit(0)
		elif k == KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		elif k >= KEY_0 and k <= KEY_3:
			focus_layer = (k - KEY_1) if k != KEY_0 else -1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(6.0, _dist - 0.6)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(24.0, _dist + 0.6)
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.004, 0.1, 1.35)
