shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Night storm sea for the loading cinematic: Gerstner swell in the vertex
// stage (world-space, so the mesh can follow the camera), wind ripples and
// foam in the fragment, and a cheap fake sky reflection lit by lightning.

uniform vec3 deep_color : source_color = vec3(0.008, 0.02, 0.028);
uniform vec3 body_color : source_color = vec3(0.03, 0.065, 0.075);
uniform vec3 foam_color : source_color = vec3(0.55, 0.6, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.11, 0.13, 0.15);
uniform vec3 zenith_color : source_color = vec3(0.012, 0.016, 0.022);
uniform float flash = 0.0;
uniform vec3 flash_dir = vec3(0.0, 0.5, -1.0);
uniform float swell = 1.0;

varying float v_crest;
varying vec3 v_world;

vec3 gerstner(vec2 p, vec2 dir, float steep, float len, float t, inout vec3 tangent, inout vec3 binormal) {
	float k = 6.28318 / len;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep / k;
	tangent += vec3(-d.x * d.x * steep * sin(f), d.x * steep * cos(f), -d.x * d.y * steep * sin(f));
	binormal += vec3(-d.x * d.y * steep * sin(f), d.y * steep * cos(f), -d.y * d.y * steep * sin(f));
	return vec3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 d = vec3(0.0);
	float t = TIME;
	d += gerstner(w.xz, vec2(1.0, 0.35), 0.16 * swell, 62.0, t, tangent, binormal);
	d += gerstner(w.xz, vec2(0.8, -0.6), 0.14 * swell, 37.0, t, tangent, binormal);
	d += gerstner(w.xz, vec2(-0.3, 1.0), 0.12 * swell, 21.0, t, tangent, binormal);
	d += gerstner(w.xz, vec2(0.95, 0.1), 0.1 * swell, 11.0, t, tangent, binormal);
	d += gerstner(w.xz, vec2(0.2, 0.9), 0.08 * swell, 6.5, t, tangent, binormal);
	VERTEX += d;
	v_crest = d.y;
	v_world = w + d;
	NORMAL = normalize(cross(binormal, tangent));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Wind ripples: two scrolling noise gradients bend the normal.
	vec2 p = v_world.xz;
	float t = TIME;
	float e = 0.35;
	vec2 q1 = p * 0.55 + vec2(t * 0.9, t * 0.3);
	vec2 q2 = p * 1.3 - vec2(t * 0.4, t * 1.1);
	float n0 = noise(q1) + noise(q2) * 0.5;
	float nx = noise(q1 + vec2(e, 0.0)) + noise(q2 + vec2(e, 0.0)) * 0.5;
	float nz = noise(q1 + vec2(0.0, e)) + noise(q2 + vec2(0.0, e)) * 0.5;
	n_world = normalize(n_world + vec3(n0 - nx, 0.0, n0 - nz) * 0.4);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(n_world, view_w), 0.0, 1.0), 5.0) * 0.9 + 0.03;
	vec3 r = reflect(-view_w, n_world);
	vec3 sky = mix(horizon_color, zenith_color, clamp(r.y * 2.5, 0.0, 1.0));
	sky += vec3(0.55, 0.62, 0.8) * flash * (0.35 + 1.6 * pow(max(dot(normalize(r), normalize(flash_dir)), 0.0), 6.0));

	float crest = smoothstep(0.6, 2.2, v_crest);
	float foam = crest * smoothstep(0.45, 0.8, noise(p * 0.8 + vec2(t * 0.6, 0.0)) * 0.7 + noise(p * 2.6) * 0.5);
	vec3 water = mix(deep_color, body_color, smoothstep(-1.5, 2.0, v_crest));
	ALBEDO = mix(water, foam_color, foam * 0.75);
	ROUGHNESS = mix(0.24, 0.6, foam);
	SPECULAR = 0.35;
	METALLIC = 0.0;
	// Reflection is faked (the scene has no reflection probe / radiance).
	EMISSION = sky * fres * (1.0 - foam) + foam_color * foam * flash * 0.4;
}
