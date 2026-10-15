// Shared by the cave decoration and mine prop shaders.
//   INSTANCE_CUSTOM.a: fade distance / 200 m (0 = never fades, e.g. single meshes).
//   fade_scale: per quality multiplier set by CaveDecor.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform float wetness;

uniform float fade_scale = 1.0;

varying float v_fade;
varying vec3 v_wp;
varying vec3 v_wn;
varying vec4 v_custom;
varying vec3 v_local;

float cave_fade(mat4 model, vec4 custom, vec3 cam) {
	float fe = custom.a > 0.0 ? custom.a * 200.0 * fade_scale : 1e6;
	return 1.0 - smoothstep(fe * 0.85, fe, distance(model[3].xyz, cam));
}

// First line of every vertex(): varyings, fade, collapse of fully faded instances.
#define CAVE_VERTEX v_custom = INSTANCE_CUSTOM; v_local = VERTEX; v_fade = cave_fade(MODEL_MATRIX, INSTANCE_CUSTOM, CAMERA_POSITION_WORLD); v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); if (v_fade <= 0.0) { VERTEX = vec3(0.0); }

float cave_dither(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

// True for the dithered-away pixels of a fading instance.
bool cave_faded(vec2 frag) {
	return cave_dither(frag) >= v_fade;
}

// Triplanar albedo.
vec3 cave_triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy).rgb * w.x + texture(tex, p.xz).rgb * w.y + texture(tex, p.xy).rgb * w.z;
}

// Triplanar normal map applied to the world normal n.
vec3 cave_triplanar_normal(sampler2D tex, vec3 p, vec3 n, float strength) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 nx = texture(tex, p.zy).rgb * 2.0 - 1.0;
	vec3 ny = texture(tex, p.xz).rgb * 2.0 - 1.0;
	vec3 nz = texture(tex, p.xy).rgb * 2.0 - 1.0;
	vec3 tn = normalize(vec3(nx.z, nx.y, nx.x) * w.x * vec3(sign(n.x), 1.0, 1.0)
			+ vec3(ny.x, ny.z, ny.y) * w.y * vec3(1.0, sign(n.y), 1.0)
			+ vec3(nz.x, nz.y, nz.z) * w.z * vec3(1.0, 1.0, sign(n.z)));
	return normalize(n + (tn - n * dot(tn, n)) * strength);
}
