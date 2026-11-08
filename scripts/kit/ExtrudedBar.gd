extends Node3D
## KIT: ExtrudedBar. A "building" whose height is a quantity (e.g. open PRs on a repo).
##
## Encodings (all on shaders/kit/data_emissive.gdshader):
##   height         = value * unit_height        (one visible band per unit: count by eye)
##   hue            = status_color               (ok / warn / alert / unknown)
##   emission       = urgency, CAPPED            (a crisis can't blind the rest of the screen)
##   desaturation   = staleness                  (old facts go grey)
##   rim            = selected                   (a UI fact)
##   halo           = urgency above halo_threshold (billboard glow card; bloom you can trust in GL)
##   flash          = pulse()                    (call ONLY when a real event lands; decays in pulse_s)
##   hatch          = alert                      (redundant with hue, for colour-blind eyes)
##   ghost outline  = max_value                  (capacity / threshold, so height has a reference)
##   label          = exact value, MSDF text, hidden past label_lod_m (LOD: numbers only up close)
## A bar with value 0 still draws a thin plinth: zero is a fact and must not look like "missing".
## Unknown (has_data = false) draws a grey dotted-edge stub with "?" so it is never read as zero.
## Idle cost: none. _process runs only while a pulse is decaying, then switches itself off.
## Renderer: any.

const EMISSIVE: Shader = preload("res://shaders/kit/data_emissive.gdshader")
const HALO: Shader = preload("res://shaders/kit/halo_card.gdshader")

@export var value: float = 1.0
@export var max_value: float = 0.0          # 0 = no ghost outline
@export var unit_height: float = 0.3        # world units per 1.0 of value
@export var footprint: float = 0.8
@export var status_color: Color = Color(0.25, 0.85, 1.0)
@export var urgency: float = 0.3
@export var staleness: float = 0.0
@export var selected: bool = false
@export var alert_hatch: bool = false
@export var has_data: bool = true
@export var caption: String = ""
@export var label_lod_m: float = 40.0
@export var pulse_s: float = 1.2
@export var label_font: Font = null
@export var halo_threshold: float = 0.5   # urgency below this gets no halo at all

var _bar: MeshInstance3D = null
var _cap: MeshInstance3D = null
var _ghost: MeshInstance3D = null
var _label: Label3D = null
var _halo: MeshInstance3D = null
var _halo_mat: ShaderMaterial = null
var _bar_mat: ShaderMaterial = null
var _cap_mat: ShaderMaterial = null
var _pulse: float = 0.0


func _ready() -> void:
	_bar = MeshInstance3D.new()
	_cap = MeshInstance3D.new()
	_ghost = MeshInstance3D.new()
	_label = Label3D.new()
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = EMISSIVE
	_cap_mat = ShaderMaterial.new()
	_cap_mat.shader = EMISSIVE
	_bar.material_override = _bar_mat
	_halo = MeshInstance3D.new()
	_halo.mesh = QuadMesh.new()
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO
	_halo.material_override = _halo_mat
	_cap.material_override = _cap_mat
	for m: MeshInstance3D in [_bar, _cap, _ghost, _halo]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.009
	_label.outline_size = 10
	_label.outline_modulate = Color(0.0, 0.02, 0.06, 0.9)
	_label.no_depth_test = false
	if label_font != null:
		_label.font = label_font
	# Label LOD: the exact number only where it can be read; far away the bar's height says enough.
	_label.visibility_range_end = label_lod_m
	_label.visibility_range_end_margin = 4.0
	_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_label)
	set_process(false)
	refresh()


## Rebuild geometry and push uniforms. Call after changing any exported field.
func refresh() -> void:
	if _bar == null:
		return
	var h: float = maxf(value, 0.0) * unit_height
	var known: bool = has_data
	if not known:
		h = unit_height * 0.5
	var plinth: float = 0.04   # value 0 still shows a plinth: zero is data
	var body_h: float = maxf(h, plinth)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(footprint, body_h, footprint)
	_bar.mesh = box
	_bar.position = Vector3(0.0, body_h * 0.5, 0.0)
	var col: Color = status_color if known else Color(0.42, 0.45, 0.5)
	_bar_mat.set_shader_parameter("status_color", col)
	_bar_mat.set_shader_parameter("urgency", urgency if known else 0.0)
	_bar_mat.set_shader_parameter("staleness", staleness if known else 1.0)
	_bar_mat.set_shader_parameter("selected", 1.0 if selected else 0.0)
	_bar_mat.set_shader_parameter("hatch", 1.0 if (alert_hatch and known) else 0.0)
	_bar_mat.set_shader_parameter("half_size", Vector3(footprint, body_h, footprint) * 0.5)
	_bar_mat.set_shader_parameter("unit_height", unit_height if (known and h > unit_height * 1.5) else 0.0)
	_bar_mat.set_shader_parameter("local_base_y", -body_h * 0.5)
	_bar_mat.set_shader_parameter("emission_cap", 1.35)
	# Cap plate: the brightest part, where the eye compares heights. Its glow is capped too.
	var cap_box: BoxMesh = BoxMesh.new()
	cap_box.size = Vector3(footprint * 1.08, 0.05, footprint * 1.08)
	_cap.mesh = cap_box
	_cap.position = Vector3(0.0, body_h + 0.025, 0.0)
	_cap.visible = known
	_cap_mat.set_shader_parameter("status_color", col)
	_cap_mat.set_shader_parameter("urgency", clampf(urgency + 0.3, 0.0, 1.0))
	_cap_mat.set_shader_parameter("staleness", staleness)
	_cap_mat.set_shader_parameter("emission_cap", 1.7)
	_cap_mat.set_shader_parameter("half_size", Vector3(footprint * 1.08, 0.05, footprint * 1.08) * 0.5)
	# Halo: sized to the bar, strength = how far urgency is past the threshold (0 below it).
	_halo.scale = Vector3(footprint * 3.2, body_h + 2.0, 1.0)
	_halo.position = Vector3(0.0, body_h * 0.5, 0.0)
	_halo_mat.set_shader_parameter("halo_color", col)
	_apply_pulse()
	# Ghost outline: capacity / threshold. Wireframe, dim, never animated.
	if max_value > 0.0 and known:
		_ghost.mesh = _wire_box(Vector3(footprint * 1.12, max_value * unit_height, footprint * 1.12))
		_ghost.material_override = _ghost_material(col)
		_ghost.visible = true
	else:
		_ghost.visible = false
	_label.text = ("%s\n%d" % [caption, roundi(value)]) if known else ("%s\n?" % caption)
	_label.modulate = Color(0.85, 0.95, 1.0) if staleness < 0.5 else Color(0.6, 0.64, 0.7)
	_label.position = Vector3(0.0, body_h + 0.75, 0.0)


## A real event landed on this bar (PR opened, CI failed...). Flash once, decay, go still.
func pulse() -> void:
	_pulse = 1.0
	_apply_pulse()
	set_process(true)


func _process(delta: float) -> void:
	_pulse = maxf(_pulse - delta / pulse_s, 0.0)
	_apply_pulse()
	if _pulse <= 0.0:
		set_process(false)


func _apply_pulse() -> void:
	var p: float = _pulse * _pulse   # ease-out: bright onset, quick fall
	_bar_mat.set_shader_parameter("event_pulse", p)
	_cap_mat.set_shader_parameter("event_pulse", p)
	var over: float = 0.0
	if has_data and urgency > halo_threshold:
		over = (urgency - halo_threshold) / maxf(1.0 - halo_threshold, 0.01)
	var halo: float = clampf(0.85 * over * (1.0 - 0.7 * staleness) + 0.6 * p, 0.0, 1.0)
	_halo_mat.set_shader_parameter("intensity", halo)
	_halo.visible = halo > 0.001


func _ghost_material(col: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(col.r, col.g, col.b, 0.8)
	return m


func _wire_box(size: Vector3) -> ArrayMesh:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var y1: float = size.y
	var c: PackedVector3Array = PackedVector3Array([
		Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
		Vector3(-hx, y1, -hz), Vector3(hx, y1, -hz), Vector3(hx, y1, hz), Vector3(-hx, y1, hz)])
	var idx: PackedInt32Array = PackedInt32Array([4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7])
	# The threshold (top square) is the fact; the verticals only anchor it, so they fade to the floor.
	var cols: PackedColorArray = PackedColorArray()
	for i: int in range(8):
		cols.append(Color(1, 1, 1, 0.03) if i < 4 else Color(1, 1, 1, 0.55))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = c
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return am
