class_name HoloCoordinateStack
extends RefCounted

## Pure coordinate-stack math for the holographic cockpit (Keath's brief,
## 2026-11-07 ~23:46 MST). Four spaces, every interaction a conversion:
##   world  — the companion body, the table, the origin; information sits at p_world
##   view   — p_view = R^-1 * (p_world - t) from the camera's rigid transform
##   clip   — p_clip = P * p_view (f = 1/tan(fov_y/2), aspect, near n, far f)
##   screen — Camera3D.unproject_position is the forward projection; the inverse
##            is the ray (project_ray_origin / project_ray_normal).
##
## No scene-tree state lives here: every function is static and pure, so the
## whole stack is unit-testable without a running scene (see
## tests/holo_coordinate_stack_test.gd). The live scene (HoloRoom) calls these
## with its real Camera3D; the tests call them with a throwaway camera.

const DEFAULT_FOV_Y_DEGREES := 55.0
## Separation epsilon for "equal" view-space depths in the stable sort.
const DEPTH_EPSILON := 0.001


## f = 1 / tan(fov_y / 2).
static func perspective_f(fov_y_degrees: float) -> float:
	return 1.0 / tan(deg_to_rad(fov_y_degrees) * 0.5)


## p_view = R^-1 * (p_world - t). The view-space z of a layer is the
## depth-layering quantity: closer means less negative z.
static func view_space_point(camera: Camera3D, world_point: Vector3) -> Vector3:
	return camera.global_transform.affine_inverse() * world_point


## p_clip = P * p_view with the standard perspective matrix. Aspect is an
## explicit argument so the math stays pure (no viewport lookup).
static func clip_space_point(camera: Camera3D, world_point: Vector3, aspect: float) -> Vector4:
	var view: Vector3 = view_space_point(camera, world_point)
	var f: float = perspective_f(camera.fov)
	var n: float = camera.near
	var fa: float = camera.far
	var x: float = f / aspect * view.x
	var y: float = f * view.y
	var z: float = (fa + n) / (n - fa) * view.z + (2.0 * fa * n) / (n - fa)
	var w: float = -view.z
	return Vector4(x, y, z, w)


## Forward projection: world point -> screen point.
static func screen_point(camera: Camera3D, world_point: Vector3) -> Vector2:
	return camera.unproject_position(world_point)


## Inverse projection: screen point -> ray (origin + direction).
static func ray_from_screen(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	return {
		"origin": camera.project_ray_origin(screen_pos),
		"direction": camera.project_ray_normal(screen_pos),
	}


## Ray-plane hit test for one holographic layer. A layer is a plane
## n-hat . p = d with n-hat = camera forward (negative camera global basis Z)
## and d = n-hat . layer_position. The hit is converted to the layer's local
## coordinates (affine_inverse) and tested against the layer's bounding rect
## (half extents in local X/Y — the quad faces local +Z).
##
## Returns {"hit": bool, "local": Vector2, "world": Vector3}. "local" and
## "world" are present even on a rect miss (useful for hover-near feedback);
## both are absent when the ray is parallel to the plane or the plane is
## behind the ray origin (Plane.intersects_ray returns null).
static func hit_layer(camera: Camera3D, screen_pos: Vector2, layer: Node3D, half_extents: Vector2) -> Dictionary:
	var ray: Dictionary = ray_from_screen(camera, screen_pos)
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	var normal: Vector3 = -camera.global_transform.basis.z.normalized()
	var plane_d: float = normal.dot(layer.global_position)
	var plane := Plane(normal, plane_d)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return {"hit": false}
	var hit_point: Vector3 = hit
	var local: Vector3 = layer.global_transform.affine_inverse() * hit_point
	if absf(local.x) > half_extents.x or absf(local.y) > half_extents.y:
		return {"hit": false, "local": Vector2(local.x, local.y), "world": hit_point}
	return {"hit": true, "local": Vector2(local.x, local.y), "world": hit_point}


## "Bringing a layer closer" is a continuous lambda in [0, 1] interpolating
## the plane distance d_i(lambda) = d_i_base + lambda * delta_d ...
static func pull_distance(base_d: float, pull: float, delta_d: float) -> float:
	return base_d + clampf(pull, 0.0, 1.0) * delta_d


## ... and the scale s_i(lambda) = s_i_base * (1 + lambda * kappa) together.
## You change the plane's d and its scale, not individual objects.
static func pull_scale(base_s: float, pull: float, kappa: float) -> float:
	return base_s * (1.0 + clampf(pull, 0.0, 1.0) * kappa)


## Depth-layering quantity for one world position: its view-space z.
static func depth_key(camera: Camera3D, world_pos: Vector3) -> float:
	return view_space_point(camera, world_pos).z


## Stable sort on (z_i, render_priority_i, epsilon_i): closer (less negative
## z) first; render_priority breaks near-equal depths; insertion index breaks
## the rest. Entries are Dictionaries {"node": Node3D, "render_priority": int,
## "index": int}. Returns a new Array; the input is untouched.
static func sort_layers_by_depth(camera: Camera3D, layers: Array) -> Array:
	var sorted: Array = layers.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var za: float = depth_key(camera, (a["node"] as Node3D).global_position)
		var zb: float = depth_key(camera, (b["node"] as Node3D).global_position)
		if absf(za - zb) > DEPTH_EPSILON:
			return za > zb
		var pa: int = int(a.get("render_priority", 0))
		var pb: int = int(b.get("render_priority", 0))
		if pa != pb:
			return pa < pb
		return int(a.get("index", 0)) < int(b.get("index", 0))
	)
	return sorted


## Parallax: offset_i = k * (z_i - z_ref) * (p_cam - p_ref). The human's head
## movement becomes a query, revealing dependencies hidden behind the layer.
static func parallax_offset(k: float, z: float, z_ref: float, cam_pos: Vector3, ref_pos: Vector3) -> Vector3:
	return k * (z - z_ref) * (cam_pos - ref_pos)


## The companion's gaze: g-hat = normalize(p_cam - p_holo).
static func gaze_direction(cam_pos: Vector3, holo_pos: Vector3) -> Vector3:
	return (cam_pos - holo_pos).normalized()


## Billboarding: rotate a flat card so its normal aligns with g-hat (minimal
## rotation between the card's default normal and g-hat). QuadMesh faces local
## +Z, so use_model_front = true (+Z toward the camera). Returns IDENTITY when
## the camera sits on the layer (no direction to face).
static func billboard_basis(layer_pos: Vector3, cam_pos: Vector3, up: Vector3 = Vector3.UP) -> Basis:
	var to_cam: Vector3 = cam_pos - layer_pos
	if to_cam.length() < 0.001:
		return Basis.IDENTITY
	return Basis.looking_at(to_cam, up, true)
