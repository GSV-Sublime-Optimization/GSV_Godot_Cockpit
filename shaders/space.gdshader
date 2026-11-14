shader_type sky;
// HOLOMIND's outer space: a still, deep starfield in three depths over faint nebula clouds. A backdrop, not data.
// Everything is computed from the view direction, so it costs one pass and no textures.

uniform vec3 deep = vec3(0.004, 0.006, 0.018);
uniform vec3 nebula_a = vec3(0.10, 0.05, 0.22);
uniform vec3 nebula_b = vec3(0.02, 0.12, 0.20);
uniform float star_density = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float threshold) {
	vec3 cell = floor(dir * scale);
	float h = hash(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 centre = (cell + vec3(hash(cell + 1.3), hash(cell + 2.7), hash(cell + 4.1))) / scale;
	float d = length(dir - normalize(centre)) * scale;
	float twinkle = 0.75 + 0.25 * fract(h * 7.0);   // fixed brightness per star: the sky does not pretend to be alive
	return smoothstep(0.42, 0.0, d) * (h - threshold) / (1.0 - threshold) * twinkle;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float n = fbm(d * 2.2);
	float m = fbm(d * 4.1 - vec3(1.7, 0.3, 0.0));
	vec3 col = deep;
	col += nebula_a * smoothstep(0.45, 0.85, n) * 0.9;
	col += nebula_b * smoothstep(0.5, 0.9, m) * 0.7;
	// A faint galactic band across the sky.
	col += vec3(0.06, 0.07, 0.11) * exp(-pow(d.y * 3.2 + 0.4 * sin(d.x * 2.0), 2.0)) * (0.5 + 0.5 * n);
	float s = stars(d, 160.0 * star_density, 0.975) * 1.8 + stars(d, 380.0 * star_density, 0.988) * 1.0 + stars(d, 800.0 * star_density, 0.995) * 0.6;
	col += vec3(0.85, 0.9, 1.0) * s;
	COLOR = col;
}
