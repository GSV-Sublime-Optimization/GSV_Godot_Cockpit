extends MeshInstance3D
## KIT: DataTrail. A fading ribbon along a mover's REAL recorded path.
##
## Honesty contract:
## - Only add_sample() adds geometry. Call it when a real position report arrives, with the
##   report's own timestamp. Never interpolate, smooth or extrapolate between samples here.
## - Brightness = age (shaders/kit/trail.gdshader). Age only advances when set_now() is called,
##   so an idle trail costs zero CPU and zero redraws. Call set_now() from a slow timer (1 Hz is
##   plenty) or when a sample arrives.
## - Samples older than max_age_s are dropped (they would be invisible anyway).
## Renderer: any (ArrayMesh triangle strip + unshaded additive shader).

const TRAIL_SHADER: Shader = preload("res://shaders/kit/trail.gdshader")

@export var trail_color: Color = Color(0.25, 0.85, 1.0)
@export var width: float = 0.22
@export var lift: float = 0.04
@export var max_age_s: float = 120.0
@export var tick_every_s: float = 30.0
@export var max_samples: int = 256

var _points: PackedVector3Array = PackedVector3Array()
var _times: PackedFloat32Array = PackedFloat32Array()
var _mat: ShaderMaterial = null
var _now: float = 0.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = TRAIL_SHADER
	_mat.set_shader_parameter("trail_color", trail_color)
	_mat.set_shader_parameter("max_age_s", max_age_s)
	_mat.set_shader_parameter("tick_every_s", tick_every_s)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Record a real position at time t_s (seconds, any epoch, as long as set_now uses the same one).
func add_sample(pos: Vector3, t_s: float) -> void:
	if not _points.is_empty() and _points[_points.size() - 1].distance_squared_to(pos) < 1e-6:
		_times[_times.size() - 1] = t_s   # stood still: refresh the time, add no geometry
	else:
		_points.append(pos)
		_times.append(t_s)
	while _points.size() > max_samples:
		_points.remove_at(0)
		_times.remove_at(0)
	set_now(maxf(_now, t_s))


## Advance the clock the shader fades against. Drops samples too old to see, then rebuilds.
func set_now(t_s: float) -> void:
	_now = t_s
	while _times.size() > 2 and _now - _times[1] > max_age_s:
		_points.remove_at(0)
		_times.remove_at(0)
	if _mat != null:
		_mat.set_shader_parameter("now_s", _now)
	_rebuild()


func sample_count() -> int:
	return _points.size()


func _rebuild() -> void:
	if _points.size() < 2:
		mesh = null
		return
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var n: int = _points.size()
	for i: int in range(n):
		var prev: Vector3 = _points[maxi(i - 1, 0)]
		var next: Vector3 = _points[mini(i + 1, n - 1)]
		var tangent: Vector3 = next - prev
		var side: Vector3 = tangent.cross(Vector3.UP)
		if side.length_squared() < 1e-8:
			side = Vector3.RIGHT   # vertical motion: any horizontal side is as true as another
		side = side.normalized() * (width * 0.5)
		var p: Vector3 = _points[i] + Vector3(0.0, lift, 0.0)
		verts.append(p - side)
		uvs.append(Vector2(_times[i], 0.0))
		verts.append(p + side)
		uvs.append(Vector2(_times[i], 1.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	mesh = am
