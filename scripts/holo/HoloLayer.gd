class_name HoloLayer
extends Node3D

## One holographic layer: a plane n-hat . p = d floating in the volume, with
## a hologram-surface quad and a Label3D card. The layer's content is a real
## source's honest state — never fabricated data.
##
## Interaction (Keath's brief): the layer is pulled up by interpolating its
## plane distance and its scale together (lambda in [0, 1]); it billboards so
## its normal aligns with the companion's gaze. Ray hits are tested by
## HoloCoordinateStack.hit_layer against this node's global transform.
##
## Text note (PR #5 rule, applied where it belongs): external strings are
## escaped with EventStream.escape_event_text ONLY on BBCode-rendering
## surfaces (the RichTextLabel ledger). Label3D renders text literally — no
## BBCode parsing — so escaping here would corrupt the display. The card
## text is therefore set raw, and the ledger is where escaping happens.

const PULL_DISTANCE := 2.5
const PULL_KAPPA := 0.6
const CARD_SIZE := Vector2(2.4, 1.5)

var layer_id: String = ""
var layer_kind: String = ""
var layer_source: String = ""
var layer_state: String = "unknown"
var render_priority: int = 0
var pull: float = 0.0
var pull_target: float = 0.0
var billboard: bool = true
var _dimmed: bool = false

var _base_position: Vector3 = Vector3.ZERO
var _quad: MeshInstance3D
var _label: Label3D
var _mat: ShaderMaterial


static func state_color(state: String) -> Color:
	match state:
		"live":
			return Color(0.2, 1.0, 0.6)
		"stale":
			return Color(0.8, 1.0, 0.3)
		"unavailable":
			return Color(1.0, 0.6, 0.2)
		"degraded":
			return Color(1.0, 0.9, 0.2)
		"dimmed":
			return Color(0.45, 0.6, 0.8)
		"incoming":
			return Color(0.7, 0.4, 1.0)
		"planned":
			return Color(0.5, 0.6, 0.8)
		"simulated":
			return Color(1.0, 0.5, 0.9)
		"derived":
			return Color(0.75, 0.55, 1.0)
		"not_connected":
			return Color(0.45, 0.6, 0.8)
		_:
			return Color(0.35, 0.35, 0.4)


func setup(def: Dictionary, surface_shader: Shader) -> void:
	layer_id = String(def.get("id", ""))
	layer_kind = String(def.get("kind", ""))
	layer_source = String(def.get("source", ""))
	layer_state = String(def.get("state", "unknown"))
	render_priority = int(def.get("depth", 0) * 10.0)
	_base_position = def.get("pos", Vector3.ZERO)
	position = _base_position

	var quad := QuadMesh.new()
	quad.size = CARD_SIZE
	_mat = ShaderMaterial.new()
	_mat.shader = surface_shader
	_mat.set_shader_parameter("holo_color", state_color(layer_state))
	# No-cut slice plane for cards: the semantic slice cuts the VOLUME only.
	_mat.set_shader_parameter("slice_plane", Vector4(0.0, 1.0, 0.0, -100.0))
	quad.material = _mat
	_quad = MeshInstance3D.new()
	_quad.mesh = quad
	add_child(_quad)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.01
	_label.font_size = 16
	_label.outline_size = 4
	_label.modulate = Color(0.9, 1.0, 1.0)
	_label.position = Vector3(0.0, 0.0, 0.03)
	add_child(_label)
	set_content(layer_id.to_upper(), PackedStringArray(["state: " + layer_state]))


## Card text: title + honest state lines. Label3D is literal text (no BBCode),
## so content is set raw here; the escaping rule lives on the ledger.
func set_content(title: String, lines: PackedStringArray) -> void:
	var text := title
	for line in lines:
		text += "\n" + line
	_label.text = text


func set_state(state: String) -> void:
	layer_state = state
	_apply_color()
	# Degraded is a state value rendered as amplitude, not a timer: a fixed
	# dim alpha while degraded, full alpha otherwise (Slice 7 — the sin(t)
	# flicker is removed; see update_frame).
	if _mat != null:
		_mat.set_shader_parameter("base_alpha", 0.6 if state == "degraded" else 1.0)


## Selection dimming: non-focused layers dim to 40% but stay visible —
## context is never deleted (design §3.2).
func set_dimmed(dimmed: bool) -> void:
	_dimmed = dimmed
	_apply_color()
	if _label != null:
		_label.modulate = Color(0.36, 0.4, 0.4) if dimmed else Color(0.9, 1.0, 1.0)


func _apply_color() -> void:
	if _mat == null:
		return
	var color := state_color(layer_state)
	if _dimmed:
		color = color * HoloSelection.DIMMED_FACTOR
	_mat.set_shader_parameter("holo_color", color)


## Per-frame: interpolate pull toward its target, move the plane toward the
## camera along camera-forward by pull * PULL_DISTANCE, scale by
## (1 + pull * PULL_KAPPA), and billboard the card at the gaze. Degraded
## layers render at a fixed dim alpha (their state value as amplitude) —
## no timer-driven flicker remains (Slice 7).
func update_frame(delta: float, camera: Camera3D) -> void:
	pull = move_toward(pull, pull_target, delta * 1.5)
	var fwd: Vector3 = -camera.global_transform.basis.z.normalized()
	var target_pos: Vector3 = _base_position + fwd * (pull * PULL_DISTANCE)
	var s: float = HoloCoordinateStack.pull_scale(1.0, pull, PULL_KAPPA)
	if billboard:
		var b := HoloCoordinateStack.billboard_basis(target_pos, camera.global_position)
		global_transform = Transform3D(b.scaled(Vector3.ONE * s), target_pos)
	else:
		global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), target_pos)


func toggle_pull() -> void:
	pull_target = 0.0 if pull_target > 0.5 else 1.0
