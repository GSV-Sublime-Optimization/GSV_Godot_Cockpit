class_name CapabilityAtlasLayer
extends Node3D

## The Capability Atlas as a holographic LAYER in the volume (Slice 5).
##
## One node per atlas entry, carrying its machine, its D/I/C/Q/U/M grade,
## its cost class, and its honest live state — laid out as a shelf behind the
## header card. The layer reuses the entry's own machinery, it does not
## invent parallel machinery:
##   - pull-up (lambda) via HoloCoordinateStack.pull_distance / pull_scale,
##     the same constants as HoloLayer (2.5 / 0.6);
##   - card quads use the holo_surface shader with the no-cut slice plane,
##     coloured by HoloLayer.state_color;
##   - cards billboard to the companion's gaze via
##     HoloCoordinateStack.billboard_basis;
##   - ray hits on the header use HoloCoordinateStack.hit_layer (called by
##     HoloRoom, like every other layer).
##
## At rest the layer is its header card only (counts + current slice); the
## entry shelf expands when the layer is pulled up (lambda > 0.05). Slicing
## (semantic axes: machine, cost class, grade) filters which entry nodes are
## visible — the slice is a filter on the shelf, never a deletion: hidden
## entries still exist as nodes and return when the slice changes.
##
## Honesty: unverified entries (grade D, incl. oh-my-pi, wrapper, Soul Claw /
## MetaClaw and every synthesis §5 item) are explicit nodes, dimmed
## (base_alpha 0.25) and labelled UNVERIFIED — never omitted, never dressed
## as live. The OpenClaw entry carries its discrepancy flag on its card
## (both sides, entry follows Lane B). An entry is "live" on its card only
## when the reader's overlay says a fresh probe observed it (overlay
## "live_probe"); otherwise the card shows the static honest state.
##
## Header honesty: every entry is GRADED (a dated static grade); only an entry
## a fresh telemetry probe observed up counts as LIVE. With no fresh snapshot
## the header says "0 live" and why. A static "live" in the graded file is a
## grade, not a reading. Degraded cards pulse only while the room is awake
## (motion = real events only); at rest they hold a fixed dim alpha.

const SURFACE_SHADER: Shader = preload("res://shaders/holo_surface.gdshader")

const PULL_DISTANCE := 2.5
const PULL_KAPPA := 0.6
const HEADER_SIZE := Vector2(2.4, 1.5)
const ENTRY_SIZE := Vector2(0.9, 0.5)
const COLUMNS := 12
const COL_SPACING := 0.98
const ROW_SPACING := 0.66
const HEADER_OFFSET := Vector3(0.0, 3.1, 0.0)
const BASE_POSITION := Vector3(0.0, 3.6, 2.4)

## Slice views, cycled by the HoloTab "Atlas" button. "proven" = grade Q or
## better (Q/U/M); "unverified" = grade D (the §5 items, oh-my-pi, wrapper,
## Soul Claw / MetaClaw included).
const SLICE_VIEWS: PackedStringArray = [
	"all", "msi", "i3", "l9", "xanadu",
	"tokenless", "cloud", "mixed",
	"proven", "unverified",
]
const PROVEN_GRADES: PackedStringArray = ["Q", "U", "M"]

var pull: float = 0.0
var pull_target: float = 0.0
var slice_view: String = "all"
## Telemetry state the entries were overlaid with: live / stale / unknown.
var telemetry_state: String = "unknown"
## Set by HoloRoom: true only while a real event is being shown.
var motion_enabled: bool = false

var _base_position: Vector3 = BASE_POSITION
var _header: Node3D
var _header_label: Label3D
var _header_mat: ShaderMaterial
var _entry_nodes: Array = []
var _entries: Array = []
var _expanded: bool = false


func _ready() -> void:
	position = _base_position
	_build_header()


func build_from(entries: Array, overlay_telemetry_state: String = "unknown") -> void:
	telemetry_state = overlay_telemetry_state
	_entries = []
	for raw in entries:
		if typeof(raw) == TYPE_DICTIONARY:
			_entries.append((raw as Dictionary).duplicate(true))
	for node in _entry_nodes:
		(node as Node).queue_free()
	_entry_nodes.clear()
	for index in _entries.size():
		var node := _build_entry_node(_entries[index], index)
		add_child(node)
		_entry_nodes.append(node)
	_refresh_header()
	_apply_slice()


func entry_count() -> int:
	return _entries.size()


func visible_count() -> int:
	var n := 0
	for node in _entry_nodes:
		if (node as Node3D).visible:
			n += 1
	return n


func live_probe_count() -> int:
	var n := 0
	for raw in _entries:
		if String((raw as Dictionary).get("overlay", "")) == "live_probe":
			n += 1
	return n


func unverified_count() -> int:
	var n := 0
	for raw in _entries:
		if String((raw as Dictionary).get("grade", "")) == "D":
			n += 1
	return n


## Every parsed entry carries a grade; "graded" is the honest count of nodes.
func graded_count() -> int:
	return _entries.size()


## Live = a fresh telemetry probe observed the entry up (overlay live_probe
## AND state live). A static "live" from the graded file is not counted.
func live_count() -> int:
	var n := 0
	for raw in _entries:
		var entry := raw as Dictionary
		if String(entry.get("overlay", "")) == "live_probe" and String(entry.get("state", "")) == "live":
			n += 1
	return n


func header_text() -> String:
	return _header_label.text if _header_label != null else ""


func is_settled() -> bool:
	return is_equal_approx(pull, pull_target)


## The visible entry card under the screen point (only while expanded), as
## {id, title, entry}; empty when nothing is hit.
func entry_at(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not _expanded:
		return {}
	for i in _entry_nodes.size():
		var node := _entry_nodes[i] as Node3D
		if not node.visible:
			continue
		var hit: Dictionary = HoloCoordinateStack.hit_layer(camera, screen_pos, node, ENTRY_SIZE * 0.5)
		if bool(hit.get("hit", false)):
			var entry: Dictionary = _entries[i]
			return {
				"id": String(entry.get("id", "")),
				"title": "Atlas: " + String(entry.get("name", entry.get("id", "?"))),
				"entry": entry,
			}
	return {}


func header_node() -> Node3D:
	return _header


func cycle_slice_view() -> String:
	var i := SLICE_VIEWS.find(slice_view)
	slice_view = SLICE_VIEWS[(i + 1) % SLICE_VIEWS.size()]
	_apply_slice()
	_refresh_header()
	return slice_view


func set_slice_view(view: String) -> bool:
	if not SLICE_VIEWS.has(view):
		return false
	slice_view = view
	_apply_slice()
	_refresh_header()
	return true


func toggle_pull() -> void:
	pull_target = 0.0 if pull_target > 0.5 else 1.0
	_expanded = pull_target > 0.5
	_apply_slice()


func set_pulled(pulled: bool) -> void:
	pull_target = 1.0 if pulled else 0.0
	_expanded = pulled
	_apply_slice()


## Per-frame: interpolate pull toward its target, move the shelf toward the
## camera along camera-forward by pull * PULL_DISTANCE, scale by
## (1 + pull * PULL_KAPPA) — the same pull as HoloLayer — and billboard
## every card at the gaze. Degraded entries flicker, like Skyclaw's desk.
func update_frame(delta: float, camera: Camera3D) -> void:
	pull = move_toward(pull, pull_target, delta * 1.5)
	var fwd: Vector3 = -camera.global_transform.basis.z.normalized()
	position = _base_position + fwd * (pull * PULL_DISTANCE)
	var s: float = HoloCoordinateStack.pull_scale(1.0, pull, PULL_KAPPA)
	scale = Vector3.ONE * s
	if pull > 0.05 and not _expanded:
		_expanded = true
		_apply_slice()
	elif pull <= 0.05 and _expanded and pull_target <= 0.5:
		_expanded = false
		_apply_slice()
	for node in _entry_nodes:
		_billboard_card(node as Node3D, camera)
	_billboard_card(_header, camera)
	_flicker_degraded()


func _billboard_card(node: Node3D, camera: Camera3D) -> void:
	if node == null:
		return
	var b := HoloCoordinateStack.billboard_basis(node.global_position, camera.global_position)
	node.global_transform = Transform3D(b, node.global_position)


func _flicker_degraded() -> void:
	# At rest a degraded card holds a fixed dim alpha; it pulses only while
	# the room is showing a real event.
	var flicker := 0.45
	if motion_enabled:
		flicker = 0.35 + 0.25 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0))
	for node in _entry_nodes:
		var mat: ShaderMaterial = (node as Node3D).get_meta("holo_mat", null)
		if mat == null:
			continue
		if String((node as Node3D).get_meta("entry_state", "")) == "degraded":
			mat.set_shader_parameter("base_alpha", flicker)


static func slice_view_matches(entry: Dictionary, view: String) -> bool:
	match view:
		"all":
			return true
		"msi", "i3", "l9", "xanadu":
			return String(entry.get("machine", "")) == view
		"tokenless", "cloud", "mixed":
			return String(entry.get("cost_class", "")) == view
		"proven":
			return PROVEN_GRADES.has(String(entry.get("grade", "")))
		"unverified":
			return String(entry.get("grade", "")) == "D"
	return false


func _apply_slice() -> void:
	for i in _entry_nodes.size():
		var node := _entry_nodes[i] as Node3D
		var entry: Dictionary = _entries[i]
		node.visible = _expanded and slice_view_matches(entry, slice_view)


func _build_header() -> void:
	_header = Node3D.new()
	_header.name = "AtlasHeader"
	_header.position = HEADER_OFFSET
	add_child(_header)
	var quad := QuadMesh.new()
	quad.size = HEADER_SIZE
	_header_mat = ShaderMaterial.new()
	_header_mat.shader = SURFACE_SHADER
	_header_mat.set_shader_parameter("holo_color", Color(0.2, 0.9, 1.0))
	_header_mat.set_shader_parameter("slice_plane", Vector4(0.0, 1.0, 0.0, -100.0))
	quad.material = _header_mat
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	_header.add_child(mesh_instance)
	_header_label = Label3D.new()
	_header_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_header_label.pixel_size = 0.01
	_header_label.font_size = 16
	_header_label.outline_size = 4
	_header_label.modulate = Color(0.9, 1.0, 1.0)
	_header_label.position = Vector3(0.0, 0.0, 0.03)
	_header.add_child(_header_label)
	_refresh_header()


func _refresh_header() -> void:
	if _header_label == null:
		return
	var live_note := ""
	if telemetry_state != "live":
		live_note = " (no fresh probe: telemetry %s)" % telemetry_state
	_header_label.text = "CAPABILITY ATLAS\n%d graded · %d live%s\n%d unverified (D) · slice: %s · probed: %d" % [
		graded_count(), live_count(), live_note, unverified_count(), slice_view, live_probe_count(),
	]


func _build_entry_node(entry: Dictionary, index: int) -> Node3D:
	var node := Node3D.new()
	node.name = "AtlasEntry_" + String(entry.get("id", ""))
	var col := index % COLUMNS
	var row := index / COLUMNS
	node.position = Vector3(
		(float(col) - float(COLUMNS - 1) * 0.5) * COL_SPACING,
		-(float(row) * ROW_SPACING),
		0.0
	)
	var state := String(entry.get("state", "unknown"))
	var quad := QuadMesh.new()
	quad.size = ENTRY_SIZE
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("holo_color", HoloLayer.state_color(state))
	mat.set_shader_parameter("slice_plane", Vector4(0.0, 1.0, 0.0, -100.0))
	# Unverified nodes are dimmed: present, never dressed as live.
	mat.set_shader_parameter("base_alpha", 0.25 if String(entry.get("grade", "")) == "D" else 0.55)
	quad.material = mat
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	node.add_child(mesh_instance)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.font_size = 12
	label.outline_size = 2
	label.modulate = Color(0.9, 1.0, 1.0)
	label.position = Vector3(0.0, 0.0, 0.03)
	label.text = _entry_card_text(entry)
	node.add_child(label)
	node.set_meta("holo_mat", mat)
	node.set_meta("entry_state", state)
	node.visible = false
	return node


## Card text: name + grade/machine/cost + honest state. Label3D renders text
## literally (no BBCode), so content is set raw here — the escaping rule
## lives on the ledger (see HoloLayer).
func _entry_card_text(entry: Dictionary) -> String:
	var name := String(entry.get("name", "?"))
	if name.length() > 24:
		name = name.substr(0, 21) + "..."
	var line2 := "%s · %s · %s" % [
		String(entry.get("grade", "?")),
		String(entry.get("machine", "?")).to_upper(),
		String(entry.get("cost_class", "?")).to_upper(),
	]
	var line3 := String(entry.get("state", "unknown"))
	if String(entry.get("grade", "")) == "D":
		line3 += " · UNVERIFIED"
	if not String(entry.get("discrepancy", "")).is_empty():
		line3 += " · DISCREPANCY"
	if String(entry.get("overlay", "")) == "live_probe":
		line3 += " · PROBE"
	return "%s\n%s\n%s" % [name, line2, line3]
