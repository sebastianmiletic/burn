shader_type sky;
// Night storm sky for the loading cinematic: low churning clouds, a moon
// smothered behind them, and lightning that lights the cloud deck from inside.

uniform vec3 zenith : source_color = vec3(0.012, 0.015, 0.022);
uniform vec3 horizon : source_color = vec3(0.1, 0.115, 0.135);
uniform vec3 cloud_lit : source_color = vec3(0.22, 0.25, 0.3);
uniform vec3 moon_dir = vec3(0.4, 0.35, -0.85);
uniform float flash = 0.0;
uniform vec3 flash_dir = vec3(0.0, 0.4, -1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -0.2, 1.0);
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.55, h));
	// Cloud deck projected onto a plane overhead.
	vec2 uv = d.xz / (max(d.y, 0.0) + 0.12);
	float t = TIME * 0.025;
	float c = fbm(uv * 0.9 + vec2(t, t * 0.4));
	float c2 = fbm(uv * 2.2 - vec2(t * 1.6, 0.0));
	float cloud = smoothstep(0.35, 0.8, c * 0.75 + c2 * 0.35);
	// Moon glow bleeding through thinner cloud.
	float m = max(dot(d, normalize(moon_dir)), 0.0);
	vec3 moon = vec3(0.5, 0.56, 0.68) * (pow(m, 300.0) * 1.2 * (1.0 - cloud) + pow(m, 12.0) * 0.12);
	vec3 base = mix(col, cloud_lit * (0.25 + c2 * 0.4), cloud * smoothstep(-0.05, 0.12, d.y));
	// Lightning lights the cloud undersides around the strike.
	float fl = flash * (0.2 + 1.8 * pow(max(dot(d, normalize(flash_dir)), 0.0), 5.0));
	base += vec3(0.6, 0.66, 0.85) * fl * (0.25 + cloud * 1.3) * smoothstep(-0.1, 0.1, d.y);
	COLOR = base + moon;
}
