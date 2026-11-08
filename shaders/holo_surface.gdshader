shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

// Hologram surface shader (Keath's brief): additive, unshaded, Fresnel rim,
// world-space scanlines. The slice plane is a half-space clip:
// keep dot(world_position, slice_normal) - slice_distance >= 0.
// Layer cards use the no-cut default (0,1,0,-100); the semantic slice cuts
// the VOLUME only (see holo_volume.gdshader + HoloRoom).

uniform vec4 holo_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float fresnel_power = 3.0;
uniform float line_density = 40.0;
uniform float line_speed = 1.0;
uniform float base_alpha = 0.55;
uniform vec4 slice_plane = vec4(0.0, 1.0, 0.0, -100.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(world_pos, slice_plane.xyz) - slice_plane.w < 0.0) {
		discard;
	}
	// NORMAL is view-space; bring it to world space for the Fresnel term.
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel = pow(1.0 - abs(dot(n_world, view_dir)), fresnel_power);
	float lines = 0.5 + 0.5 * sin(world_pos.y * line_density + TIME * line_speed);
	float glow = base_alpha + fresnel * 0.8;
	ALBEDO = holo_color.rgb * glow * (0.6 + 0.4 * lines);
	ALPHA = base_alpha;
}
