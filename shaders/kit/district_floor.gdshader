shader_type spatial;
// KIT: district_floor. A procedural grid floor that says where things belong.
//   grid           -> scale (cell = 1 world unit; major line every major_every cells)
//   district rects -> ownership / grouping (machine, org, repo family)
//   district tint  -> which district; fill strength = district_activity (0..1, a real measured rate)
//   vignette       -> distance from the centre of attention (things at the edge are dimmer)
// Opaque, unshaded, no textures, no TIME: costs one pass over the floor's pixels, any renderer.
// Grid lines are antialiased with fwidth and fade with distance to avoid moire.
render_mode unshaded, cull_back;

const int MAX_DISTRICTS = 8;

uniform vec4 base_color : source_color = vec4(0.014, 0.030, 0.075, 1.0);
uniform vec4 grid_color : source_color = vec4(0.16, 0.42, 0.70, 1.0);
uniform float cell = 1.0;
uniform float major_every = 5.0;
uniform float grid_strength = 0.35;

uniform int district_count = 0;
// xy = min corner (world x,z), zw = max corner (world x,z)
uniform vec4 district_rect[MAX_DISTRICTS];
// rgb = tint (linear), a unused. Set from script with Color.srgb_to_linear() if you want sRGB input.
uniform vec4 district_tint[MAX_DISTRICTS];
uniform float district_activity[MAX_DISTRICTS];
uniform float border_width = 0.06;

uniform vec2 focus_center = vec2(0.0, 0.0);
uniform float focus_radius = 22.0;
uniform float fade_distance = 45.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float width_px) {
	vec2 w = fwidth(p);
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(w, vec2(1e-4));
	return 1.0 - clamp(min(g.x, g.y) / width_px, 0.0, 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 col = base_color.rgb;

	// Distance from the camera: thin out the grid far away (no shimmer, no false density).
	float cam_d = length(world_pos - CAMERA_POSITION_WORLD);
	float far_fade = 1.0 - smoothstep(fade_distance * 0.5, fade_distance, cam_d);

	float minor = grid_line(p / cell, 1.0);
	float major = grid_line(p / (cell * major_every), 1.4);
	col += grid_color.rgb * grid_strength * (0.35 * minor + 0.9 * major) * far_fade;

	// Districts: soft fill scaled by activity, crisp bright border, corner brackets.
	for (int i = 0; i < MAX_DISTRICTS; i++) {
		if (i >= district_count) {
			break;
		}
		vec4 r = district_rect[i];
		vec2 lo = r.xy;
		vec2 hi = r.zw;
		vec2 c = (lo + hi) * 0.5;
		vec2 h = (hi - lo) * 0.5;
		vec2 q = abs(p - c) - h;
		float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);   // signed distance to the rect
		float aa = fwidth(sd);
		float inside = 1.0 - smoothstep(-aa, aa, sd);
		float border = 1.0 - smoothstep(border_width - aa, border_width + aa, abs(sd));
		// Corner brackets: thicker border near each corner (reads as a designed zone, not a bug).
		vec2 to_corner = h - abs(p - c);
		float corner = step(max(to_corner.x, to_corner.y), 1.2);   // within 1.2 units of a corner on both axes
		float bracket = (1.0 - smoothstep(border_width * 2.5 - aa, border_width * 2.5 + aa, abs(sd))) * corner;
		vec3 tint = district_tint[i].rgb;
		float act = clamp(district_activity[i], 0.0, 1.0);
		col += tint * inside * (0.035 + 0.11 * act);
		// Grid inside a district takes its tint, so membership is readable even far from the border.
		col += tint * inside * major * 0.25 * far_fade;
		col += tint * border * (0.45 + 0.35 * act);
		col += tint * bracket * 0.6;
	}

	// Vignette: distance from attention. Never to black: the edge is dim, not gone.
	float v = smoothstep(focus_radius, focus_radius * 0.35, length(p - focus_center));
	col *= 0.30 + 0.70 * v;

	ALBEDO = col;
}
