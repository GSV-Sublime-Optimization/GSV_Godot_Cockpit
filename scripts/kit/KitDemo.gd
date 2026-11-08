extends Node3D
## KIT DEMO: every kit piece driven by a small HARD-CODED SAMPLE dataset (labelled on screen).
## Nothing here is live colony data. Motion = the sample event log replayed once, then stillness.
##
## Exit: Esc quits at any time; the demo also quits by itself after --timeout=<s> (default 120 s).
## Off-screen render: -- --shot=<png>  (moves the window to 12000,12000, renders, saves, quits).
## Background run (for CPU measurement): -- --background  (off-screen, unfocusable, idle loop).
## Cost probe: -- --continuous  redraws every frame at 30 fps (what an always-animating scene costs).
## Renderer: written for the project's GL Compatibility renderer; also runs under Forward+.

const ExtrudedBarScript: Script = preload("res://scripts/kit/ExtrudedBar.gd")
const DataTrailScript: Script = preload("res://scripts/kit/DataTrail.gd")
const FLOOR_SHADER: Shader = preload("res://shaders/kit/district_floor.gdshader")
const RING_SHADER: Shader = preload("res://shaders/kit/stage_rings.gdshader")
const HEAT_SHADER: Shader = preload("res://shaders/kit/heat_field.gdshader")
const EMISSIVE_SHADER: Shader = preload("res://shaders/kit/data_emissive.gdshader")

# Status hues (sRGB). Hue is never the only channel: alert also hatches, unknown is grey + "?".
const C_OK: Color = Color(0.30, 0.84, 1.00)      # cyan
const C_WARN: Color = Color(1.00, 0.66, 0.16)    # amber
const C_ALERT: Color = Color(1.00, 0.27, 0.22)   # red
const C_TEXT: Color = Color(0.80, 0.92, 1.00)
const C_DIM: Color = Color(0.45, 0.55, 0.68)
const C_NAVY: Color = Color(0.012, 0.026, 0.065)

# PR stages: draft, review, changes requested, approved, merge queue (Okabe-Ito derived).
const STAGE_NAMES: Array[String] = ["draft", "review", "changes", "approved", "queued"]
const STAGE_COLORS: Array[Color] = [
	Color(0.50, 0.56, 0.66), Color(0.34, 0.71, 0.91), Color(0.90, 0.62, 0.00),
	Color(0.00, 0.70, 0.52), Color(0.80, 0.47, 0.65)]

# ---------------------------------------------------------------- SAMPLE DATA (hard-coded)
const SAMPLE_DISTRICTS: Array[Dictionary] = [
	{"name": "FORGE", "rect": Vector4(-12.5, -9.5, -1.5, 0.0), "tint": Color(0.22, 0.50, 1.00), "activity": 0.85},
	{"name": "LIBRARY", "rect": Vector4(1.5, -9.5, 12.5, 0.0), "tint": Color(0.55, 0.42, 1.00), "activity": 0.30},
	{"name": "DOCKS", "rect": Vector4(-12.5, 1.5, -1.5, 9.5), "tint": Color(0.20, 0.72, 0.68), "activity": 0.60},
	{"name": "COUNCIL", "rect": Vector4(1.5, 1.5, 12.5, 9.5), "tint": Color(0.42, 0.56, 0.78), "activity": 0.15},
]
# open = open PRs; stages = counts per STAGE_NAMES; has_data false = probe failed (unknown, not zero).
const SAMPLE_REPOS: Array[Dictionary] = [
	{"name": "cockpit", "at": Vector2(-10.8, -6.5), "open": 7, "status": "ok", "urgency": 0.35, "stale": 0.0, "stages": [1, 3, 1, 2, 0], "max": 10},
	{"name": "steward", "at": Vector2(-3.6, -6.5), "open": 3, "status": "ok", "urgency": 0.20, "stale": 0.30, "stages": [0, 2, 0, 1, 0], "max": 10},
	{"name": "forge", "at": Vector2(-7.2, -3.0), "open": 12, "status": "alert", "urgency": 1.0, "stale": 0.0, "stages": [2, 4, 4, 1, 1], "max": 10},
	{"name": "radio", "at": Vector2(4.5, -6.5), "open": 2, "status": "ok", "urgency": 0.10, "stale": 0.85, "stages": [0, 1, 0, 1, 0], "max": 10},
	{"name": "library", "at": Vector2(9.5, -6.5), "open": 5, "status": "warn", "urgency": 0.60, "stale": 0.10, "stages": [1, 1, 2, 1, 0], "max": 10, "selected": true},
	{"name": "atlas", "at": Vector2(4.5, -2.5), "open": 0, "status": "ok", "urgency": 0.05, "stale": 0.0, "stages": [0, 0, 0, 0, 0], "max": 10},
	{"name": "kilo-core", "at": Vector2(9.5, -2.5), "open": -1, "status": "unknown", "urgency": 0.0, "stale": 1.0, "stages": [], "max": 10},
]
# Activity points in DOCKS: x, z, weight (events in the last hour), radius.
const SAMPLE_ACTIVITY: Array[Vector4] = [
	Vector4(-9.5, 4.0, 1.6, 1.3), Vector4(-8.6, 4.6, 1.2, 1.0), Vector4(-9.0, 3.4, 0.9, 0.9),
	Vector4(-5.0, 6.8, 0.8, 1.4), Vector4(-4.2, 7.4, 0.6, 1.0), Vector4(-6.5, 5.5, 0.5, 1.2),
	Vector4(-10.5, 7.8, 0.4, 0.9), Vector4(-3.5, 3.0, 0.3, 0.8)]
# Recorded positions of one mover in COUNCIL: x, z, seconds-ago. Straight lines between them.
const SAMPLE_PATH: Array[Vector3] = [
	Vector3(3.0, 8.5, 118.0), Vector3(3.6, 6.2, 104.0), Vector3(5.2, 5.0, 92.0), Vector3(5.6, 3.2, 80.0),
	Vector3(7.4, 2.6, 66.0), Vector3(8.0, 4.4, 52.0), Vector3(7.2, 6.6, 40.0), Vector3(9.0, 7.6, 28.0),
	Vector3(10.6, 6.4, 17.0), Vector3(10.4, 4.2, 8.0), Vector3(11.2, 3.0, 0.0)]
# Event log replayed once: seconds after start, repo, what happened.
const SAMPLE_EVENTS: Array[Dictionary] = [
	{"t": 0.8, "repo": "forge", "what": "CI failed on PR #212"},
	{"t": 1.6, "repo": "cockpit", "what": "PR #41 opened"},
]
# ----------------------------------------------------------------

var shot_path: String = ""
var background: bool = false
var timeout_s: float = 120.0
var continuous: bool = false

var _elapsed: float = 0.0
var _frames: int = 0
var _next_event: int = 0
var _bars: Dictionary = {}   # repo name -> ExtrudedBar node
var _ticker: Label = null
var _ticker_lines: PackedStringArray = PackedStringArray()
var _font3d: SystemFont = null
var _font2d: SystemFont = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.get_slice("=", 1)
		elif arg == "--background":
			background = true
		elif arg == "--continuous":
			continuous = true
		elif arg.begins_with("--timeout="):
			timeout_s = maxf(arg.get_slice("=", 1).to_float(), 5.0)
	get_window().always_on_top = false
	if shot_path != "" or background:
		get_window().unfocusable = true
		# Godot 4.7.1 ignores CLI --position at startup on this rig: move off-screen ourselves.
		DisplayServer.window_set_position(Vector2i(12000, 12000))
		print("KIT_DEMO window_at=", DisplayServer.window_get_position())
	Engine.max_fps = 30
	# Still scene = no redraws. A shot needs frames to flow, so it opts out.
	OS.low_processor_usage_mode = shot_path == "" and not continuous
	OS.low_processor_usage_mode_sleep_usec = 33000

	_font3d = SystemFont.new()
	_font3d.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Segoe UI", "monospace"])
	_font3d.multichannel_signed_distance_field = true   # SDF text: crisp at any distance/angle
	_font2d = SystemFont.new()
	_font2d.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "monospace"])

	_build_environment()
	_build_floor()
	_build_bars_and_rings()
	_build_heat()
	_build_trail()
	_build_calibration_strip()
	_build_hud()


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	while _next_event < SAMPLE_EVENTS.size() and _elapsed >= float(SAMPLE_EVENTS[_next_event]["t"]):
		var ev: Dictionary = SAMPLE_EVENTS[_next_event]
		var bar: Node3D = _bars.get(String(ev["repo"]), null)
		if bar != null:
			bar.call("pulse")
		_ticker_lines.append("+%.1fs  %s  %s  (sample)" % [float(ev["t"]), String(ev["repo"]), String(ev["what"])])
		_ticker.text = "EVENTS (pulse = an event landed; nothing else moves)\n" + "\n".join(_ticker_lines)
		_next_event += 1
	if shot_path != "" and _elapsed >= 2.0 and _frames >= 20:
		_shoot()
	elif _elapsed >= timeout_s:
		print("KIT_DEMO timeout ", timeout_s, "s, quitting")
		get_tree().quit(0)
	elif _next_event >= SAMPLE_EVENTS.size() and shot_path == "" and _elapsed > 4.0:
		# Event log done: stop the per-frame tick. A timer keeps the timeout honest.
		set_process(false)
		var t: SceneTreeTimer = get_tree().create_timer(maxf(timeout_s - _elapsed, 0.1))
		t.timeout.connect(func() -> void: get_tree().quit(0))


func _input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		get_tree().quit(0)


func _shoot() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(shot_path)
	print("KIT_DEMO_SHOT ", shot_path, " ", img.get_width(), "x", img.get_height(), " err=", err,
		" frames=", _frames, " window_at=", DisplayServer.window_get_position())
	get_tree().quit(0)


# ---------------------------------------------------------------- building

func _build_environment() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = C_NAVY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.07, 0.12)
	# Additive glow with a threshold: only values pushed past it (urgent, events) bloom.
	e.glow_enabled = true
	e.glow_intensity = 2.0
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 0.5
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Depth fog = distance from attention: far rows sink into the navy.
	e.fog_enabled = true
	e.fog_light_color = C_NAVY
	e.fog_density = 0.012
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 44.0
	cam.position = Vector3(0.0, 19.0, 21.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, 2.2), Vector3.UP)


func _build_floor() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(60.0, 50.0)
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	floor_mi.mesh = plane
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	var rects: PackedVector4Array = PackedVector4Array()
	var tints: PackedVector4Array = PackedVector4Array()
	var acts: PackedFloat32Array = PackedFloat32Array()
	for d: Dictionary in SAMPLE_DISTRICTS:
		rects.append(d["rect"])
		var c: Color = (d["tint"] as Color).srgb_to_linear()
		tints.append(Vector4(c.r, c.g, c.b, 1.0))
		acts.append(float(d["activity"]))
	m.set_shader_parameter("district_count", SAMPLE_DISTRICTS.size())
	m.set_shader_parameter("district_rect", rects)
	m.set_shader_parameter("district_tint", tints)
	m.set_shader_parameter("district_activity", acts)
	m.set_shader_parameter("focus_center", Vector2(0.0, 0.0))
	m.set_shader_parameter("focus_radius", 24.0)
	floor_mi.material_override = m
	add_child(floor_mi)
	for d: Dictionary in SAMPLE_DISTRICTS:
		var r: Vector4 = d["rect"]
		var tint: Color = d["tint"]
		var lbl: Label3D = _label3d("%s  ·  activity %.2f" % [String(d["name"]), float(d["activity"])], 64,
			tint.lightened(0.35), Vector3(r.x + 0.35, 0.03, r.w - 0.35))
		lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # printed on the floor
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.modulate.a = 0.9
		lbl.pixel_size = 0.0075


func _build_bars_and_rings() -> void:
	for repo: Dictionary in SAMPLE_REPOS:
		var at: Vector2 = repo["at"]
		var status: String = repo["status"]
		var bar: Node3D = ExtrudedBarScript.new()
		var known: bool = int(repo["open"]) >= 0
		bar.set("value", float(maxi(int(repo["open"]), 0)))
		bar.set("max_value", float(repo["max"]))
		bar.set("unit_height", 0.36)
		bar.set("footprint", 1.0)
		bar.set("status_color", _status_color(status))
		bar.set("urgency", float(repo["urgency"]))
		bar.set("staleness", float(repo["stale"]))
		bar.set("selected", bool(repo.get("selected", false)))
		bar.set("alert_hatch", status == "alert")
		bar.set("has_data", known)
		bar.set("caption", String(repo["name"]))
		bar.set("label_font", _font3d)
		bar.position = Vector3(at.x, 0.0, at.y)
		add_child(bar)
		_bars[String(repo["name"])] = bar
		# Stage ring at the base.
		var quad: PlaneMesh = PlaneMesh.new()
		quad.size = Vector2(3.0, 3.0)
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.mesh = quad
		ring.position = Vector3(at.x, 0.03, at.y)
		var rm: ShaderMaterial = ShaderMaterial.new()
		rm.shader = RING_SHADER
		var counts: PackedFloat32Array = PackedFloat32Array()
		var cols: PackedVector4Array = PackedVector4Array()
		for i: int in range(STAGE_NAMES.size()):
			var stages: Array = repo["stages"]
			counts.append(float(stages[i]) if i < stages.size() else 0.0)
			var lc: Color = STAGE_COLORS[i].srgb_to_linear()
			cols.append(Vector4(lc.r, lc.g, lc.b, 1.0))
		rm.set_shader_parameter("stage_count", STAGE_NAMES.size())
		rm.set_shader_parameter("counts", counts)
		rm.set_shader_parameter("stage_colors", cols)
		rm.set_shader_parameter("has_data", 1.0 if known else 0.0)
		rm.set_shader_parameter("inner_radius", 0.31)
		rm.set_shader_parameter("outer_radius", 0.44)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)


func _build_heat() -> void:
	var r: Vector4 = SAMPLE_DISTRICTS[2]["rect"]
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(r.z - r.x, r.w - r.y)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3((r.x + r.z) * 0.5, 0.02, (r.y + r.w) * 0.5)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = HEAT_SHADER
	var pts: PackedVector4Array = PackedVector4Array()
	for p: Vector4 in SAMPLE_ACTIVITY:
		pts.append(p)
	m.set_shader_parameter("point_count", pts.size())
	m.set_shader_parameter("points", pts)
	m.set_shader_parameter("full_scale", 3.0)   # fixed: 3 events/hour/unit = full ramp
	mi.material_override = m
	add_child(mi)


func _build_trail() -> void:
	var trail: MeshInstance3D = DataTrailScript.new()
	trail.set("trail_color", C_OK)
	trail.set("width", 0.24)
	trail.set("max_age_s", 120.0)
	trail.set("tick_every_s", 30.0)
	add_child(trail)
	var now_s: float = 1000.0
	for s: Vector3 in SAMPLE_PATH:
		trail.call("add_sample", Vector3(s.x, 0.0, s.y), now_s - s.z)
	trail.call("set_now", now_s)
	# The mover itself, at its last REPORTED position.
	var last: Vector3 = SAMPLE_PATH[SAMPLE_PATH.size() - 1]
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	var mover: MeshInstance3D = MeshInstance3D.new()
	mover.mesh = sphere
	mover.position = Vector3(last.x, 0.45, last.y)
	mover.material_override = _emissive(C_OK, 0.8, 0.0)
	add_child(mover)
	_label3d("agent-7 · reported path, last 120 s\nticks every 30 s", 36, C_TEXT, Vector3(last.x - 1.4, 1.5, last.y))


func _build_calibration_strip() -> void:
	# A legend in the world: same shader, one parameter swept. Read it before reading the city.
	for i: int in range(5):
		var t: float = float(i) / 4.0
		var cube: BoxMesh = BoxMesh.new()
		cube.size = Vector3(0.7, 0.7, 0.7)
		var u: MeshInstance3D = MeshInstance3D.new()
		u.mesh = cube
		u.position = Vector3(-11.0 + float(i) * 1.15, 0.35, 11.0)
		var mu: ShaderMaterial = _emissive(C_WARN, t, 0.0)
		mu.set_shader_parameter("half_size", Vector3(0.35, 0.35, 0.35))
		u.material_override = mu
		add_child(u)
		var s: MeshInstance3D = MeshInstance3D.new()
		s.mesh = cube
		s.position = Vector3(-3.0 + float(i) * 1.15, 0.35, 11.0)
		var ms: ShaderMaterial = _emissive(C_ALERT, 0.6, t)
		ms.set_shader_parameter("half_size", Vector3(0.35, 0.35, 0.35))
		s.material_override = ms
		add_child(s)
	_label3d("urgency 0 → 1  (emission, capped)", 36, C_TEXT, Vector3(-8.7, 1.45, 11.0))
	_label3d("staleness 0 → 1  (desaturate)", 36, C_TEXT, Vector3(-0.7, 1.45, 11.0))
	var hues: Array[Color] = [C_OK, C_WARN, C_ALERT, Color(0.42, 0.45, 0.5)]
	var names: PackedStringArray = ["ok", "warn", "alert", "unknown"]
	for i: int in range(hues.size()):
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.3
		sphere.height = 0.6
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = sphere
		mi.position = Vector3(5.0 + float(i) * 1.9, 0.35, 11.0)
		var mh: ShaderMaterial = _emissive(hues[i], 0.45, 0.0)
		if i == 2:
			mh.set_shader_parameter("hatch", 1.0)
		mi.material_override = mh
		add_child(mi)
		_label3d(names[i], 36, C_TEXT, Vector3(5.0 + float(i) * 1.9, 1.15, 11.0))


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var title: Label = _hud_label("HOLOMIND GRAPHICS KIT  ·  SAMPLE DATA (hard-coded, not live)", 22, C_WARN)
	title.position = Vector2(24, 16)
	layer.add_child(title)
	var sub: Label = _hud_label("height = open PRs (1 band per PR)   ring = PR stages   hue = status   glow = urgency (capped)   grey = stale   rim = selected   hatch = alert   ? = unknown (not zero)",
		14, C_DIM)
	sub.position = Vector2(24, 48)
	layer.add_child(sub)
	var stages: Label = _hud_label("", 14, C_DIM)
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(STAGE_NAMES.size()):
		parts.append("[%d] %s" % [i + 1, STAGE_NAMES[i]])
	stages.text = "ring order, clockwise from 12: " + "   ".join(parts) + "   ·   floor: grid = 1 unit, tint = district activity   ·   heat: fixed scale, contours at 25/50/75%"
	stages.position = Vector2(24, 70)
	layer.add_child(stages)
	var swatches: HBoxContainer = HBoxContainer.new()
	swatches.position = Vector2(24, 94)
	swatches.add_theme_constant_override("separation", 6)
	for i: int in range(STAGE_NAMES.size()):
		var sw: ColorRect = ColorRect.new()
		sw.color = STAGE_COLORS[i]
		sw.custom_minimum_size = Vector2(14, 14)
		swatches.add_child(sw)
		var nl: Label = _hud_label(STAGE_NAMES[i] + "   ", 13, C_TEXT)
		swatches.add_child(nl)
	layer.add_child(swatches)
	_ticker = _hud_label("EVENTS (pulse = an event landed; nothing else moves)\n(none yet)", 14, C_TEXT)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_ticker.position = Vector2(24, vp.y - 72)
	layer.add_child(_ticker)
	var quit: Label = _hud_label("Esc quits  ·  auto-quits after %d s" % int(timeout_s), 14, C_DIM)
	quit.position = Vector2(vp.x - 330, vp.y - 36)
	layer.add_child(quit)


# ---------------------------------------------------------------- helpers

func _status_color(status: String) -> Color:
	match status:
		"ok":
			return C_OK
		"warn":
			return C_WARN
		"alert":
			return C_ALERT
	return Color(0.42, 0.45, 0.5)


func _emissive(col: Color, urgency: float, staleness: float) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = EMISSIVE_SHADER
	m.set_shader_parameter("status_color", col)
	m.set_shader_parameter("urgency", urgency)
	m.set_shader_parameter("staleness", staleness)
	return m


func _label3d(text: String, size: int, color: Color, at: Vector3) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.font = _font3d
	l.font_size = size
	l.pixel_size = 0.009
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0.0, 0.01, 0.04, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = at
	add_child(l)
	return l


func _hud_label(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", _font2d)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
