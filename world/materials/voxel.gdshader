shader_type spatial;
render_mode cull_back;
// Opaque voxel terrain. Vertex data from ChunkMesher:
//   COLOR.rgb  block colour * ambient occlusion
//   COLOR.a    ASCII material class / 7
//   UV         position on the face (0..1) for edge shading
//   UV2        (block id, skylight 0..1)

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform float wind_strength = 0.6;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float cave_darkness : hint_range(0.0, 1.0) = 1.0;
uniform float ember_glow = 3.0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying flat float v_block;
varying float v_sky;
varying float v_class;

void vertex() {
	v_block = UV2.x;
	v_sky = UV2.y;
	v_class = COLOR.a * 7.0;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Leaves sway in the wind.
	int b = int(UV2.x + 0.5);
	if (b == 8 || b == 27 || b == 35) {
		float s = sin(TIME * 1.7 + world.x * 0.35 + world.z * 0.27) + sin(TIME * 2.9 + world.z * 0.5) * 0.4;
		world.xz += vec2(s, s * 0.6) * 0.06 * wind_strength;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	}
	v_world = world;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri_noise(vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return n_value2(p.yz * scale) * w.x + n_value2(p.xz * scale) * w.y + n_value2(p.xy * scale) * w.z;
}

void fragment() {
	int b = int(v_block + 0.5);
	vec3 base = COLOR.rgb;
	vec3 p = v_world;
	vec3 n = v_wnormal;

	// Surface grain: two octaves of noise in block space plus a per-block tint.
	float fine = tri_noise(p, n, 7.0);
	float coarse = tri_noise(p, n, 1.3);
	float block_tint = n_hash13(floor(p - n * 0.5) + vec3(float(b)));
	vec3 col = base * (0.78 + fine * 0.22 + coarse * 0.14 + (block_tint - 0.5) * 0.12);

	// Block edges read as seams.
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.07, min(e.x, e.y));
	col *= mix(0.62, 1.0, edge);

	// Grass blocks: green tops, dirt sides with a grassy lip.
	if (b == 3 || b == 34) {
		vec3 dirt = vec3(0.36, 0.25, 0.16) * (0.8 + fine * 0.3);
		if (n.y < 0.5) {
			float lip = smoothstep(0.78, 0.86, fract(p.y - 0.001) + fine * 0.08);
			float ao = clamp(dot(base, vec3(0.333)) / 0.31, 0.3, 1.2);
			col = mix(dirt * ao * mix(0.62, 1.0, edge), col, lip);
		}
	}
	// Ores: speckles of the ore colour on stone.
	if (b >= 13 && b <= 15) {
		float speck = step(0.62, n_value2((p.xz + p.y * 1.7) * 5.0 + vec2(float(b))));
		col = mix(vec3(0.38) * (0.8 + fine * 0.3), col * 1.5, speck);
	}
	// Planks and logs: grain stripes.
	if (b == 9 || b == 7 || b == 26) {
		float stripe = sin((n.y > 0.5 ? p.x : p.y) * 18.0 + fine * 4.0) * 0.5 + 0.5;
		col *= 0.85 + stripe * 0.2;
	}
	// Brick and cobble: mortar lines.
	if (b == 10 || b == 11 || b == 28) {
		vec2 q = (abs(n.y) > 0.5) ? p.xz : (abs(n.x) > 0.5 ? p.zy : p.xy);
		q *= vec2(2.0, 4.0);
		q.x += step(1.0, mod(q.y, 2.0)) * 0.5;
		vec2 f = fract(q);
		float mortar = smoothstep(0.0, 0.08, min(min(f.x, 1.0 - f.x) * 0.5, min(f.y, 1.0 - f.y)));
		col *= mix(0.55, 1.0, mortar);
	}

	float wet = wetness * step(0.5, n.y) * v_sky;
	ALBEDO = col * (1.0 - wet * 0.35);

	// Emissive blocks.
	vec3 emit = vec3(0.0);
	if (b == 16) emit = vec3(1.0, 0.42, 0.12) * ember_glow * (0.6 + fine * 0.8);
	else if (b == 24) emit = vec3(0.9, 0.12, 0.05) * 2.0 * (0.5 + fine);
	else if (b == 36) emit = vec3(0.45, 0.8, 1.0) * 2.2 * (0.6 + fine * 0.6);
	else if (b == 29 || b == 40) emit = vec3(1.0, 0.68, 0.32) * 4.0;
	else if (b == 31) emit = vec3(1.0, 0.45, 0.15) * step(0.8, n_value2(p.xz * 3.0 + p.y * 2.0)) * 2.5;
	else if (b == 20) emit = vec3(1.0, 0.36, 0.06) * (2.5 + sin(TIME * 1.5 + fine * 6.0) * 0.6);
	EMISSION = emit;

	float rough = 0.85;
	if (b == 6 || b == 17) rough = 0.25;
	if (b == 30) rough = 0.35;
	ROUGHNESS = ascii_roughness(mix(rough, 0.2, wet), int(v_class + 0.5));
	SPECULAR = 0.35;
	// Skylight only dims ambient light, so torches still light caves fully.
	AO = mix(1.0, v_sky, cave_darkness);
	AO_LIGHT_AFFECT = 0.0;
}
