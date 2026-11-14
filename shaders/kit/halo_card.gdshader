shader_type spatial;
// KIT: halo_card. A camera-facing additive glow card: bloom you control per object.
//   intensity -> urgency above a threshold (the script decides the threshold, e.g. urgency > 0.5)
//   colour    -> the status hue (the halo never invents a colour)
// Why: in the Compatibility (GL) renderer the 3D target is low dynamic range, so environment glow
// with a threshold barely separates "urgent" from "bright". A halo card is guaranteed, costs one
// small quad of overdraw, and its strength is exactly the number you give it. Any renderer.
// Use on a QuadMesh. No textures, no TIME.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled;

uniform vec4 halo_color : source_color = vec4(1.0, 0.3, 0.25, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.0;
uniform float falloff = 2.2;

void vertex() {
	// Billboard: keep the quad facing the camera, keep its scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float g = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	ALBEDO = halo_color.rgb * g * intensity;
}
