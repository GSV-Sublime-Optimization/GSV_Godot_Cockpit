shader_type spatial;
// KIT: data_emissive. One material that carries four facts at once, and nothing else.
//   status_color -> hue          (what state is it in: ok / warn / alert / unknown)
//   urgency      -> emission     (how much it needs attention now; capped, so it can never blind)
//   staleness    -> desaturation (how old the fact is: grey and dim means "do not trust this colour")
//   selected     -> fresnel rim  (the thing you are looking at; a UI fact, never a data fact)
//   event_pulse  -> brief flash  (set by script ONLY when a real event lands; decays to 0; never from TIME)
//   hatch        -> diagonal stripes (redundant channel for alert so colour-blind eyes see it too)
//   unit_height  -> one band per unit of height (count PRs by eye on an extruded bar)
// Renderer: works in Compatibility (GL) and Forward+. Unshaded with a fixed key light done in the
// shader, so it costs the same in both and needs no scene lights. No textures, no TIME.
render_mode unshaded, cull_back;

uniform vec4 status_color : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float urgency : hint_range(0.0, 1.0) = 0.3;
uniform float staleness : hint_range(0.0, 1.0) = 0.0;
uniform float selected : hint_range(0.0, 1.0) = 0.0;
uniform float event_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float hatch : hint_range(0.0, 1.0) = 0.0;
// Glow budget: brightness at urgency 0 and at urgency 1. Nothing (not even a pulse) exceeds white.
uniform float emission_floor = 0.35;
uniform float emission_cap = 1.5;
// Box-edge highlight: pass the mesh half-extents (local units). (0,0,0) turns edges off (spheres etc).
uniform vec3 half_size = vec3(0.0);
uniform float edge_width = 0.035;
uniform float selected_edge_boost = 2.0;   // selected boxes draw edges this much wider
// Unit bands: 0 = off. local_base_y is the local Y of the bar's floor (BoxMesh is centred, so -h/2).
uniform float unit_height = 0.0;
uniform float local_base_y = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec3 hue = status_color.rgb;
	// Staleness: drain colour toward grey, then dim. A stale red must not read as a fresh red.
	hue = mix(hue, vec3(luma(hue)), staleness * 0.85);
	float alive = 1.0 - 0.55 * staleness;

	// Fixed key light in view space: gives form without any scene light (cheap in GL).
	vec3 key = normalize(vec3(0.35, 0.8, 0.5));
	float ndl = clamp(dot(NORMAL, key), 0.0, 1.0);
	float shade = 0.55 + 0.45 * ndl;

	// Emission: urgency maps LINEARLY into [emission_floor, emission_cap] brightness. Above 1.0 the
	// colour "overdrives": it cannot get brighter on an 8-bit target, so it whitens a little (a hot
	// core) and crosses the environment's glow threshold, so only urgent things bloom.
	// A real event adds a brief extra level on top; the total is still capped below.
	float level = mix(emission_floor, emission_cap, urgency) + event_pulse * 0.9;
	level = min(level, emission_cap + 0.6);

	vec3 col = hue * shade * level * alive;

	// Hatch: diagonal stripes in object space; 28% darker stripes keep the hue legible.
	if (hatch > 0.0) {
		float s = step(0.5, fract((local_pos.x + local_pos.y + local_pos.z) * 4.0));
		col *= 1.0 - 0.28 * hatch * s;
	}

	// Unit bands: a thin dark line every unit_height, antialiased with fwidth.
	if (unit_height > 0.0) {
		float u = (local_pos.y - local_base_y) / unit_height;
		float d = abs(fract(u - 0.5) - 0.5) / max(fwidth(u), 1e-4);
		float band = 1.0 - clamp(d, 0.0, 1.0);
		col *= 1.0 - 0.45 * band;
	}

	// Edges: where two axes are at their extent, draw a bright wire (reads as a hologram frame).
	if (half_size.x > 0.0) {
		vec3 e = step(half_size - vec3(edge_width * mix(1.0, selected_edge_boost, selected)), abs(local_pos));
		float edge = step(1.5, e.x + e.y + e.z);
		vec3 edge_col = hue * min(0.5 + 0.6 * level, 1.0) * alive + vec3(0.06);
		// Selected: edges go white-hot, so selection never borrows a status hue.
		edge_col = mix(edge_col, vec3(1.6, 1.7, 1.8), selected);
		col = mix(col, edge_col, edge * 0.85);
	}

	// Hue-preserving clamp: scale the whole colour down so its brightest channel is 1.0, then add
	// the overdrive equally to every channel (at most +0.36). Plain per-channel clipping would turn a
	// bright amber yellow and a bright red pink: the hue would lie. Adding white keeps the hue family,
	// reads as "hot", and pushes the pixel past the glow threshold so urgent things bloom.
	float m = max(max(col.r, col.g), col.b);
	col /= max(m, 1.0);
	col += vec3(clamp(m - 1.0, 0.0, 0.6) * 0.6);   // overdrive: equal parts on every channel

	// Selection rim: fresnel, only when selected. White-tinted so it never changes the status hue.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += vec3(0.85, 0.95, 1.0) * rim * selected * 1.4;

	ALBEDO = col;
}
