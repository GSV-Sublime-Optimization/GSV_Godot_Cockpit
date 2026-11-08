shader_type spatial;
// KIT: stage_rings. A ring split into coloured arcs, one arc per stage, arc length = count.
//   segment hue    -> which stage (e.g. PR: draft / review / changes / approved / queued)
//   segment length -> how many items are in that stage (share of the whole)
//   unit ticks     -> one notch per item, so 3 and 4 are distinguishable without a label
//   empty ring     -> total == 0: a faint solid ring  ("none", a real zero)
//   dotted ring    -> has_data == 0: a dotted grey ring ("unknown", never drawn as zero)
// Put it on a PlaneMesh (lies flat in XZ) or a QuadMesh (faces the camera). UV (0.5,0.5) = centre.
// Transparent + additive, no textures, no TIME. Any renderer; fwidth for antialiasing.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

const int MAX_STAGES = 6;

uniform int stage_count = 5;
uniform float counts[MAX_STAGES];
uniform vec4 stage_colors[MAX_STAGES];   // linear rgb
uniform float has_data = 1.0;
uniform float inner_radius = 0.36;   // in UV units, 0.5 = edge of the quad
uniform float outer_radius = 0.48;
uniform float segment_gap = 0.012;   // fraction of a full turn left dark between stages
uniform float unit_tick = 0.0035;    // fraction of a turn notched between single items
uniform float max_ticks = 60.0;      // above this many items, ticks stop (they would be noise)
uniform float strength = 1.0;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d);
	float aa = fwidth(r) * 1.2;
	float band = smoothstep(inner_radius - aa, inner_radius + aa, r) * (1.0 - smoothstep(outer_radius - aa, outer_radius + aa, r));
	// 0 at 12 o'clock, increasing clockwise (when viewed from above, +Y up), 0..1.
	float a = fract(atan(d.x, -d.y) / 6.2831853 + 1.0);
	float a_aa = fwidth(a);

	float total = 0.0;
	for (int i = 0; i < MAX_STAGES; i++) {
		if (i < stage_count) {
			total += max(counts[i], 0.0);
		}
	}

	vec3 col = vec3(0.0);
	if (has_data < 0.5) {
		// Unknown: dotted grey. 48 dots, never a solid ring, never a colour.
		float dots = step(0.5, fract(a * 48.0));
		col = vec3(0.35, 0.38, 0.42) * dots * 0.5;
	} else if (total <= 0.0) {
		// A real zero: thin, faint and continuous.
		float mid = (inner_radius + outer_radius) * 0.5;
		float thin = 1.0 - smoothstep(0.004, 0.004 + aa, abs(r - mid));
		col = vec3(0.30, 0.55, 0.70) * thin * 0.6;
		band = 1.0;
	} else {
		float start = 0.0;
		for (int i = 0; i < MAX_STAGES; i++) {
			if (i >= stage_count) {
				break;
			}
			float n = max(counts[i], 0.0);
			float len = n / total;
			if (len > 0.0 && a >= start && a < start + len) {
				float local = a - start;
				// Gap at the start of each stage arc.
				float g = smoothstep(segment_gap - a_aa, segment_gap + a_aa, local);
				// One notch per item boundary inside the arc.
				float notch = 1.0;
				if (total <= max_ticks && n > 1.0) {
					float k = local / len * n;
					float dk = abs(fract(k - 0.5) - 0.5) * len / n;   // distance (turns) to nearest item boundary
					notch = smoothstep(unit_tick - a_aa, unit_tick + a_aa, dk);
				}
				// Outer lip brighter: the ring reads as a lit edge, not a flat sticker.
				float lip = smoothstep(outer_radius - 0.03, outer_radius, r);
				col = stage_colors[i].rgb * (0.55 + 0.6 * lip) * g * notch;
			}
			start += len;
		}
	}
	ALBEDO = col * band * strength;
	ALPHA = 1.0;
}
