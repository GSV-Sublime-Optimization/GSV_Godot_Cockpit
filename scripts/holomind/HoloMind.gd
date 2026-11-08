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
# The cockpit: agents around the table, a shared channel to talk in, speech in space.
const OUTBOX := "C:/Users/Public/colony/mindview/outbox.jsonl"
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
var _hud_clock: float = 0.0
var _sent_local: Array[Dictionary] = []   # what you typed this session, to show sent > delivered > read
var _actions_root: Node3D
const KIND_COLOURS := {"rig": Color(1.0, 0.4, 0.4), "review": Color(0.5, 0.75, 1.0), "decision": Color(1.0, 0.78, 0.35), "reply": Color(0.95, 0.95, 1.0)}
var _seen_channel: int = 0


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
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--as="):
			_speaker = arg.get_slice("=", 1)
	_build_room()
	_build_layers()
	_build_mind()
	_build_cockpit()
	_build_hud()
	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)
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
	_typebox.placeholder_text = "Type to the colony… (@mind is the default; @claude, @msi, @muse…) · Enter to send · it can only talk, never act"
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
	_far.rotation.y += delta * 0.004
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
		node.scale = Vector3.ONE * (1.0 + 0.5 * float(rec["pulse"]) + 0.04 * sin(_t * 2.0 + float(node.get_index())))
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
	var thinking := int(feed.get("mind_thinking", 0))
	if thinking > 0:
		_waiting_text += " · the Mind is thinking (%d message%s queued)" % [thinking, "" if thinking == 1 else "s"]


func _update_hud() -> void:
	_hud.text = "HOLOMIND · the colony cockpit (i3 Claude) · talks, never acts · %s · WORK WAITING: %s\n%s · drag: orbit · wheel: zoom · 1/2/3: layer · 0: all · C: copy brief · F11: fullscreen · Esc: quit" % [
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


func _set_layer(l: int) -> void:
	focus_layer = l
	for c in _stars.get_children():
		if c is Label3D and c.has_meta("detail"):
			(c as Label3D).text = String(c.get_meta("detail")) if focus_layer == 1 else "vitals"
	_update_hud()


func _shoot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("HOLOMIND_SHOT ", shot_path, " ", img.get_width(), "x", img.get_height(), " frames=", _frames)
	get_tree().quit(0)


func _input(event: InputEvent) -> void:
	# Esc always quits, even while typing (brief: never trap the screen).
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
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
			_set_layer((k - KEY_1) if k != KEY_0 else -1)
		elif k == KEY_C and not (event as InputEventKey).ctrl_pressed:
			DisplayServer.clipboard_set(_brief_text())
			_subtitle.text = "Copied the whole cockpit brief to the clipboard: fleet, agents, work waiting, conversation, next steps."
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
