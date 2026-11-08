shader_type spatial;
// HOLOMIND hologram material: light in the air, not a surface.
// Additive, unshaded, two-sided; a fresnel rim, slow scanlines and a faint flicker.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform float strength = 0.6;
uniform float rim_power = 2.2;
uniform float scan_density = 90.0;
uniform float scan_speed = 0.6;
uniform float flicker = 0.04;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	float scan = 0.55 + 0.45 * sin(world_pos.y * scan_density - TIME * scan_speed * 6.2831);
	float fl = 1.0 - flicker + flicker * sin(TIME * 37.0 + world_pos.x * 3.1);
	float a = strength * (0.18 + 0.82 * rim) * scan * fl;
	ALBEDO = tint.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
