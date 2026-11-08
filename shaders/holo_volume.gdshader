shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

// Volumetric raymarcher (Keath's brief): a scalar density field rho(p)
// rendered by fixed-step accumulation:
//   C = sum rho(p_i) * T_i * c(p_i) * delta,  T_{i+1} = T_i * exp(-rho * delta)
// max_steps is the compiled bound (64); step_size is the uniform trade-off
// (0.02). The slice plane is a half-space clip applied per sample: samples
// outside the kept half-space contribute zero density, so the slice cuts the
// volume along a DATA axis (time / sense / age — see HoloRoom).
//
// Marching happens in OBJECT space: VERTEX is the front-surface entry point
// in the box's local coords, and the world ray direction is reused in local
// space. That is exact only because the volume mesh is NEVER rotated —
// translation + uniform scale only (enforced by construction in HoloRoom).
// box_scale is the uniform scale (MODEL_MATRIX column length).

const int MAX_STEPS = 64;

uniform sampler3D density_tex;
uniform float step_size = 0.02;
uniform float box_scale = 2.6;
uniform vec3 volume_color : source_color = vec3(0.3, 0.8, 1.0);
uniform vec4 slice_plane = vec4(0.0, 1.0, 0.0, -100.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ro_local = VERTEX;
	vec3 rd_world = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 rd_local = rd_world / box_scale;
	vec3 acc = vec3(0.0);
	float transmittance = 1.0;
	for (int i = 0; i < MAX_STEPS; i++) {
		float t = float(i) * step_size;
		vec3 p_local = ro_local + rd_local * t;
		vec3 uvw = p_local + vec3(0.5);
		if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) {
			break;
		}
		vec3 p_world = world_pos + rd_world * t;
		float inside = step(0.0, dot(p_world, slice_plane.xyz) - slice_plane.w);
		float rho = texture(density_tex, uvw).r * inside;
		float a = 1.0 - exp(-rho * step_size);
		acc += transmittance * a * volume_color;
		transmittance *= (1.0 - a);
		if (transmittance < 0.01) {
			break;
		}
	}
	ALBEDO = acc;
	ALPHA = 1.0;
}
