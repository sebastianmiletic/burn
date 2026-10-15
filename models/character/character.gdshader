shader_type spatial;
render_mode cull_back;
// One shared material for every humanoid. Instance uniforms use fixed slots
// (1..12) so they never collide with glow.gdshader's `intensity` (slot 15) on
// the glowing eye / crown surfaces of the same instance.
// Geometry carries a palette slot and
// a material type per vertex (see CharGeo); each character instance sets its
// own palette through instance uniforms, so all characters - and all their
// garments - draw with a single material and a single draw call per body.
//
// Material types: 0 skin, 1 cloth, 2 leather, 3 metal, 4 hair, 5 bone, 6 eye,
// 7 dark cavity, 8 chainmail, 9 lips, 10 horn, 11 wool/fur, 12 ivory, 13 decayed skin.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

instance uniform vec3 c_skin : instance_index(1) = vec3(0.78, 0.6, 0.48);
instance uniform vec3 c_hair : instance_index(2) = vec3(0.15, 0.1, 0.07);
instance uniform vec3 c_cloth : instance_index(3) = vec3(0.3, 0.25, 0.2);
instance uniform vec3 c_cloth2 : instance_index(4) = vec3(0.5, 0.25, 0.12);
instance uniform vec3 c_trousers : instance_index(5) = vec3(0.2, 0.17, 0.14);
instance uniform vec3 c_leather : instance_index(6) = vec3(0.2, 0.13, 0.08);
instance uniform vec3 c_metal : instance_index(7) = vec3(0.5, 0.5, 0.52);
instance uniform vec3 c_cloak : instance_index(8) = vec3(0.2, 0.17, 0.15);
instance uniform float hit_flash : instance_index(9) = 0.0;
instance uniform vec3 flash_color : instance_index(10) = vec3(1.0, 1.0, 1.0);
instance uniform float burn : instance_index(11) = 0.0;
instance uniform float dissolve : instance_index(12) = 0.0;

global uniform float wetness;

varying vec3 v_rest;
varying float v_param;
varying vec3 v_world;
varying flat int v_slot;
varying flat int v_type;
varying float v_shade;
varying float v_ao;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_param = CUSTOM0.w;
	v_slot = int(round(COLOR.r * 255.0));
	v_type = int(round(COLOR.g * 255.0));
	v_shade = COLOR.b * 2.0;
	v_ao = COLOR.a;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 palette(int slot) {
	if (slot == 0) return c_skin;
	if (slot == 1) return c_hair;
	if (slot == 2) return c_cloth;
	if (slot == 3) return c_cloth2;
	if (slot == 4) return c_trousers;
	if (slot == 5) return c_leather;
	if (slot == 6) return c_metal;
	if (slot == 7) return c_cloak;
	return vec3(0.5);
}

vec3 fixed_color(int t) {
	if (t == 5) return vec3(0.80, 0.76, 0.66);   // bone
	if (t == 6) return vec3(0.86, 0.84, 0.8);    // eye white
	if (t == 7) return vec3(0.015, 0.012, 0.01); // cavity
	if (t == 10) return vec3(0.2, 0.17, 0.15);   // horn
	if (t == 12) return vec3(0.88, 0.84, 0.72);  // ivory
	return vec3(0.5);
}

// Mikkelsen-style bump from a scalar height field, in view space.
vec3 bump(vec3 n, vec3 p, float h, float strength) {
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	float dhx = dFdx(h) * strength;
	float dhy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

void fragment() {
	int t = v_type;
	vec3 base = (v_slot >= 8) ? fixed_color(t) : palette(v_slot);
	vec3 col = base * v_shade;
	float rough = 0.8;
	float metal = 0.0;
	float spec = 0.4;
	int ascii_id = ASCII_SOLID;
	float h = 0.0;
	float bump_k = 0.0;
	vec3 p = v_rest;
	// Fade fine detail with distance so it never shimmers.
	float fw = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.004, 0.02, fw);

	// Cloak hems tear (param > 0 carries the distance down the cloth).
	if (v_param > 0.0) {
		float tear = n_fbm3(vec3(p.x * 9.0, p.y * 2.0, p.z * 9.0));
		if (v_param > 0.5 + tear * 0.55) {
			discard;
		}
		col *= 1.0 - smoothstep(0.55, 1.0, v_param) * 0.35;
	}

	if (t == 0 || t == 9 || t == 13) {
		// Skin: subtle blotches, redder lips/cheeks, slight translucency.
		float n = n_fbm3(p * 38.0);
		float pores = n_value3(p * 420.0);
		col *= 0.9 + 0.2 * n;
		if (t == 9) col = mix(col, col * vec3(1.1, 0.68, 0.66), 0.75);
		if (t == 13) {
			float d = n_fbm3(p * 14.0);
			col = mix(col, col * vec3(0.55, 0.62, 0.42), smoothstep(0.45, 0.7, d));
			col *= 0.85 + 0.3 * n_value3(p * 90.0);
			rough = 0.75;
		} else {
			rough = 0.52 + 0.12 * pores;
		}
		h = n * 0.5 + pores * 0.15 * fine;
		bump_k = 0.6;
		spec = 0.35;
		BACKLIGHT = col * vec3(0.3, 0.12, 0.08) * 0.25;
	} else if (t == 1 || t == 11) {
		// Woven cloth: mottled dye, fine weave, soft sheen; wool is fuzzier.
		float n = n_fbm3(p * 9.0);
		float weave = (sin(p.x * 900.0 + p.z * 900.0) * sin(p.y * 900.0)) * fine;
		col *= 0.82 + 0.3 * n + weave * 0.04;
		h = n * 0.6 + weave * 0.08;
		bump_k = t == 11 ? 1.4 : 0.9;
		rough = 0.95;
		spec = 0.2;
		ascii_id = ASCII_CLOTH;
		float sheen = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		col += base * sheen * 0.25;
	} else if (t == 2) {
		// Leather: creases and worn, lighter high points.
		float n = n_fbm3(p * 22.0);
		float crease = n_fbm3(vec3(p.x * 60.0, p.y * 14.0, p.z * 60.0));
		col *= 0.75 + 0.45 * n;
		col *= 0.85 + 0.25 * smoothstep(0.3, 0.7, crease);
		h = crease;
		bump_k = 0.8;
		rough = 0.48 + 0.25 * n;
		spec = 0.45;
	} else if (t == 3 || t == 8) {
		// Metal: brushed, scratched, darker in recesses. Mail gets rings.
		float n = n_fbm3(p * 16.0);
		float scratch = n_value3(vec3(p.x * 300.0, p.y * 12.0, p.z * 300.0));
		metal = 0.85;
		rough = 0.28 + 0.25 * n + scratch * 0.08;
		col *= 0.8 + 0.35 * n;
		h = n * 0.3;
		bump_k = 0.4;
		if (t == 8) {
			vec2 q = vec2(p.x + p.z, p.y) * 110.0;
			vec2 f = fract(q + vec2(0.5 * floor(q.y), 0.0)) - 0.5;
			float ring = smoothstep(0.18, 0.28, length(f)) * (1.0 - smoothstep(0.38, 0.48, length(f)));
			ring = mix(0.6, ring, fine);
			col *= 0.45 + 0.75 * ring;
			h += ring * 0.6 * fine;
			rough = 0.45;
			bump_k = 1.0;
		}
		spec = 0.5;
	} else if (t == 4) {
		// Hair: fine strands running down the head.
		float strands = n_value3(vec3(p.x * 260.0, p.y * 18.0, p.z * 260.0));
		float n = n_fbm3(p * 20.0);
		col *= 0.65 + 0.55 * strands * (0.7 + 0.3 * n);
		h = strands;
		bump_k = 0.7;
		rough = 0.55;
		spec = 0.45;
		ascii_id = ASCII_CLOTH;
	} else if (t == 5 || t == 12 || t == 10) {
		// Bone / ivory / horn: porous, stained, darker in the joints.
		float n = n_fbm3(p * 30.0);
		float pores = n_value3(p * 260.0);
		col *= 0.78 + 0.32 * n;
		col = mix(col, col * vec3(0.72, 0.62, 0.48), smoothstep(0.55, 0.8, n_fbm3(p * 7.0)));
		if (t == 10) {
			float ridge = sin(p.y * 220.0 + n * 6.0) * 0.5 + 0.5;
			col *= 0.8 + 0.3 * ridge;
			h = ridge;
		} else {
			h = n * 0.6 + pores * 0.25 * fine;
		}
		bump_k = 0.8;
		rough = 0.7;
		spec = 0.35;
	} else if (t == 6) {
		// Eye: white, iris (UV.y = angle from the front pole), pupil, wet.
		float a = UV.y;
		vec3 iris = mix(vec3(0.22, 0.13, 0.07), vec3(0.3, 0.38, 0.45), step(0.5, n_hash13(floor(p * 3.0))));
		col = mix(iris * (0.7 + 0.5 * n_value3(p * 900.0)), col, smoothstep(0.2, 0.26, a));
		col = mix(vec3(0.01), col, smoothstep(0.08, 0.11, a));
		rough = 0.08;
		spec = 0.7;
	} else if (t == 7) {
		rough = 1.0;
		spec = 0.05;
	}

	// Wet weather darkens fabric and skin a little and makes everything glossier.
	float wet = clamp(wetness, 0.0, 1.0);
	col *= 1.0 - wet * (t == 1 || t == 11 ? 0.3 : 0.12);
	rough = mix(rough, rough * 0.55, wet);

	col *= mix(0.45, 1.0, v_ao);
	if (bump_k > 0.0) {
		NORMAL = bump(NORMAL, VERTEX, h, bump_k * 0.0025);
	}

	vec3 emit = vec3(0.0);
	if (dissolve > 0.0) {
		float d = n_fbm3(v_world * 1.7);
		if (d < dissolve) {
			discard;
		}
		float edge = 1.0 - smoothstep(dissolve, dissolve + 0.07, d);
		emit += vec3(1.0, 0.42, 0.1) * edge * 6.0;
		col *= 1.0 - edge * 0.8;
	}
	if (burn > 0.0) {
		float f = n_fbm3(v_world * 3.0 + vec3(0.0, -TIME * 1.6, 0.0));
		emit += vec3(1.0, 0.36, 0.07) * burn * pow(f, 3.0) * 7.0;
		col *= 1.0 - burn * 0.4;
	}
	// Soft rim and a touch of self-illumination keep characters readable as
	// glyphs against bright ground (they would otherwise become blank holes).
	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	emit += col * (0.09 + r * 0.22);

	ALBEDO = mix(col, flash_color, hit_flash);
	METALLIC = metal;
	SPECULAR = spec;
	AO = mix(0.5, 1.0, v_ao);
	EMISSION = emit + flash_color * hit_flash * 1.6;
	ROUGHNESS = ascii_roughness(rough, ascii_id);
}
