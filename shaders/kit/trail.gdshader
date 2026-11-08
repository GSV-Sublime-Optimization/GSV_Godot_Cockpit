shader_type spatial;
// KIT: trail. A ribbon along a mover's RECORDED path (scripts/kit/DataTrail.gd builds the mesh).
//   ribbon position -> where it really was (straight segments between real samples, no splines)
//   brightness      -> how recently (age = now_s - sample time; fades to 0 at max_age_s)
//   age ticks       -> faint cross-lines every tick_every_s of age: a time scale you can read
// Mesh contract: UV.x = sample time in seconds (any epoch, same as now_s), UV.y = 0..1 across.
// now_s is a uniform the script sets when a sample lands (or at a slow tick), so an idle trail
// costs nothing per frame. Additive, unshaded, no textures, no TIME. Any renderer.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 trail_color : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float now_s = 0.0;
uniform float max_age_s = 120.0;
uniform float tick_every_s = 30.0;   // 0 = no ticks
uniform float strength = 1.2;

void fragment() {
	float age = clamp((now_s - UV.x) / max_age_s, 0.0, 1.0);
	float fresh = pow(1.0 - age, 1.6);
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float core = smoothstep(0.0, 0.6, across);
	float c = fresh * core;
	if (tick_every_s > 0.0) {
		float k = (now_s - UV.x) / tick_every_s;
		float d = abs(fract(k - 0.5) - 0.5) / max(fwidth(k), 1e-4);
		float tick = 1.0 - clamp(d / 1.5, 0.0, 1.0);
		c += tick * 1.1 * (0.35 + 0.65 * (1.0 - age));
	}
	ALBEDO = trail_color.rgb * c * strength;
}
