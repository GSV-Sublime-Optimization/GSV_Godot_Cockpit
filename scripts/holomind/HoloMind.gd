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
var _flights: Array[Dictionary] = []   # real events in flight: {node, from, to, t}
var _hb_age: Dictionary = {}             # last seen heartbeat age per rig, to spot a NEW heartbeat
var _order_state: Dictionary = {}        # order id -> last seen status, to spot new orders and receipts
var _flights_primed: bool = false
var _districts: Node3D
var _picks: Array[Dictionary] = []      # everything you can click: {node, title, body, url, ask}
var _focus_point: Vector3 = Vector3(0, 1.8, 0)   # what the camera orbits; click something to move it there
var _focus_want: Vector3 = Vector3(0, 1.8, 0)
var _press_at: Vector2 = Vector2.ZERO
var _inspector: PanelContainer
var _inspector_text: RichTextLabel
var _inspector_bar: HBoxContainer
var _legend: RichTextLabel
var _repo_pos: Dictionary = {}           # repo -> its Forge building position (for relationship lines)
var _text_hidden: bool = false           # H: visuals only (every label and panel hidden) to dial in the look
var _cine: bool = false                  # V: the camera follows the newest real event, then returns
var _cine_target: Node3D = null
var _cine_look: Vector3 = Vector3(0, 1.8, 0)
const FLIGHT_SECONDS := 7.0              # slow enough to follow, eased in and out
const FORGE_AT := Vector3(3.1, 0, -3.7)  # the Forge district: repositories as buildings
const ExtrudedBarScript: Script = preload("res://scripts/kit/ExtrudedBar.gd")   # graphics kit (holo/graphics-kit)
const RING_SHADER: Shader = preload("res://shaders/kit/stage_rings.gdshader")
const RING_STAGES: Array[String] = ["approved", "changes", "needs-review", "stale-review", "draft"]
const STAGE_COLOURS := {"draft": Color(0.45, 0.5, 0.62), "needs-review": Color(0.45, 0.72, 1.0), "stale-review": Color(0.7, 0.6, 1.0),
	"changes": Color(1.0, 0.6, 0.25), "approved": Color(0.35, 0.95, 0.55)}
var _settle: float = 3.0               # seconds of scene updates left; 0 = nothing changed, so nothing is touched or redrawn        # the first feed only records state: nothing flies for old news
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
# The cockpit: agents around the table, a shared channel to talk in, speech in space.
var OUTBOX: String = "C:/Users/Public/colony/mindview/outbox.jsonl"   # follows the feed folder (set in _ready), so the chat works on any OS
const AGENT_RING := 8.3
const HOME_PLACES := {"i3": Vector3(-3.6, 0, 2.4), "msi": Vector3(-3.6, 0, -2.2)}
var _agents_root: Node3D
var _agent_nodes: Dictionary = {}   # agent name -> {node: Node3D, label: Label3D, bubble: Label3D, latest: String, pulse: float}
var _you: Node3D
var _you_bubble: Label3D
var _chat: RichTextLabel
var _typebox: LineEdit
var _speaker: String = "keath"
var _far: Node3D
var _bench: VBoxContainer
var _palette: PanelContainer
var _palette_input: LineEdit
var _palette_list: ItemList
var _palette_cmds: Array[Dictionary] = []
var _palette_shown: Array[Dictionary] = []
var _activity_seen: String = ""
var _now_text: String = ""
var _bench_scroll: ScrollContainer
var _bench_backing: ColorRect
const SEATS: Array[String] = ["claude (i3 seat)", "claude (msi seat)", "gpt-6", "muse", "codex", "any"]
const STATION_FOR: Dictionary = {"suggestion": "anvil", "review": "pegs", "rig": "anvil", "decision": "ledger", "reply": "bell", "merge": "ledger", "fix": "anvil", "triage": "ledger"}
var _hud_clock: float = 0.0
var _sent_local: Array[Dictionary] = []   # what you typed this session, to show sent > delivered > read
var _actions_root: Node3D
const KIND_COLOURS := {"rig": Color(1.0, 0.4, 0.4), "review": Color(0.5, 0.75, 1.0), "decision": Color(1.0, 0.78, 0.35), "reply": Color(0.95, 0.95, 1.0), "merge": Color(0.35, 0.95, 0.55), "fix": Color(1.0, 0.6, 0.25), "triage": Color(0.7, 0.7, 0.8), "suggestion": Color(0.8, 0.6, 1.0)}
var _seen_channel: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--feed=") or arg.begins_with("--fixture="):
			feed_path = arg.get_slice("=", 1)
			if not feed_path.begins_with("res://"):
				OUTBOX = feed_path.get_base_dir().path_join("outbox.jsonl")
		elif arg.begins_with("--shot="):
			shot_path = arg.get_slice("=", 1)
		elif arg == "--background":
			background = true
	Engine.max_fps = 30
	# Redraw only when something changed (borrowed from GPT-6's Cognitive Loom, #18 and #23): a still scene costs ~nothing.
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 33000
	get_window().always_on_top = false
	# Renders and measurements must never take focus from whatever the person at the machine is doing.
	if background or shot_path != "":
		get_window().unfocusable = true
		# Godot 4.7.1 clamps CLI --position onto the screen, so an off-screen render must move itself.
		if shot_path != "" or "--position" in OS.get_cmdline_args():
			DisplayServer.window_set_position(Vector2i(12000, 12000))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--as="):
			_speaker = arg.get_slice("=", 1)
	_build_room()
	_build_layers()
	_build_mind()
	_build_cockpit()
	_build_hud()
	_build_bench()
	_build_palette()
	_build_inspector()
	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)
	_read_feed()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--visuals-only":
			_text_hidden = true
			_apply_text_visibility()
		if arg == "--cine":
			_cine = true
		if arg.begins_with("--select="):   # for receipts: open the inspector on the first thing whose title matches
			var want := arg.get_slice("=", 1).to_lower()
			for i in _picks.size():
				if String(_picks[i].get("title", "")).to_lower().contains(want):
					_select(i)
					break
		if arg == "--legend":
			_legend.visible = true
		if arg.begins_with("--palette="):   # for receipts: render with the palette open on a query
			_open_palette()
			_palette_input.text = arg.get_slice("=", 1)
			_filter_palette()


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
	# Outer space: a procedural starfield and nebula sky (shaders/space.gdshader), deep and slowly twinkling.
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/space.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY   # the background still twinkles; radiance (unused: ambient is a flat colour) is not recomputed per frame
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.06, 0.1)
	e.glow_enabled = true
	e.glow_intensity = 1.3
	e.glow_strength = 1.1
	e.glow_bloom = 0.35
	e.glow_hdr_threshold = 0.7
	env.environment = e
	add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.far = 900.0
	add_child(_cam)
	# Distant worlds for scale: far beyond the table, slowly turning.
	_far = Node3D.new()
	add_child(_far)
	var worlds := [[Vector3(-160, 40, -260), 34.0, Color(0.55, 0.35, 0.85)], [Vector3(220, -30, -180), 18.0, Color(0.3, 0.75, 0.95)],
		[Vector3(90, 95, 300), 9.0, Color(0.95, 0.6, 0.35)]]
	for w: Array in worlds:
		var s := SphereMesh.new()
		s.radius = float(w[1])
		s.height = float(w[1]) * 2.0
		s.radial_segments = 48
		s.rings = 24
		_mesh(s, _holo(w[2] as Color, 0.55), w[0] as Vector3, _far)
		var halo := TorusMesh.new()
		halo.inner_radius = float(w[1]) * 1.5
		halo.outer_radius = float(w[1]) * 1.53
		var hm := _mesh(halo, _holo((w[2] as Color).lightened(0.3), 0.6), w[0] as Vector3, _far)
		hm.rotation = Vector3(0.4, 0.0, 0.25)
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
			# The library is the system's sun: a warm core and a soft corona the heartbeats orbit into.
			var corona := SphereMesh.new()
			corona.radius = 1.5
			corona.height = 3.0
			var cm := _holo(Color(1.0, 0.8, 0.45), 0.35)
			cm.set_shader_parameter("rim_power", 1.2)
			_mesh(corona, cm, p, ship)
			var sun := OmniLight3D.new()
			sun.light_color = Color(1.0, 0.85, 0.6)
			sun.light_energy = 1.5
			sun.omni_range = 9.0
			sun.position = p
			ship.add_child(sun)
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


func _rebuild_actions() -> void:
	# The work queue as cards beside whoever it belongs to: rigs, agents, or you (decisions).
	for c in _actions_root.get_children():
		c.queue_free()
	var groups := {}
	for a: Variant in feed.get("actions", []):
		var d: Dictionary = a
		var where := String(d.get("where", "")).to_lower()
		if not groups.has(where):
			groups[where] = []
		(groups[where] as Array).append(d)
	for where: String in groups:
		var items: Array = groups[where]
		var anchor := Vector3(0, 2.0, 0)
		if where in BODY_PLACES:
			anchor = (BODY_PLACES[where] as Vector3) + Vector3(0, 3.6, 0)
		elif where == "keath" or where == _speaker.to_lower():
			anchor = Vector3.ZERO   # follows you; positioned each frame
		else:
			for name: String in _agent_nodes:
				if name.to_lower().begins_with(where.get_slice(" ", 0)) or where.begins_with(name.to_lower().get_slice(" ", 0)):
					anchor = ((_agent_nodes[name] as Dictionary)["node"] as Node3D).position + _agents_root.position + Vector3(0, 1.5, 0)
					break
		var stack := Node3D.new()
		stack.position = anchor
		stack.set_meta("where", where)
		_actions_root.add_child(stack)
		var shown := mini(items.size(), 3)
		for i in shown:
			var it: Dictionary = items[i]
			var kind := String(it.get("kind", ""))
			var col: Color = KIND_COLOURS.get(kind, Color.WHITE)
			var lbl := _label("● %s  %s" % [kind.to_upper(), String(it.get("title", "")).left(64)], 20, col, Vector3(0, 0.34 * i, 0), stack)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if items.size() > shown:
			_label("+%d more waiting" % (items.size() - shown), 18, Color(0.75, 0.82, 1.0), Vector3(0, 0.34 * shown, 0), stack)


func _build_cockpit() -> void:
	_actions_root = Node3D.new()
	add_child(_actions_root)
	_agents_root = Node3D.new()
	_agents_root.position.y = 1.2
	add_child(_agents_root)
	# You, at the front edge of the table.
	_you = Node3D.new()
	add_child(_you)
	var ym := SphereMesh.new()
	ym.radius = 0.32
	ym.height = 0.64
	_mesh(ym, _holo(Color(1.0, 0.85, 0.55), 1.3), Vector3.ZERO, _you)
	_label(_speaker.to_upper(), 30, Color(1.0, 0.88, 0.6), Vector3(0, -0.6, 0), _you)
	_you_bubble = _label("", 30, Color(1.0, 0.92, 0.75), Vector3(0, 0.75, 0), _you)
	_you_bubble.width = 520
	_you_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _agent_place(i: int, n: int, home: String) -> Vector3:
	if home in HOME_PLACES:
		# Agents that run on a rig stand just outside it, beyond the table's edge, spread apart.
		var h: Vector3 = HOME_PLACES[home]
		var out := Vector3(h.x, 0, h.z).normalized()
		var across := out.cross(Vector3.UP)
		return out * (h.length() + 3.4) + across * (float(i % 3) - 1.0) * 1.6 + Vector3(0, 0.3, 0)
	var ang := PI * 0.15 + TAU * float(i) / float(maxi(n, 1))
	return Vector3(cos(ang) * AGENT_RING, 0.4 * sin(float(i) * 1.7), sin(ang) * AGENT_RING)


func _rebuild_agents() -> void:
	var agents: Array = feed.get("agents", [])
	var names := PackedStringArray()
	for a: Variant in agents:
		names.append(String((a as Dictionary).get("agent", "?")))
	# Agents who stopped appearing fade away; new ones appear; existing ones move to their place.
	for name: String in _agent_nodes.keys():
		if not names.has(name):
			((_agent_nodes[name] as Dictionary)["node"] as Node3D).queue_free()
			_agent_nodes.erase(name)
	for i in agents.size():
		var a: Dictionary = agents[i]
		var name := String(a.get("agent", "?"))
		var recent: Array = a.get("recent", [])
		var top: Dictionary = recent[0] if not recent.is_empty() else {}
		var activity := "%s #%s · %s" % [String(top.get("repo", "")), str(top.get("number", "")), String(top.get("title", "")).left(54)]
		if not _agent_nodes.has(name):
			var node := Node3D.new()
			_agents_root.add_child(node)
			var g := SphereMesh.new()
			g.radius = 0.36
			g.height = 0.72
			g.radial_segments = 8
			g.rings = 4
			_mesh(g, _holo(_agent_color(name), 1.2), Vector3.ZERO, node)
			var lbl := _label(name, 30, _agent_color(name).lightened(0.3), Vector3(0, -0.62, 0), node)
			var act := _label("", 22, Color(0.75, 0.85, 1.0, 0.85), Vector3(0, -0.98, 0), node)
			act.width = 520
			act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var bubble := _label("", 28, Color(1, 1, 1), Vector3(0, 0.8, 0), node)
			bubble.width = 520
			bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_agent_nodes[name] = {"node": node, "label": lbl, "act": act, "bubble": bubble, "latest": "", "pulse": 0.0}
		var rec: Dictionary = _agent_nodes[name]
		rec["home"] = String(a.get("home", "cloud"))
		(rec["node"] as Node3D).position = _agent_place(i, agents.size(), String(a.get("home", "cloud")))
		(rec["act"] as Label3D).text = activity
		if String(rec["latest"]) != String(top.get("at", "")):
			rec["latest"] = String(top.get("at", ""))
			rec["pulse"] = 1.0   # new activity: the avatar flares


func _agent_color(name: String) -> Color:
	var n := name.to_lower()
	if n.begins_with("claude"):
		return Color(1.0, 0.62, 0.38)
	if n.begins_with("gpt"):
		return Color(0.45, 0.95, 0.75)
	if n.begins_with("muse"):
		return Color(0.85, 0.55, 1.0)
	if n.begins_with("codex"):
		return Color(0.55, 0.75, 1.0)
	return Color(0.8, 0.8, 0.9)


func _speaker_node(who: String) -> Node3D:
	var w := who.to_lower()
	if w.ends_with("mind"):
		return _mind
	if w == _speaker.to_lower() or w == "keath":
		return _you
	# A seat names its rig ("claude (msi seat)"): match the agent that runs there first, then by first word.
	for rig: String in ["i3", "msi"]:
		if w.contains("(" + rig) or w.contains(rig + " seat"):
			for name: String in _agent_nodes:
				var rec: Dictionary = _agent_nodes[name]
				if String(rec.get("home", "")) == rig and name.to_lower().get_slice(" ", 0) == w.get_slice(" ", 0):
					return rec["node"]
	for name: String in _agent_nodes:
		if name.to_lower() == w:
			return (_agent_nodes[name] as Dictionary)["node"]
	for name: String in _agent_nodes:
		var key := name.to_lower().get_slice(" ", 0)
		if (w.begins_with(key) or key.begins_with(w.get_slice(" ", 0))) and String((_agent_nodes[name] as Dictionary).get("home", "")) == "cloud":
			return (_agent_nodes[name] as Dictionary)["node"]
	return null


func _apply_channel() -> void:
	var channel: Array = feed.get("channel", [])
	var b := PackedStringArray()
	b.append("[color=#7d8aa8]COCKPIT CHANNEL · shared with every agent · select text to copy · C copies the whole brief[/color]")
	var delivered_texts := {}
	for m: Variant in channel.slice(-14):
		var d: Dictionary = m
		var who := String(d.get("from", "?"))
		var mine := who.to_lower() == _speaker.to_lower()
		var col := "ffd27a" if mine else ("9fd8ff" if who.ends_with("mind") else "ffb07a")
		var model: Variant = d.get("model")
		var status := ""
		if mine:
			delivered_texts[String(d.get("text", ""))] = true
			var rb: Array = d.get("read_by", [])
			# Delivery you can see: delivered (it's in the shared channel), then read by whichever seats have read it.
			status = "  [color=#46d38a]✓ delivered[/color]" + ("  [color=#9fd8ff]✓ read by %s[/color]" % _esc(", ".join(PackedStringArray(rb))) if not rb.is_empty() else "  [color=#7d8aa8]· not read yet[/color]")
		b.append("[color=#%s]%s[/color]%s [color=#7d8aa8]→ %s[/color]%s\n%s" % [col, _esc(who), ("" if model == null else " [color=#7d8aa8](" + _esc(model) + ")[/color]"),
			_esc(d.get("to", "all")), status, _esc(d.get("text", ""))])
	# What you typed that hasn't reached the shared channel yet.
	for s: Dictionary in _sent_local:
		if not delivered_texts.has(String(s.get("text", ""))):
			b.append("[color=#ffd27a]%s[/color] [color=#7d8aa8]→ %s[/color]  [color=#f5b041]… sent, waiting for the channel (≤10 s)[/color]\n%s" % [
				_esc(_speaker), _esc(s.get("to", "")), _esc(s.get("text", ""))])
	_chat.text = "\n".join(b)
	# Speech in space: each speaker's latest words appear by their avatar.
	var latest := {}
	for m: Variant in channel.slice(-10):
		latest[String((m as Dictionary).get("from", ""))] = String((m as Dictionary).get("text", ""))
	for who: String in latest:
		var node := _speaker_node(who)
		var text := String(latest[who]).left(140)
		if node == _you:
			_you_bubble.text = text
		elif node == _mind:
			_card_label.text = "%s\n%s" % [who, text]
			_card.scale = Vector3.ONE * 0.4 if channel.size() != _seen_channel else _card.scale
		elif node != null:
			for name: String in _agent_nodes:
				if (_agent_nodes[name] as Dictionary)["node"] == node:
					((_agent_nodes[name] as Dictionary)["bubble"] as Label3D).text = text
	_seen_channel = channel.size()


func _esc(s: Variant) -> String:
	return String(s).replace("[", "[lb]")


func _send(text: String) -> void:
	var t := text.strip_edges()
	if t == "" or shot_path != "":
		return
	var to := "mind"
	if t.begins_with("@"):
		to = t.get_slice(" ", 0).trim_prefix("@")
		t = t.substr(t.find(" ") + 1).strip_edges() if t.find(" ") > 0 else ""
		if t == "":
			return
	var line := {"at": Time.get_datetime_string_from_system(true) + "Z", "from": _speaker, "to": to, "text": t}
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(OUTBOX) else FileAccess.WRITE
	var f := FileAccess.open(OUTBOX, mode)
	if f == null:
		_subtitle.text = "(could not write the outbox: is the feeder folder there?)"
		return
	f.seek_end()
	f.store_line(JSON.stringify(line))
	f.close()
	_sent_local.append(line)
	_you_bubble.text = t
	_subtitle.text = "you → %s: “%s”  · sent; it shows ✓ delivered when it reaches the shared channel" % [to, t]
	_apply_channel()


## Everything the cockpit shows, as one text you can paste anywhere: fleet, agents, work queue, conversation, next steps.
func _brief_text() -> String:
	var L := PackedStringArray()
	L.append("COLONY COCKPIT BRIEF (HOLOMIND, i3) · feed %s · i3 screen: %s" % [String(feed.get("at", "?")), String(feed.get("screen", ""))])
	L.append("")
	L.append("FLEET")
	var bodies: Dictionary = feed.get("bodies", {})
	for id: String in bodies:
		var b: Dictionary = bodies[id]
		var failing: Array = b.get("failing", [])
		L.append("- %s (%s): %s%s. %s" % [String(b.get("label", id)), String(b.get("role", "")), String(b.get("status", "?")),
			(" (failing: " + ", ".join(PackedStringArray(failing)) + ")") if not failing.is_empty() else "", String(b.get("detail", ""))])
	L.append("")
	L.append("AGENTS AT WORK")
	for a: Variant in feed.get("agents", []):
		var g: Dictionary = a
		var r: Array = g.get("recent", [])
		if not r.is_empty():
			var top: Dictionary = r[0]
			L.append("- %s: %s #%s %s" % [String(g.get("agent", "")), String(top.get("repo", "")), str(top.get("number", "")), String(top.get("title", ""))])
	L.append("")
	var acts: Array = feed.get("actions", [])
	L.append("WORK WAITING (%d)" % acts.size())
	for x: Variant in acts:
		var d: Dictionary = x
		L.append("- [%s] %s: %s%s" % [String(d.get("kind", "")), String(d.get("where", "")), String(d.get("title", "")), ("  " + String(d.get("url"))) if d.has("url") else ""])
	L.append("")
	L.append("RECENT THOUGHTS")
	var events: Array = feed.get("events", [])
	for e: Variant in events.slice(-5):
		L.append("- %s: %s" % [String((e as Dictionary).get("mind", "?")), String((e as Dictionary).get("line", ""))])
	L.append("")
	L.append("CONVERSATION (latest)")
	var channel: Array = feed.get("channel", [])
	for m: Variant in channel.slice(-10):
		var d: Dictionary = m
		var rb: Array = d.get("read_by", [])
		L.append("- %s → %s: %s%s" % [String(d.get("from", "?")), String(d.get("to", "all")), String(d.get("text", "")), ("  [read by " + ", ".join(PackedStringArray(rb)) + "]") if not rb.is_empty() else ""])
	L.append("")
	L.append("SUGGESTED NEXT STEPS")
	var n := 0
	for x: Variant in acts:
		var d: Dictionary = x
		var k := String(d.get("kind", ""))
		var step := ""
		match k:
			"rig": step = "Bring %s back to green: %s" % [String(d.get("where", "")), String(d.get("title", ""))]
			"review": step = "Second-review %s" % String(d.get("title", "")).get_slice(" awaits", 0)
			"decision": step = "Keath to decide: %s" % String(d.get("title", ""))
			"reply": step = "Answer: %s" % String(d.get("title", ""))
		if step != "":
			n += 1
			L.append("%d. %s" % [n, step])
		if n >= 8:
			break
	return "\n".join(L)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var backing := ColorRect.new()   # a dark glass behind the channel so it reads over the hologram
	backing.color = Color(0.02, 0.03, 0.07, 0.72)
	backing.name = "chat_backing"
	layer.add_child(backing)
	_chat = RichTextLabel.new()
	_chat.bbcode_enabled = true
	_chat.scroll_following = true
	_chat.selection_enabled = true        # select with the mouse, Ctrl+C to copy
	_chat.context_menu_enabled = true     # right-click: Copy / Select All
	_chat.mouse_filter = Control.MOUSE_FILTER_STOP
	_chat.add_theme_font_size_override("normal_font_size", 15)
	_chat.add_theme_color_override("default_color", Color(0.85, 0.9, 1.0))
	layer.add_child(_chat)
	_typebox = LineEdit.new()
	_typebox.placeholder_text = "Type to the colony… (@mind is the default; @claude, @msi, @muse…) · Enter to send · assign work from the Workbench on the left"
	_typebox.add_theme_font_size_override("font_size", 17)
	_typebox.text_submitted.connect(func(t: String) -> void:
		_send(t)
		_typebox.clear())
	layer.add_child(_typebox)
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
	feed_note = ("[%s] " % String(feed.get("source"))) + "frozen " + String(feed.get("at", "?")) if feed.has("source") else "feed " + String(feed.get("at", "?"))
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
	_rebuild_agents()
	_rebuild_actions()
	_apply_activity()
	_rebuild_districts()
	_detect_flights()
	_apply_text_visibility()
	_rebuild_bench()
	_apply_channel()
	_count_waiting()
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
	# Budget: 30 fps while someone is looking at it, 10 fps in the background, ~2 fps minimized (nothing to draw).
	var minimized := get_window().mode == Window.MODE_MINIMIZED
	Engine.max_fps = 2 if minimized else (30 if ((get_window().has_focus() and not background) or shot_path != "") else 10)
	_poll -= delta
	if minimized:
		if _poll <= 0.0:
			_poll = 10.0
			_read_feed()
		return
	if _poll <= 0.0 and shot_path == "":
		_poll = 3.0
		_read_feed()
	# The camera moves only when you drag it (no idle drift: motion on screen must mean something).
	if _focus_point.distance_to(_focus_want) > 0.003:
		_focus_point = _focus_point.lerp(_focus_want, clampf(delta * 1.4, 0.0, 1.0))
		_settle = maxf(_settle, 0.5)
		_cam.position = Vector3.INF   # force the orbit placement below
	var cam_want := Vector3(cos(_yaw) * cos(_pitch), sin(_pitch), sin(_yaw) * cos(_pitch)) * _dist + _focus_point - Vector3(0, 0.2, 0)
	if _cine:
		# Follow the newest real event in flight; with nothing happening, settle back to the wide view and hold.
		var look := Vector3(0, 1.8, 0)
		if _cine_target != null and is_instance_valid(_cine_target):
			look = _cine_target.global_position
			var side := Vector3(look.x, 0, look.z).normalized() if Vector3(look.x, 0, look.z).length() > 0.1 else Vector3(0, 0, 1)
			cam_want = look + side * 4.2 + Vector3(0, 2.4, 0)
		else:
			_cine_target = null
		var k := clampf(delta * 0.7, 0.0, 1.0)
		if not _cam.position.is_equal_approx(cam_want):
			_cam.position = _cam.position.lerp(cam_want, k)
			_cine_look = _cine_look.lerp(look, k)
			_cam.look_at(_cine_look, Vector3.UP)
			_settle = maxf(_settle, 0.5)
	elif not _cam.position.is_equal_approx(cam_want):
		_cam.position = cam_want
		_settle = maxf(_settle, 0.5)
		_cam.look_at(_focus_point, Vector3.UP)
	# Real events in flight (a new heartbeat, an order, a receipt). Nothing else travels.
	_update_flights(delta)
	# The Mind moves only when its attention changes; its rings turn only while it is actually thinking.
	if _mind.position.distance_to(_mind_target) > 0.002:
		_mind.position = _mind.position.lerp(_mind_target, clampf(delta * 1.6, 0.0, 1.0))
	if int(feed.get("mind_thinking", 0)) > 0:
		for c in _mind.get_children():
			if String(c.name).begins_with("ring"):
				(c as Node3D).rotate_object_local(Vector3(1, 0, 0) if String(c.name) == "ring100" else Vector3(0, 0, 1), delta * 0.9)
	_settle -= delta
	if _settle <= 0.0 and _flights.is_empty():
		# Nothing changed: touch nothing, so the engine (low_processor_usage_mode) has nothing to redraw.
		_hud_clock -= delta
		if _hud_clock <= 0.0:
			_hud_clock = 1.0
			_update_hud()
		if shot_path != "" and _t > 4.0:
			_shoot()
		return
	_card.position = _mind.position + Vector3(0, 1.6, 0)
	if _cam.position.distance_to(_card.position) > 0.01:
		_card.look_at(_cam.position, Vector3.UP)
		_card.rotate_object_local(Vector3.UP, PI)
	_card.scale = _card.scale.lerp(Vector3.ONE, clampf(delta * 2.2, 0.0, 1.0))
	# The terminal rises beside the Mind's attention, facing you, and folds away when attention moves.
	if _term_focus != "":
		_term_shown = minf(1.0, _term_shown + delta * 0.8)
		var host: Vector3 = BODY_PLACES.get(_term_focus, Vector3.ZERO)
		# Agents stand outside their rig, so the console rises on the inner side, toward the table's centre.
		var inward := -Vector3(host.x, 0, host.z).normalized() if host.length() > 0.1 else Vector3(0, 0, 1)
		_term.position = host + inward * 1.9 + Vector3(0, 1.6 + 1.0 * _term_shown, 0)
		if _cam.position.distance_to(_term.position) > 0.01:
			_term.look_at(_cam.position, Vector3.UP)   # squarely facing the viewer
			_term.rotate_object_local(Vector3.UP, PI)
		_term.scale = Vector3(1.0, maxf(0.01, _term_shown), 1.0)
	# Layer focus: the chosen layer bright, others dim.
	for i in _layer_roots.size():
		_layer_roots[i].visible = focus_layer < 0 or focus_layer == i or i == 0
	# You stand at the front edge, nearest the camera; agents breathe and flare on new activity.
	var front := Vector3(_cam.position.x, 0, _cam.position.z).normalized() * 6.8
	_you.position = front + Vector3(0, 0.9, 0)
	for s in _actions_root.get_children():
		if String(s.get_meta("where", "")) in ["keath", _speaker.to_lower()]:
			# Your decisions float over the table's near edge, not in front of the camera.
			(s as Node3D).position = front * 0.55 + Vector3(0, 3.0, 0)
	for name: String in _agent_nodes:
		var rec: Dictionary = _agent_nodes[name]
		rec["pulse"] = maxf(0.0, float(rec["pulse"]) - delta * 0.25)
		var node: Node3D = rec["node"]
		node.scale = Vector3.ONE * (1.0 + 0.5 * float(rec["pulse"]))   # flares only on real new activity
	_hud_clock -= delta
	if _hud_clock <= 0.0:   # the header changes at most once a second
		_hud_clock = 1.0
		_update_hud()
	if shot_path != "" and _t > 4.0:
		_shoot()


var _waiting_text: String = "none"
var _colony_text: String = ""


func _count_waiting() -> void:
	var counts := {}
	for a: Variant in feed.get("actions", []):
		var k := String((a as Dictionary).get("kind", ""))
		counts[k] = int(counts.get(k, 0)) + 1
	var waiting := PackedStringArray()
	for k: String in counts:
		waiting.append("%d %s" % [int(counts[k]), k])
	_waiting_text = ", ".join(waiting) if not waiting.is_empty() else "none"
	# Measured colony facts (from the MSI's CHORUS): backup, mirror, spine.
	var c: Dictionary = feed.get("colony", {}) if feed.get("colony") is Dictionary else {}
	_colony_text = ""
	if not c.is_empty():
		var b: Dictionary = c.get("backup", {}) if c.get("backup") is Dictionary else {}
		var m: Dictionary = c.get("mirror", {}) if c.get("mirror") is Dictionary else {}
		var sp: Dictionary = c.get("spine", {}) if c.get("spine") is Dictionary else {}
		var down: Array = sp.get("down", [])
		_colony_text = "
backup %s h old%s · mirror %s h, %s failures · MSI spine %s/%s up%s" % [str(b.get("age_h", "?")), " (running)" if bool(b.get("in_progress", false)) else "",
			str(m.get("age_h", "?")), str(m.get("failures", "?")), str(sp.get("up", "?")), str(sp.get("total", "?")),
			(" (down: " + ", ".join(PackedStringArray(down)) + ")") if not down.is_empty() else ""]
	# Self-awareness: name any stale or failing source in the header.
	var srcs: Dictionary = feed.get("sources", {}) if feed.get("sources") is Dictionary else {}
	var bad := PackedStringArray()
	for k: String in srcs:
		var v: Dictionary = srcs[k]
		if not bool(v.get("ok", true)):
			bad.append(k)
	if not srcs.is_empty():
		_colony_text += ("  ·  sources: all fresh" if bad.is_empty() else "  ·  STALE/FAILING: " + ", ".join(bad))
	# The development pipeline in one line.
	var pipe: Array = feed.get("pipeline", [])
	if not pipe.is_empty():
		var st := {}
		for x: Variant in pipe:
			var k2 := String((x as Dictionary).get("stage", ""))
			st[k2] = int(st.get(k2, 0)) + 1
		_colony_text += "\nPRs %d open · %d draft · %d need review · %d changes requested · %d approved, ready to merge" % [pipe.size(),
			int(st.get("draft", 0)), int(st.get("needs-review", 0)) + int(st.get("stale-review", 0)), int(st.get("changes", 0)), int(st.get("approved", 0))]
	var thinking := int(feed.get("mind_thinking", 0))
	if thinking > 0:
		_waiting_text += " · the Mind is thinking (%d message%s queued)" % [thinking, "" if thinking == 1 else "s"]


func _update_hud() -> void:
	_hud.text = "HOLOMIND · the colony workstation (i3 Claude) · acts through orders you assign · %s · WORK WAITING: %s\n%s · motion = real events only (heartbeat → xanadu · order → seat · receipt → you) · drag: orbit · wheel: zoom · 1/2/3: layer · 0: all · C: copy brief · click: inspect · Backspace: whole colony · L: legend · H: visuals only · V: cinematic · F11: fullscreen · Esc: quit" % [
		feed_note, _waiting_text, ("layer " + LAYER_NAMES[focus_layer]) if focus_layer >= 0 else "all layers"] + _colony_text


func _layout_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	_subtitle.position = Vector2(vp.x * 0.04, vp.y - 120)
	_subtitle.size = Vector2(vp.x * 0.66, 60)
	_chat.position = Vector2(vp.x * 0.72, 80)
	_chat.size = Vector2(vp.x * 0.27, vp.y - 170)
	var backing := _chat.get_parent().get_node("chat_backing") as ColorRect
	backing.position = _chat.position - Vector2(10, 8)
	backing.size = _chat.size + Vector2(20, 16)
	_typebox.position = Vector2(vp.x * 0.04, vp.y - 54)
	_typebox.size = Vector2(vp.x * 0.92, 38)
	if _inspector != null:
		_inspector.position = Vector2(vp.x * 0.3, 150)
		_inspector.size = Vector2(vp.x * 0.4, 0)
		_legend.position = Vector2(vp.x * 0.29, 150)
		_legend.size = Vector2(vp.x * 0.42, vp.y * 0.6)
	if _bench_scroll != null:
		_bench_scroll.position = Vector2(vp.x * 0.01, 150)
		_bench_scroll.size = Vector2(vp.x * 0.27, vp.y - 290)
		_bench_backing.position = _bench_scroll.position - Vector2(8, 8)
		_bench_backing.size = _bench_scroll.size + Vector2(16, 16)


func _set_layer(l: int) -> void:
	focus_layer = l
	for c in _stars.get_children():
		if c is Label3D and c.has_meta("detail"):
			(c as Label3D).text = String(c.get_meta("detail")) if focus_layer == 1 else "vitals"
	_update_hud()


## THE WORKBENCH: the cockpit as a workstation. Every work item can be assigned to a seat, opened, asked about,
## or (for your decisions) approved or declined. Orders use CHORUS's shape in the shared channel, so both
## cockpits and every agent (cockpit.py orders/take/status) work one queue; receipts land back here.
func _build_bench() -> void:
	var layer := _chat.get_parent()
	_bench_backing = ColorRect.new()
	_bench_backing.color = Color(0.02, 0.03, 0.07, 0.78)
	layer.add_child(_bench_backing)
	_bench_scroll = ScrollContainer.new()
	_bench_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layer.add_child(_bench_scroll)
	_bench = VBoxContainer.new()
	_bench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench.add_theme_constant_override("separation", 6)
	_bench_scroll.add_child(_bench)


func _bench_label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(80, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


func _bench_button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b


func _rebuild_bench() -> void:
	if _bench == null:
		return
	for c in _bench.get_children():
		c.queue_free()
	var orders: Array = feed.get("orders", [])
	var open_count := 0
	for o: Variant in orders:
		if not (String((o as Dictionary).get("status", "")) in ["done", "declined"]):
			open_count += 1
	_bench.add_child(_bench_label("WORKBENCH · assign work, approve decisions, watch receipts land · Ctrl+K: do anything", 14, Color(0.49, 0.54, 0.66)))
	if _now_text != "":
		_bench.add_child(_bench_label(_now_text, 13, Color(0.55, 1.0, 0.75)))
	if not orders.is_empty():
		_bench.add_child(_bench_label("ORDERS · %d open" % open_count, 15, Color(1.0, 0.82, 0.48)))
		for o: Variant in orders.slice(-8):
			var d: Dictionary = o
			var st := String(d.get("status", "posted"))
			var col := Color(0.62, 0.85, 1.0)
			if st == "done":
				col = Color(0.27, 0.83, 0.54)
			elif st in ["taken", "working"]:
				col = Color(0.96, 0.69, 0.25)
			elif st == "declined":
				col = Color(0.6, 0.6, 0.66)
			var by := String(d.get("by")) if d.get("by") != null else ""
			var row := VBoxContainer.new()
			row.add_child(_bench_label("%s → %s · %s%s" % [st.to_upper(), String(d.get("to", "any")), String(d.get("text", "")).left(140),
				("  · " + by) if by != "" else ""], 13, col))
			if String(d.get("note", "")) != "":
				row.add_child(_bench_label("“" + String(d.get("note")) + "”", 12, Color(0.8, 0.86, 1.0)))
			var link := String(d.get("link", ""))
			if link != "":
				row.add_child(_bench_button("Open receipt", link, func() -> void: OS.shell_open(link)))
			_bench.add_child(row)
	var acts: Array = feed.get("actions", [])
	_bench.add_child(_bench_label("WORK WAITING · %d" % acts.size(), 15, Color(1.0, 0.82, 0.48)))
	for x: Variant in acts.slice(0, 24):
		var a: Dictionary = x
		var kind := String(a.get("kind", ""))
		var box := VBoxContainer.new()
		var ordered := String(a.get("ordered", ""))
		var kc: Color = KIND_COLOURS.get(kind, Color(0.8, 0.85, 1.0))
		box.add_child(_bench_label("[%s] %s%s" % [kind.to_upper(), String(a.get("title", "")).left(150), ("  · ordered: " + ordered) if ordered != "" else ""], 13, kc.lightened(0.25)))
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 4)
		if kind == "merge":
			bar.add_child(_bench_button("Merge", "You approve; a seat runs gsv merge (re-checks CI, provenance, a different-actor review) and posts the receipt", func() -> void: _order(a, "claude (i3 seat)", "MERGE, Keath approved: ")))
		if kind == "decision" and String(a.get("where", "")) in ["keath", _speaker.to_lower()]:
			bar.add_child(_bench_button("Approve", "Your decision goes to the shared channel for the Steward and the seats", func() -> void: _decide(a, "approve")))
			bar.add_child(_bench_button("Decline", "Decline this request", func() -> void: _decide(a, "decline")))
		var pick := OptionButton.new()
		pick.focus_mode = Control.FOCUS_NONE
		pick.add_theme_font_size_override("font_size", 13)
		for seat: String in SEATS:
			pick.add_item(seat)
		pick.tooltip_text = "Which seat should do it"
		bar.add_child(pick)
		bar.add_child(_bench_button("Assign", "Post a work order to that seat", func() -> void: _order(a, pick.get_item_text(pick.selected))))
		var url := String(a.get("url", ""))
		if url != "":
			bar.add_child(_bench_button("Open", url, func() -> void: OS.shell_open(url)))
		bar.add_child(_bench_button("Ask", "Ask the Mind about this", func() -> void: _send("About “%s”: what matters here, and who should take it?" % String(a.get("title", "")))))
		box.add_child(bar)
		_bench.add_child(box)


func _emit(line: Dictionary) -> bool:
	if shot_path != "":
		return false
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(OUTBOX) else FileAccess.WRITE
	var f := FileAccess.open(OUTBOX, mode)
	if f == null:
		_subtitle.text = "(could not write the outbox: is the feeder folder there?)"
		return false
	f.seek_end()
	f.store_line(JSON.stringify(line))
	f.close()
	return true


func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _order(a: Dictionary, seat: String, prefix: String = "") -> void:
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "").replace("T", "-")
	var text := prefix + String(a.get("title", ""))
	if String(a.get("url", "")) != "":
		text += "  " + String(a.get("url"))
	var line := {"at": _now_iso(), "from": _speaker, "kind": "order", "id": "o-" + stamp.right(11) + "-h", "to": seat,
		"station": String(STATION_FOR.get(String(a.get("kind", "")), "anvil")), "text": text, "ref": String(a.get("id", "")),
		"url": String(a.get("url", "")), "via": "holomind"}
	if _emit(line):
		_subtitle.text = "Order posted to %s: “%s” · it shows TAKEN, then DONE with a receipt, as the seat works it" % [seat, String(a.get("title", "")).left(80)]
		_flash_bench("ORDER → " + seat)


func _decide(a: Dictionary, verdict: String) -> void:
	var line := {"at": _now_iso(), "from": _speaker, "kind": "decision", "card": String(a.get("title", "")), "verdict": verdict, "via": "holomind"}
	if _emit(line):
		_subtitle.text = "You chose %s: “%s” · recorded in the shared channel for the Steward and the seats" % [verdict, String(a.get("title", "")).left(90)]
		_flash_bench(verdict.to_upper())


func _flash_bench(text: String) -> void:
	# A visible reaction in the room: the Mind's card flares with what you just did.
	_card_label.text = text
	_card_label.modulate = Color(1.0, 0.85, 0.5)
	_card.scale = Vector3.ONE * 0.01


## LIVE WORK: agent seats stream what they're doing (hooks/seat_activity.py: tool + short label, never content).
## The seat's avatar shows it and flares on each new step, and the Workbench says who is working on what, right now.
func _apply_activity() -> void:
	var acts: Array = feed.get("activity", [])
	if acts.is_empty():
		_now_text = ""
		return
	var last: Dictionary = acts[-1]
	var who := String(last.get("mind", "?"))
	var age := _age_seconds(String(last.get("at", "")))
	_now_text = "NOW · %s: %s (%s)%s" % [who, String(last.get("label", "")), String(last.get("tool", "")),
		("  · %d s ago" % age) if age >= 0 else ""]
	var node := _speaker_node(who)
	if node != null:
		for name: String in _agent_nodes:
			var rec: Dictionary = _agent_nodes[name]
			if rec["node"] == node:
				(rec["act"] as Label3D).text = "▶ " + String(last.get("label", "")).left(60)
				if String(last.get("at", "")) != _activity_seen:
					rec["pulse"] = 1.0
	_activity_seen = String(last.get("at", ""))


func _age_seconds(stamp: String) -> int:
	if stamp == "":
		return -1
	var t := Time.get_unix_time_from_datetime_string(stamp.trim_suffix("Z"))
	return int(Time.get_unix_time_from_system() - t)


## COMMAND PALETTE (Ctrl+K): everything the cockpit can do, as typed commands with fuzzy match.
func _build_palette() -> void:
	var layer := _chat.get_parent()
	_palette = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.1, 0.96)
	sb.border_color = Color(0.4, 0.7, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_palette.add_theme_stylebox_override("panel", sb)
	_palette.visible = false
	layer.add_child(_palette)
	var v := VBoxContainer.new()
	_palette.add_child(v)
	_palette_input = LineEdit.new()
	_palette_input.placeholder_text = "Do anything… (assign, open, ask, approve, layer, copy brief, PRs)  ↑↓ Enter · Esc closes"
	_palette_input.add_theme_font_size_override("font_size", 18)
	v.add_child(_palette_input)
	_palette_list = ItemList.new()
	_palette_list.custom_minimum_size = Vector2(0, 360)
	_palette_list.add_theme_font_size_override("font_size", 15)
	v.add_child(_palette_list)
	_palette_input.text_changed.connect(func(_t: String) -> void: _filter_palette())
	_palette_input.text_submitted.connect(func(_t: String) -> void: _run_palette(maxi(0, _palette_list.get_selected_items()[0] if _palette_list.get_selected_items().size() > 0 else 0)))
	_palette_input.gui_input.connect(_palette_keys)
	_palette_list.item_activated.connect(_run_palette)


func _palette_keys(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and _palette_list.item_count > 0:
		var k := (ev as InputEventKey).keycode
		var sel := _palette_list.get_selected_items()[0] if _palette_list.get_selected_items().size() > 0 else 0
		if k == KEY_DOWN or k == KEY_UP:
			sel = clampi(sel + (1 if k == KEY_DOWN else -1), 0, _palette_list.item_count - 1)
			_palette_list.select(sel)
			_palette_list.ensure_current_is_visible()
			_palette_input.accept_event()


func _open_palette() -> void:
	_palette_cmds = _palette_commands()
	var vp := get_viewport().get_visible_rect().size
	_palette.position = Vector2(vp.x * 0.22, vp.y * 0.12)
	_palette.size = Vector2(vp.x * 0.56, 0)
	_palette.visible = true
	_palette_input.text = ""
	_filter_palette()
	_palette_input.grab_focus()


func _palette_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for x: Variant in feed.get("actions", []):
		var a: Dictionary = x
		var title := String(a.get("title", ""))
		var kind := String(a.get("kind", ""))
		if kind == "merge":
			out.append({"label": "Merge · " + title, "do": "merge", "item": a})
		if kind == "decision":
			out.append({"label": "Approve · " + title, "do": "approve", "item": a})
			out.append({"label": "Decline · " + title, "do": "decline", "item": a})
		for seat: String in SEATS:
			out.append({"label": "Assign → %s · %s" % [seat, title], "do": "assign", "seat": seat, "item": a})
		if String(a.get("url", "")) != "":
			out.append({"label": "Open · " + title, "do": "open", "url": String(a.get("url"))})
		out.append({"label": "Ask the Mind · " + title, "do": "ask", "item": a})
	for x: Variant in feed.get("orders", []):
		var o: Dictionary = x
		if String(o.get("link", "")) != "":
			out.append({"label": "Open receipt · %s (%s)" % [String(o.get("text", "")).left(80), String(o.get("status", ""))], "do": "open", "url": String(o.get("link"))})
	for x: Variant in feed.get("agents", []):
		var g: Dictionary = x
		for r: Variant in g.get("recent", []):
			var d: Dictionary = r
			if String(d.get("url", "")) != "":
				out.append({"label": "Open %s's PR · %s #%s %s" % [String(g.get("agent", "")), String(d.get("repo", "")), str(d.get("number", "")), String(d.get("title", ""))], "do": "open", "url": String(d.get("url"))})
	for i in LAYER_NAMES.size():
		out.append({"label": "Show layer %d · %s" % [i, LAYER_NAMES[i]], "do": "layer", "n": i})
	out.append({"label": "Show all layers", "do": "layer", "n": -1})
	out.append({"label": "Copy the whole brief to the clipboard", "do": "copy"})
	out.append({"label": "Toggle fullscreen", "do": "full"})
	return out


func _fuzzy(hay: String, needle: String) -> int:
	# Every word of the needle must appear; score favours earlier and tighter matches.
	if needle == "":
		return 1
	var h := hay.to_lower()
	var score := 1000
	for w: String in needle.to_lower().split(" ", false):
		var at := h.find(w)
		if at < 0:
			return 0
		score -= at
	return maxi(1, score)


func _filter_palette() -> void:
	_palette_list.clear()
	var q := _palette_input.text.strip_edges()
	var scored: Array = []
	for c: Dictionary in _palette_cmds:
		var sc := _fuzzy(String(c["label"]), q)
		if sc > 0:
			scored.append([sc, c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	_palette_shown.clear()
	for e: Array in scored.slice(0, 60):
		var c: Dictionary = e[1]
		_palette_shown.append(c)
		_palette_list.add_item(String(c["label"]).left(150))
	if _palette_list.item_count > 0:
		_palette_list.select(0)


func _run_palette(i: int) -> void:
	if i < 0 or i >= _palette_shown.size():
		return
	var c: Dictionary = _palette_shown[i]
	_palette.visible = false
	match String(c["do"]):
		"assign": _order(c["item"] as Dictionary, String(c["seat"]))
		"merge": _order(c["item"] as Dictionary, "claude (i3 seat)", "MERGE, Keath approved: ")
		"approve": _decide(c["item"] as Dictionary, "approve")
		"decline": _decide(c["item"] as Dictionary, "decline")
		"open": OS.shell_open(String(c["url"]))
		"ask": _send("About “%s”: what matters here, and who should take it?" % String((c["item"] as Dictionary).get("title", "")))
		"layer": _set_layer(int(c["n"]))
		"copy":
			DisplayServer.clipboard_set(_brief_text())
			_subtitle.text = "Copied the whole cockpit brief to the clipboard."
		"full":
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


## EVENT FLIGHTS: something travels across the table only when the feed shows it actually happened.
## - heartbeat: a rig's heartbeat age dropped since the last feed, so a NEW heartbeat landed on xanadu
## - order: a work order appeared in the shared channel, so it flies from whoever posted it to the seat
## - receipt: an order's status changed (taken/working/done/declined), so it flies from the seat back to you
## The first feed only records state, so old news never animates.
func _detect_flights() -> void:
	_settle = 3.0
	var ship: Node3D = _layer_roots[0]
	var bodies: Dictionary = feed.get("bodies", {})
	for id: String in bodies:
		var b: Dictionary = bodies[id]
		if id == "xanadu" or b.get("age_s") == null:
			continue
		var age := int(b.get("age_s"))
		if _flights_primed and _hb_age.has(id) and age < int(_hb_age[id]) and String(b.get("status", "")) != "silent":
			var col: Color = C_ALARM if String(b.get("status", "")) == "red" else C_CALM
			_fly(ship.to_global(BODY_PLACES[id] as Vector3), ship.to_global(BODY_PLACES["xanadu"] as Vector3), col,
				"heartbeat · %s · %s" % [id, String(b.get("status", ""))])
		_hb_age[id] = age
	for x: Variant in feed.get("orders", []):
		var o: Dictionary = x
		var oid := String(o.get("id", ""))
		var st := String(o.get("status", "posted"))
		var seat_node := _speaker_node(String(o.get("by")) if o.get("by") != null and String(o.get("by")) != "" else String(o.get("to", "")))
		var seat_pos: Vector3 = seat_node.global_position if seat_node != null else Vector3(0, 1.4, 0)
		if _flights_primed and not _order_state.has(oid):
			_fly(_you.global_position, seat_pos, Color(1.0, 0.82, 0.48), "order → %s" % String(o.get("to", "")))
		elif _flights_primed and String(_order_state.get(oid, "")) != st:
			_fly(seat_pos, _you.global_position, Color(0.27, 0.83, 0.54) if st == "done" else Color(0.96, 0.69, 0.25), "%s · %s" % [st, String(o.get("text", "")).left(40)])
		_order_state[oid] = st
	_flights_primed = true


func _fly(from: Vector3, to: Vector3, col: Color, text: String) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	_mesh(s, _holo(col, 2.2), Vector3.ZERO, holder)
	_label(text, 30, col.lightened(0.3), Vector3(0, 0.35, 0), holder)
	holder.global_position = from
	_flights.append({"node": holder, "from": from, "to": to, "t": 0.0})
	_cine_target = holder   # the cinematic camera (V) follows the newest real event
	_apply_text_visibility()


func _update_flights(delta: float) -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var f: Dictionary = _flights[i]
		f["t"] = float(f["t"]) + delta / FLIGHT_SECONDS
		var n: Node3D = f["node"]
		var u := smoothstep(0.0, 1.0, clampf(float(f["t"]), 0.0, 1.0))   # ease in and out: slow, followable
		var arc := Vector3(0, 1.6 * sin(u * PI), 0)   # a visible arc so you can follow it, nothing more
		n.global_position = (f["from"] as Vector3).lerp(f["to"] as Vector3, u) + arc
		if float(f["t"]) >= 1.0:
			n.queue_free()
			_flights.remove_at(i)


## DISTRICTS: the colony laid out as what is actually there, rebuilt from each feed. Nothing here is decorative.
## - Around each rig, one pylon per heartbeat check: green = passing, red = failing (height = how long it took).
## - Around the MSI, one tower per spine service from CHORUS: cyan = up, red = down; core services stand taller.
## - Around xanadu, one slab per open Steward decision card (the library's unanswered questions).
## - The Forge: one building per repository. Its floors are its open PRs, stacked and coloured by pipeline stage
##   (grey draft, blue needs review, violet stale review, orange changes requested, green approved); a red cap
##   glows as bright as the share of its PRs failing CI.
func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.55)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	m.metallic = 0.6
	return m


func _box(size: Vector3, mat: Material, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, mat, at, parent)


func _rebuild_districts() -> void:
	var ship: Node3D = _layer_roots[0]
	if _districts != null:
		_districts.queue_free()
	_districts = Node3D.new()
	ship.add_child(_districts)
	_picks.clear()
	_repo_pos.clear()
	var bodies: Dictionary = feed.get("bodies", {})
	_register_bodies(bodies)
	# Heartbeat check pylons around each rig.
	for id: String in bodies:
		var b: Dictionary = bodies[id]
		var checks: Array = b.get("checks", []) if b.get("checks") is Array else []
		var at: Vector3 = BODY_PLACES.get(id, Vector3.ZERO)
		for i in checks.size():
			var c: Dictionary = checks[i]
			var ok := bool(c.get("ok", false))
			var ms := float(c.get("ms")) if c.get("ms") != null else 50.0
			var h := 0.2 + clampf(log(maxf(ms, 1.0)) / log(30000.0), 0.0, 1.0) * 0.7
			var ang := TAU * float(i) / float(maxi(checks.size(), 1))
			var p := at + Vector3(cos(ang) * 1.25, h * 0.5 - 0.35, sin(ang) * 1.25)
			var pylon := _box(Vector3(0.09, h, 0.09), _glow(C_CALM if ok else C_ALARM, 1.2 if ok else 3.0), p, _districts)
			_picks.append({"node": pylon, "title": "%s · heartbeat check · %s" % [id, String(c.get("name", "?"))],
				"body": "[b]%s[/b] on %s\nlast result: %s · took %s ms\nThe rig runs this check every heartbeat (~5 min) and reports it to xanadu." % [String(c.get("name", "?")), id, "[color=#46d38a]passing[/color]" if ok else "[color=#ff6b6b]FAILING[/color]", str(c.get("ms", "?"))],
				"ask": "What does the %s check on %s mean, and %s?" % [String(c.get("name", "")), id, "is it healthy" if ok else "how do we fix it"]})
			_label(String(c.get("name", "?")), 20, (C_CALM if ok else C_ALARM).lightened(0.3), p + Vector3(0, h * 0.5 + 0.12, 0), _districts)
	# Spine service towers around the MSI.
	var colony: Dictionary = feed.get("colony", {}) if feed.get("colony") is Dictionary else {}
	var spine: Dictionary = colony.get("spine", {}) if colony.get("spine") is Dictionary else {}
	var services: Array = spine.get("services", []) if spine.get("services") is Array else []
	var msi: Vector3 = BODY_PLACES["msi"]
	var away := Vector3(msi.x, 0, msi.z).normalized()
	if services.is_empty():
		var stub: Node3D = ExtrudedBarScript.new()
		stub.set("has_data", false)   # the kit draws a grey stub with "?": unknown, never "zero services"
		stub.set("footprint", 0.3)
		stub.position = msi + away * 2.15 + Vector3(0, -0.35, 0)
		_districts.add_child(stub)
		_label("spine: unknown (CHORUS unreachable)", 18, Color(0.6, 0.62, 0.7), stub.position + Vector3(0, 0.5, 0), _districts)
	for i in services.size():
		var s: Dictionary = services[i]
		var up := bool(s.get("up", false))
		var tier := String(s.get("tier", ""))
		var h2 := 0.9 if tier == "core" else 0.55
		var ang2 := atan2(away.z, away.x) + (float(i) - float(services.size() - 1) * 0.5) * 0.19
		var p2 := msi + Vector3(cos(ang2) * 2.15, h2 * 0.5 - 0.35, sin(ang2) * 2.15)
		var tower := _box(Vector3(0.14, h2, 0.14), _glow(C_HOLO if up else C_ALARM, 1.0 if up else 3.2), p2, _districts)
		_picks.append({"node": tower, "title": "MSI spine service · " + String(s.get("name", "?")),
			"body": "[b]%s[/b] · tier %s\nstatus: %s · probe %s ms\nMeasured by CHORUS on the MSI every 5 min." % [String(s.get("name", "?")), tier, "[color=#59c3ff]up[/color]" if up else "[color=#ff6b6b]DOWN[/color]", str(s.get("ms", "?"))],
			"ask": "What is %s for in the colony, and %s?" % [String(s.get("name", "")), "is it healthy" if up else "what should we do now that it is down"]})
		_label(String(s.get("name", "?")), 18, (C_HOLO if up else C_ALARM).lightened(0.35), p2 + Vector3(0, h2 * 0.5 + 0.12, 0), _districts)
	# The library's open questions: Steward decision cards as slabs around xanadu.
	var cards := 0
	for x: Variant in feed.get("actions", []):
		if String((x as Dictionary).get("kind", "")) == "decision" and String((x as Dictionary).get("title", "")).begins_with("xanadu card"):
			cards += 1
	for i in cards:
		var ang3 := TAU * float(i) / float(maxi(cards, 1)) + 0.3
		_box(Vector3(0.05, 0.42, 0.28), _glow(C_WATCH, 1.6), Vector3(cos(ang3) * 1.55, -0.12, sin(ang3) * 1.55), _districts)
	# The Forge: repositories as buildings, floors = open PRs by stage, red cap = CI failing share.
	var by_repo := {}
	for x: Variant in feed.get("pipeline", []):
		var pr: Dictionary = x
		var r := String(pr.get("repo", "?"))
		if not by_repo.has(r):
			by_repo[r] = {"stages": {}, "fail": 0, "n": 0}
		var rec: Dictionary = by_repo[r]
		var st := String(pr.get("stage", "draft"))
		(rec["stages"] as Dictionary)[st] = int((rec["stages"] as Dictionary).get(st, 0)) + 1
		rec["n"] = int(rec["n"]) + 1
		if String(pr.get("ci", "")) == "fail":
			rec["fail"] = int(rec["fail"]) + 1
	var repos: Array = by_repo.keys()
	repos.sort()
	var cols := 4
	for i in repos.size():
		var name := String(repos[i])
		var rec2: Dictionary = by_repo[name]
		var base := FORGE_AT + Vector3(float(i % cols) * 0.75 - 1.1, -0.4, float(int(i / cols)) * 0.75 - 0.6)
		_repo_pos[name] = base
		var stages: Dictionary = rec2["stages"]
		var moving := int(stages.get("approved", 0)) + int(stages.get("changes", 0)) + int(stages.get("needs-review", 0)) + int(stages.get("stale-review", 0))
		var fail_share := float(rec2["fail"]) / float(maxi(int(rec2["n"]), 1))
		# Bar height = PRs actually moving (not drafts); colour = the stage that most needs a hand; halo = CI failing share.
		var col: Color = STAGE_COLOURS["needs-review"]
		if int(stages.get("changes", 0)) > 0:
			col = STAGE_COLOURS["changes"]
		elif int(stages.get("approved", 0)) > 0:
			col = STAGE_COLOURS["approved"]
		elif moving == 0:
			col = STAGE_COLOURS["draft"]
		var bar: Node3D = ExtrudedBarScript.new()
		bar.set("value", float(moving))
		bar.set("unit_height", 0.16)
		bar.set("footprint", 0.42)
		bar.set("status_color", col)
		bar.set("urgency", clampf(fail_share, 0.0, 1.0))
		bar.set("alert_hatch", fail_share >= 0.5)
		bar.set("has_data", true)
		bar.set("caption", "")
		bar.position = base + Vector3(0, 0.0, 0)
		_districts.add_child(bar)
		# Stage ring at its foot: every open PR including drafts, one notch per PR.
		var quad := PlaneMesh.new()
		quad.size = Vector2(0.72, 0.72)
		var ring := MeshInstance3D.new()
		ring.mesh = quad
		ring.position = base + Vector3(0, 0.02, 0)
		var rm := ShaderMaterial.new()
		rm.shader = RING_SHADER
		var counts := PackedFloat32Array()
		var ring_cols := PackedVector4Array()
		for st3: String in RING_STAGES:
			counts.append(float(stages.get(st3, 0)))
			var lc: Color = (STAGE_COLOURS[st3] as Color).srgb_to_linear()
			ring_cols.append(Vector4(lc.r, lc.g, lc.b, 1.0))
		rm.set_shader_parameter("stage_count", RING_STAGES.size())
		rm.set_shader_parameter("counts", counts)
		rm.set_shader_parameter("stage_colors", ring_cols)
		rm.set_shader_parameter("has_data", 1.0)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_districts.add_child(ring)
		var y := 0.16 * float(moving)
		_label("%s\n%d moving · %d draft · %d CI fail" % [name, moving, int(stages.get("draft", 0)), int(rec2["fail"])], 18, Color(0.8, 0.88, 1.0), base + Vector3(0, y + 0.3, 0), _districts)
		var anchor := Node3D.new()
		_districts.add_child(anchor)
		anchor.position = base + Vector3(0, y * 0.5, 0)
		_picks.append({"node": anchor, "title": "repository · " + name, "body": _repo_body(name), "url": _repo_url(name),
			"ask": "What is %s for, and what's the highest-yield move on its %d open PRs?" % [name, int(rec2["n"])]})
	_draw_relationships()
	for n in _districts.get_children():
		if n is Label3D:
			var l := n as Label3D
			l.fixed_size = true
			l.pixel_size = 0.0007
			l.visibility_range_end = 9.5
			l.visibility_range_end_margin = 1.5
			l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not repos.is_empty():
		_label("THE FORGE · %d repositories · floors = open PRs by stage" % repos.size(), 26, Color(0.6, 0.8, 1.0), FORGE_AT + Vector3(0, -0.35, 1.3), _districts)


## Visuals only (H): hide every label and panel, so the look can be judged and dialled in on its own.
func _apply_text_visibility() -> void:
	for c in get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = not _text_hidden
	_set_labels_visible(self, not _text_hidden)


func _set_labels_visible(n: Node, v: bool) -> void:
	for c in n.get_children():
		if c is Label3D:
			(c as Label3D).visible = v
		_set_labels_visible(c, v)


## SELECTION: everything you can click, what it is, and what you can do about it.
func _register_bodies(bodies: Dictionary) -> void:
	for id: String in _bodies:
		var b: Dictionary = bodies.get(id, {}) if bodies.get(id) is Dictionary else {}
		var node: MeshInstance3D = (_bodies[id] as Dictionary)["node"]
		# Honest breathing: a rig glows by how fresh its last heartbeat is (bright when just in, fading over minutes).
		var age := float(b.get("age_s")) if b.get("age_s") != null else 9999.0
		var mat: Variant = (_bodies[id] as Dictionary)["mat"]
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("strength", 0.35 + 1.2 * exp(-age / 180.0))
		var checks: Array = b.get("checks", []) if b.get("checks") is Array else []
		var lines := PackedStringArray()
		for c: Variant in checks:
			var d: Dictionary = c
			lines.append("%s %s (%s ms)" % ["[color=#46d38a]✓[/color]" if bool(d.get("ok")) else "[color=#ff6b6b]✗[/color]", String(d.get("name", "?")), str(d.get("ms", "?"))])
		var disks: Dictionary = b.get("disks", {}) if b.get("disks") is Dictionary else {}
		var dl := PackedStringArray()
		for k: String in disks:
			dl.append("%s: %s%% free" % [k, str(disks[k])])
		var work := PackedStringArray()
		for x: Variant in feed.get("actions", []):
			var a: Dictionary = x
			if String(a.get("where", "")).to_lower() == id or String(a.get("title", "")).to_lower().begins_with(id + " "):
				work.append("• " + String(a.get("title", "")).left(90))
		_picks.append({"node": node, "title": "rig · %s · %s" % [id, String(b.get("role", BODY_TITLES.get(id, "")))],
			"body": "[b]%s[/b] is [b]%s[/b] · last heartbeat %s s ago\nRAM free: %s MB · %s\n\n[b]Checks[/b]\n%s\n\n[b]Work about this rig[/b]\n%s" % [
				id.to_upper(), String(b.get("status", "?")), str(b.get("age_s", "?")), str(b.get("ram_mb", "?")), ", ".join(dl),
				"\n".join(lines) if not lines.is_empty() else "(no checks reported)", "\n".join(work) if not work.is_empty() else "(nothing waiting)"],
			"ask": "What is %s doing for the colony right now, and what does it need?" % id})
	for name: String in _agent_nodes:
		var rec: Dictionary = _agent_nodes[name]
		var g: Dictionary = {}
		for x: Variant in feed.get("agents", []):
			if String((x as Dictionary).get("agent", "")) == name:
				g = x
		var prs := PackedStringArray()
		for r: Variant in g.get("recent", []):
			var d2: Dictionary = r
			prs.append("• %s #%s %s%s" % [String(d2.get("repo", "")), str(d2.get("number", "")), String(d2.get("title", "")).left(70), " (draft)" if bool(d2.get("draft", false)) else ""])
		_picks.append({"node": rec["node"], "title": "agent · " + name + " · home " + String(rec.get("home", "?")),
			"body": "[b]%s[/b] works from %s\n\n[b]PRs in the last 24 h[/b]\n%s" % [name, String(rec.get("home", "?")), "\n".join(prs) if not prs.is_empty() else "(none)"],
			"ask": "What is %s working on, and what should it do next?" % name})


func _repo_body(repo: String) -> String:
	var lines := PackedStringArray()
	var counts := {}
	for x: Variant in feed.get("pipeline", []):
		var p: Dictionary = x
		if String(p.get("repo", "")) != repo:
			continue
		var st := String(p.get("stage", ""))
		counts[st] = int(counts.get(st, 0)) + 1
		if st != "draft" and lines.size() < 12:
			lines.append("• #%s [%s, CI %s] %s · %s" % [str(p.get("number", "")), st, String(p.get("ci", "")), String(p.get("title", "")).left(60), String(p.get("agent", ""))])
	var head := PackedStringArray()
	for st2: String in ["approved", "changes", "needs-review", "stale-review", "draft"]:
		if counts.has(st2):
			head.append("%d %s" % [int(counts[st2]), st2])
	var know: Dictionary = feed.get("knowledge", {}) if feed.get("knowledge") is Dictionary else {}
	var k: Dictionary = know.get(repo.to_lower(), {}) if know.get(repo.to_lower()) is Dictionary else {}
	var vault := ("\n[color=#b39bff]Second brain[/color] (%s, %s): %s" % [String(k.get("note", "")), String(k.get("status", "")), String(k.get("role", "")).left(220)]) if not k.is_empty() else "\n[color=#7d8aa8](no note for this repository in the Obsidian vault yet)[/color]"
	return "[b]%s[/b] · %s%s\n\n%s" % [repo, ", ".join(head), vault, "\n".join(lines) if not lines.is_empty() else "(only drafts)"]


func _repo_url(repo: String) -> String:
	for x: Variant in feed.get("pipeline", []):
		var p: Dictionary = x
		if String(p.get("repo", "")) == repo:
			return String(p.get("url", "")).get_slice("/pull/", 0) + "/pulls"
	return ""


## Relationships: a line from each agent to every repository where it has PRs in flight (real cross-references).
func _draw_relationships() -> void:
	var lines := ImmediateMesh.new()
	var any := false
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for x: Variant in feed.get("agents", []):
		var g: Dictionary = x
		var name := String(g.get("agent", ""))
		if not _agent_nodes.has(name):
			continue
		var from: Vector3 = _districts.to_local(((_agent_nodes[name] as Dictionary)["node"] as Node3D).global_position)
		var seen := {}
		for r: Variant in g.get("recent", []):
			var repo := String((r as Dictionary).get("repo", ""))
			if _repo_pos.has(repo) and not seen.has(repo):
				seen[repo] = true
				lines.surface_add_vertex(from)
				lines.surface_add_vertex(_repo_pos[repo] as Vector3)
				any = true
	if any:
		lines.surface_end()
		_mesh(lines, _holo(Color(0.75, 0.6, 1.0), 0.8), Vector3.ZERO, _districts)


func _pick_at(screen: Vector2) -> void:
	var best := -1
	var best_d := 40.0
	for i in _picks.size():
		var n: Variant = _picks[i].get("node")
		if not (n is Node3D) or not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree():
			continue
		var wp: Vector3 = (n as Node3D).global_position
		if _cam.is_position_behind(wp):
			continue
		var d := _cam.unproject_position(wp).distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_select(best)


func _select(i: int) -> void:
	if i < 0:
		_inspector.visible = false
		_focus_want = Vector3(0, 1.8, 0)
		_settle = maxf(_settle, 2.0)
		return
	var p: Dictionary = _picks[i]
	_focus_want = (p["node"] as Node3D).global_position
	_settle = maxf(_settle, 3.0)
	_inspector_text.text = "[color=#ffd27a]%s[/color]\n%s" % [String(p.get("title", "")), String(p.get("body", ""))]
	for c in _inspector_bar.get_children():
		c.queue_free()
	var ask := String(p.get("ask", ""))
	if ask != "":
		_inspector_bar.add_child(_bench_button("Ask the Mind", ask, func() -> void: _send(ask)))
	var url := String(p.get("url", ""))
	if url != "":
		_inspector_bar.add_child(_bench_button("Open", url, func() -> void: OS.shell_open(url)))
	var title := String(p.get("title", ""))
	if title.begins_with("repository · "):
		var know: Dictionary = feed.get("knowledge", {}) if feed.get("knowledge") is Dictionary else {}
		var k: Variant = know.get(title.trim_prefix("repository · ").to_lower())
		if k is Dictionary:
			var note_path := String((k as Dictionary).get("path", ""))
			_inspector_bar.add_child(_bench_button("Open note in Obsidian", note_path, func() -> void: OS.shell_open("obsidian://open?path=" + note_path.uri_encode())))
	_inspector_bar.add_child(_bench_button("Assign to i3 seat", "Post a work order about this", func() -> void: _order({"title": String(p.get("title", "")), "url": url, "kind": "rig", "id": "pick:" + String(p.get("title", ""))}, "claude (i3 seat)")))
	_inspector_bar.add_child(_bench_button("Back to the whole colony", "Backspace", func() -> void: _select(-1)))
	_inspector.visible = true


func _build_inspector() -> void:
	var layer := _chat.get_parent()
	_inspector = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.1, 0.9)
	sb.border_color = Color(1.0, 0.82, 0.48, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	_inspector.add_theme_stylebox_override("panel", sb)
	_inspector.visible = false
	layer.add_child(_inspector)
	var v := VBoxContainer.new()
	_inspector.add_child(v)
	_inspector_text = RichTextLabel.new()
	_inspector_text.bbcode_enabled = true
	_inspector_text.selection_enabled = true
	_inspector_text.fit_content = true
	_inspector_text.custom_minimum_size = Vector2(520, 0)
	_inspector_text.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(_inspector_text)
	_inspector_bar = HBoxContainer.new()
	v.add_child(_inspector_bar)
	_legend = RichTextLabel.new()
	_legend.bbcode_enabled = true
	_legend.visible = false
	_legend.add_theme_font_size_override("normal_font_size", 14)
	_legend.text = """[color=#ffd27a]HOW TO READ THE COLONY[/color]  (L closes)
[b]Rigs[/b]: MSI workshop, i3 engine room, L9 hangar, xanadu library at the centre. Brightness = how fresh the last heartbeat is.
[b]Pylons around a rig[/b]: its heartbeat checks. [color=#46d38a]green[/color] passing, [color=#ff6b6b]red[/color] failing; height = how long the check took.
[b]Towers around the MSI[/b]: its spine services (CHORUS). [color=#59c3ff]cyan[/color] up, [color=#ff6b6b]red[/color] down; core services stand taller.
[b]Amber slabs around xanadu[/b]: the Steward's open questions for Keath.
[b]The Forge[/b]: one building per repository. Floors = open PRs by stage: dim grey draft, [color=#73b8ff]blue[/color] needs review, [color=#b39bff]violet[/color] stale review, [color=#ff9a40]orange[/color] changes requested, [color=#59f28c]green[/color] approved. Red cap = share failing CI.
[b]Violet lines[/b]: an agent and the repositories where it has PRs in flight.
[b]Anything that flies[/b] is a real event: a new heartbeat (rig to xanadu), an order (you to a seat), a receipt (seat to you).
[b]The Mind[/b] sits over what it is attending to; its rings turn only while it is thinking.
Click anything to inspect it. Backspace returns to the whole colony."""
	layer.add_child(_legend)


func _shoot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("HOLOMIND_SHOT ", shot_path, " ", img.get_width(), "x", img.get_height(), " frames=", _frames, " window_at=", DisplayServer.window_get_position())
	get_tree().quit(0)


func _input(event: InputEvent) -> void:
	# Esc always quits, even while typing (brief: never trap the screen).
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _inspector != null and _inspector.visible:
			_select(-1)
			get_viewport().set_input_as_handled()
			return
		if _palette != null and _palette.visible:
			_palette.visible = false   # Esc closes the palette first; a second Esc quits
			get_viewport().set_input_as_handled()
			return
		get_tree().quit(0)
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_K and (event as InputEventKey).ctrl_pressed:
		_open_palette()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	_settle = maxf(_settle, 1.0)
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			get_tree().quit(0)
		elif k == KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		elif k >= KEY_0 and k <= KEY_3:
			_set_layer((k - KEY_1) if k != KEY_0 else -1)
		elif k == KEY_BACKSPACE:
			_select(-1)
		elif k == KEY_L:
			_legend.visible = not _legend.visible
		elif k == KEY_H:
			_text_hidden = not _text_hidden
			_apply_text_visibility()
		elif k == KEY_V:
			_cine = not _cine
			_subtitle.text = "Cinematic camera ON: it follows each real event (heartbeat, order, receipt), then returns to the wide view." if _cine else "Cinematic camera off: drag to orbit."
		elif k == KEY_C and not (event as InputEventKey).ctrl_pressed:
			DisplayServer.clipboard_set(_brief_text())
			_subtitle.text = "Copied the whole cockpit brief to the clipboard: fleet, agents, work waiting, conversation, next steps."
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			if mb.pressed:
				_press_at = mb.position
			elif mb.position.distance_to(_press_at) < 6.0:
				_pick_at(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(6.0, _dist - 0.6)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(24.0, _dist + 0.6)
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.004, 0.1, 1.35)
