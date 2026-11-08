shader_type spatial;
// KIT: heat_field. Activity density from up to MAX_POINTS weighted points, with contour lines.
//   brightness/colour -> density (sum of Gaussian kernels), on a FIXED scale (full_scale)
//   contours          -> iso-lines at quarters of full_scale (read levels, not just "glow")
// Point layout: points[i] = vec4(world x, world z, weight, radius). point_count <= MAX_POINTS.
// full_scale is set by the caller and kept fixed: auto-normalising to the current max would make
// a quiet day look as hot as a busy one (theatre). The ramp's luminance rises monotonically
// (teal -> cyan -> amber -> pale), so it still reads in greyscale and for colour-blind eyes.
// Cost: MAX_POINTS kernel evaluations per covered pixel; keep the plane only as big as the area.
// Additive, unshaded, no textures, no TIME. Any renderer.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

const int MAX_POINTS = 16;

uniform int point_count = 0;
uniform vec4 points[MAX_POINTS];
uniform float full_scale = 3.0;
uniform float strength = 0.9;
uniform float contour_levels = 4.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 ramp(float t) {
	vec3 c0 = vec3(0.02, 0.16, 0.22);
	vec3 c1 = vec3(0.05, 0.45, 0.62);
	vec3 c2 = vec3(0.95, 0.55, 0.10);
	vec3 c3 = vec3(1.00, 0.92, 0.75);
	if (t < 0.33) {
		return mix(c0, c1, t / 0.33);
	} else if (t < 0.66) {
		return mix(c1, c2, (t - 0.33) / 0.33);
	}
	return mix(c2, c3, (t - 0.66) / 0.34);
}

void fragment() {
	vec2 p = world_pos.xz;
	float dens = 0.0;
	for (int i = 0; i < MAX_POINTS; i++) {
		if (i >= point_count) {
			break;
		}
		vec4 q = points[i];
		vec2 d = p - q.xy;
		dens += q.z * exp(-dot(d, d) / max(q.w * q.w, 1e-4));
	}
	float t = clamp(dens / full_scale, 0.0, 1.0);
	// Below 4% of full scale: nothing. Noise floor is not activity.
	float vis = smoothstep(0.04, 0.12, t);
	vec3 col = ramp(t) * vis * (0.35 + 0.65 * t);
	// Contours at 1/levels steps of the fixed scale.
	float k = t * contour_levels;
	float dk = abs(fract(k - 0.5) - 0.5) / max(fwidth(k), 1e-4);
	float line = (1.0 - clamp(dk, 0.0, 1.0)) * step(0.5, k);
	col += ramp(min(t + 0.15, 1.0)) * line * 0.7;
	ALBEDO = col * strength;
}
