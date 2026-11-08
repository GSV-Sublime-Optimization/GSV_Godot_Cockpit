extends RefCounted

## Pure procedural 3D geometry for the source-backed workstation.
## Holographic appearance conveys topology; it NEVER certifies capability.
## No files, sockets, timers, external runner, or permissions are created here.

const CYAN := Color("#62d9f5")
const AZURE := Color("#396fb7")
const GOLD := Color("#fbc87a")
const MUTE := Color("#40536e")
const GHOST := Color("#132438")

static func material(color: Color, intensity: float = 0.9, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = intensity
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

static func mesh(parent: Node3D, shape: Mesh, color: Color, glow: float = 0.9, alpha: float = 1.0, name: String = "Hologram") -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = name
	item.mesh = shape
	item.material_override = material(color, glow, alpha)
	parent.add_child(item)
	return item

static func cylinder(parent: Node3D, top: float, bottom: float, height: float, segments: int, color: Color, at: Vector3 = Vector3.ZERO, glow: float = 0.9, alpha: float = 1.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = segments
	var item := mesh(parent, shape, color, glow, alpha, "HoloColumn")
	item.position = at
	return item

static func torus(parent: Node3D, radius: float, width: float, color: Color, at: Vector3 = Vector3.ZERO, glow: float = 1.0) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = maxf(0.01, radius - width)
	shape.outer_radius = radius + width
	shape.rings = 14
	shape.ring_segments = 96
	var item := mesh(parent, shape, color, glow, 1.0, "HoloOrbit")
	item.position = at
	return item

static func wire(parent: Node3D, a: Vector3, b: Vector3, color: Color, width: float = 0.025, alpha: float = 0.8) -> MeshInstance3D:
	var direction := b - a
	var shape := CylinderMesh.new()
	shape.top_radius = width
	shape.bottom_radius = width
	shape.height = maxf(direction.length(), 0.001)
	shape.radial_segments = 5
	var part := mesh(parent, shape, color, 1.25, alpha, "EvidenceLink")
	part.position = (a + b) * 0.5
	if direction.length() > 0.001:
		part.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	return part

static func legend(parent: Node3D, text: String, at: Vector3, size: int = 26, color: Color = CYAN) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.027
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = color
	label.position = at
	parent.add_child(label)
	return label

static func stage(world: Node) -> Dictionary:
	## A giant skeletal arena, nested depth rings and four distinct decks.
	## These are UI coordinate guides, never inferred host-to-host links.
	var theatre := Node3D.new()
	theatre.name = "HolographicTheatre"
	world.add_child(theatre)

	cylinder(theatre, 12.8, 12.8, 0.12, 96, GHOST, Vector3(0, -5.15, 0), 0.55, 0.88)
	for r in [4.0, 7.4, 10.4, 12.6]:
		torus(theatre, r, 0.015, MUTE, Vector3(0, -5.05, 0), 0.55)
	for i in range(-12, 13, 2):
		wire(theatre, Vector3(i, -5.02, -12), Vector3(i, -5.02, 12), MUTE, 0.009, 0.26)
		wire(theatre, Vector3(-12, -5.02, i), Vector3(12, -5.02, i), MUTE, 0.009, 0.26)

	var animated: Array[Node3D] = []
	var kernel := Node3D.new()
	kernel.name = "NonAuthoritativeObservationBeacon"
	theatre.add_child(kernel)
	var core_sphere := SphereMesh.new()
	core_sphere.radius = 0.96
	core_sphere.height = 1.92
	core_sphere.radial_segments = 32
	core_sphere.rings = 16
	mesh(kernel, core_sphere, Color("#167f9d"), 1.4, 0.7, "SourceNotSentience")
	for i in range(3):
		var dial := torus(kernel, 1.36 + float(i) * 0.25, 0.025, CYAN if i == 0 else AZURE, Vector3.ZERO, 1.8)
		dial.rotation = Vector3(0.40 * i, 0.48 * i, PI * 0.34 * i)
		animated.append(dial)
	cylinder(theatre, 0.9, 1.0, 0.25, 12, CYAN, Vector3(0, -0.6, 0), 0.75)
	cylinder(theatre, 0.75, 0.75, 3.65, 12, AZURE, Vector3(0, -3.2, 0), 0.32, 0.12)
	var kernel_title := legend(theatre, "Ξ  OBSERVATION ANCHOR", Vector3(0, 2.6, 0), 28)
	kernel_title.pixel_size = 0.013
	var kernel_scope := legend(theatre, "0 LOCAL EXECUTION RIGHTS", Vector3(0, -1.25, 0), 19, GOLD)
	kernel_scope.pixel_size = 0.010

	for deck in [
		{"name": "PROJECT CONCOURSE", "radius": 7.5, "y": 4.0, "hue": CYAN},
		{"name": "MISSION TRANSECT", "radius": 4.7, "y": 0.6, "hue": GOLD},
		{"name": "FLEET VAULT", "radius": 10.6, "y": -3.0, "hue": AZURE},
		{"name": "SERVICE PERIMETER", "radius": 10.2, "y": -0.1, "hue": MUTE},
		{"name": "LOCAL TOOL PRESENCE", "radius": 6.3, "y": -1.55, "hue": GOLD}
	]:
		var rad: float = deck["radius"]
		var y: float = deck["y"]
		torus(theatre, rad, 0.035, deck["hue"], Vector3(0, y, 0), 1.15)
		torus(theatre, rad + 0.35, 0.013, MUTE, Vector3(0, y, 0), 0.3)
		var deck_label := legend(theatre, deck["name"], Vector3(rad * 0.71, y + 0.40, -rad * 0.71), 21, deck["hue"])
		deck_label.pixel_size = 0.012
		for j in range(12):
			var angle := TAU * float(j) / 12.0
			var a := Vector3(cos(angle) * rad, y, sin(angle) * rad)
			var b := Vector3(cos(angle) * (rad + 0.55), y, sin(angle) * (rad + 0.55))
			wire(theatre, a, b, deck["hue"], 0.02, 0.7)

	## Upper and lower spatial witness pillars create a navigable sense of scale.
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.16
		var at := Vector3(cos(a) * 12.9, -1.05, sin(a) * 12.9)
		cylinder(theatre, 0.07, 0.17, 9.0, 6, AZURE, at, 0.7, 0.46)
		torus(theatre, 0.33, 0.018, CYAN, at + Vector3(0, 4.4, 0), 0.7)
	return {"root": theatre, "animated": animated}

static func object(parent: Node3D, entry: Dictionary, color: Color) -> Dictionary:
	## Domain-specific architectural silhouettes communicate type from shape.
	var root := Node3D.new()
	root.name = "Observed_" + String(entry.get("kind", "node"))
	root.position = entry["position"]
	parent.add_child(root)
	var kind: String = entry["kind"]
	var radius := 0.65 if kind == "rig" else 0.46
	var spin: Node3D = Node3D.new()
	spin.name = "StateGlyph"
	root.add_child(spin)
	match kind:
		"rig":
			cylinder(root, 0.68, 0.90, 0.20, 8, MUTE, Vector3(0, -0.62, 0), 0.45)
			cylinder(root, 0.48, 0.60, 1.20, 8, color, Vector3.ZERO, 0.85, 0.83)
			cylinder(spin, 0.20, 0.44, 0.42, 8, color, Vector3(0, 0.93, 0), 1.1)
			torus(root, 0.84, 0.034, color, Vector3(0, -0.46, 0), 1.3)
		"project":
			cylinder(root, 0.26, 0.52, 0.85, 6, color, Vector3.ZERO, 1.20)
			if entry.get("game", false):
				torus(root, 0.94, 0.023, GOLD, Vector3(0, -0.34, 0), 1.2)
			cylinder(spin, 0.03, 0.26, 0.50, 6, CYAN, Vector3(0, 0.69, 0), 1.65)
			torus(root, 0.58, 0.024, color, Vector3(0, -0.54, 0), 0.65)
		"mission":
			cylinder(spin, 0.0, 0.48, 0.75, 5, color, Vector3(0, 0.35, 0), 1.35)
			var lower := cylinder(spin, 0.0, 0.48, 0.75, 5, color, Vector3(0, -0.35, 0), 1.35)
			lower.rotation.x = PI
			torus(root, 0.54, 0.026, color, Vector3(0, -0.57, 0), 1.25)
		"service":
			cylinder(root, 0.33, 0.45, 1.25, 4, color, Vector3.ZERO, 0.7, 0.8)
			cylinder(spin, 0.02, 0.33, 0.26, 4, color, Vector3(0, 0.75, 0), 1.4)
			torus(root, 0.53, 0.026, color, Vector3(0, -0.68, 0), 0.8)
		"tool":
			# A cartridge for local evidence. Neither a CLI seat nor an attached session.
			cylinder(root, 0.44, 0.44, 0.25, 8, MUTE, Vector3(0, -0.50, 0), 0.5)
			cylinder(spin, 0.24, 0.38, 0.55, 8, color, Vector3(0, 0.03, 0), 0.9)
			torus(root, 0.58, 0.025, GOLD, Vector3(0, -0.60, 0), 0.8)

	var selection := Node3D.new()
	selection.name = "FocusedSource"
	selection.visible = false
	root.add_child(selection)
	var halo := torus(selection, radius * 1.8, 0.045, GOLD, Vector3(0, -0.86, 0), 2.7)
	var vertical := cylinder(selection, 0.004, 0.005, 4.0, 6, GOLD, Vector3(0, 1.0, 0), 1.6, 0.50)
	vertical.visible = true
	torus(selection, radius * 1.45, 0.025, GOLD, Vector3(0, 1.2, 0), 2.0)

	var label := legend(root, String(entry["title"]).substr(0, 15), Vector3(0, 1.40, 0), 27, Color("#e4f5ff"))
	label.pixel_size = 0.013
	var status_label := legend(root, String(entry["status"]).to_upper().substr(0, 18),
		Vector3(0, -1.02, 0), 18, color)
	status_label.pixel_size = 0.012
	return {"root": root, "halo": selection, "spin": spin, "pulse": halo,
		"label": label, "status_label": status_label, "entry": entry}

static func evidence_link(parent: Node3D, a: Vector3, b: Vector3, relation_kind: String = "verified_repo") -> Node3D:
	var obj := Node3D.new()
	obj.name = "SourceVerifiedRelation"
	parent.add_child(obj)
	var hue := GOLD if relation_kind == "local_path_match" else CYAN
	wire(obj, a, b, hue, 0.026, 0.78)
	wire(obj, a, b, GOLD if relation_kind == "local_path_match" else AZURE, 0.080, 0.17)
	var middle := (a + b) * 0.5
	var marker := cylinder(obj, 0.02, 0.14, 0.29, 5, GOLD, middle, 1.8)
	var vector := b - a
	if vector.length() > 0.05:
		marker.basis = Basis(Quaternion(Vector3.UP, vector.normalized()))
	return obj
