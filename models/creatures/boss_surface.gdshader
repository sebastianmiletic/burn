shader_type spatial;
// One shared surface for the bespoke boss models (models/creatures/boss_kit.gd):
// worn plate armour and gilded trim, cloth and robes with tattered hems, stone
// skin, crystal, starlit void, bone, leather, fur and wood. Parts of one boss
// share a few materials; per-part colours ride in the vertex colour (rgb) so
// many parts merge into one mesh, and COLOR.a marks parts that carry runes.
//
// Per-instance state matches models/creature.gdshader (hit flash, burn,
// dissolve) so CreatureModel drives these parts too; `power` brightens runes,
// crystal and void glow when a boss changes phase.
//
// Skinned meshes (cloaks, robes) carry their rest-pose position in UV/UV2 so
// patterns do not swim while the cloth moves.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

// 0 metal, 1 cloth, 2 rock, 3 crystal, 4 void, 5 bone, 6 leather, 7 skin, 8 fur / hair, 9 wood
uniform int mode = 0;
uniform vec3 albedo : source_color = vec3(1.0);
uniform vec3 albedo2 : source_color = vec3(0.2);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float pattern_scale = 4.0;
uniform float wear : hint_range(0.0, 1.0) = 0.3;
uniform float grime : hint_range(0.0, 1.0) = 0.3;
uniform float rust : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rust_color : source_color = vec3(0.32, 0.17, 0.08);
uniform float frost : hint_range(0.0, 1.0) = 0.0;
uniform float rune : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rune_color : source_color = vec3(0.4, 1.0, 0.6);
uniform float rune_energy = 3.0;
uniform float rune_scale = 3.0;
uniform float tatter : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 4.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.6, 0.4, 1.0);
uniform bool skinned = false;
uniform int ascii_id = 0;
uniform float rim = 0.15;
uniform float bump = 1.0;
uniform float bump_distance = 40.0;

global uniform float wetness;

instance uniform float hit_flash = 0.0;
instance uniform vec3 flash_color = vec3(1.0, 1.0, 1.0);
instance uniform float burn = 0.0;
instance uniform float dissolve = 0.0;
instance uniform float power = 0.0;

varying vec3 v_rest;
varying float v_param;
varying vec3 v_world;
varying vec3 v_wn;
varying vec4 v_col;

void vertex() {
	if (skinned) {
		v_rest = vec3(UV.x, UV.y, UV2.x);
		v_param = UV2.y;
	} else {
		v_rest = VERTEX;
		v_param = UV2.y;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

// Engraved rune strokes on a grid: 0..1 line intensity.
float runes(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = n_hash12(cell);
	float h2 = n_hash12(cell + 13.7);
	float w = 0.07;
	float d = 1.0;
	// A vertical stave in most glyphs, plus two of four branches.
	if (h > 0.2) d = min(d, abs(f.x));
	if (h2 > 0.5) d = min(d, abs(f.x - f.y * 0.8) + max(0.0, abs(f.y) - 0.42));
	if (h2 < 0.6) d = min(d, abs(f.x + f.y * 0.8) + max(0.0, abs(f.y) - 0.42));
	if (fract(h * 7.3) > 0.6) d = min(d, abs(f.y - 0.18) + max(0.0, abs(f.x) - 0.26));
	if (fract(h * 3.1) > 0.7) d = min(d, length(f - vec2(0.0, -0.2)) - 0.12);
	// Keep the vertical extent of a glyph.
	d = max(d, abs(f.y) - 0.42);
	float line = 1.0 - smoothstep(w * 0.5, w, d);
	// Glyphs sit in rows with gaps between words.
	float word = step(0.25, n_hash12(vec2(floor(cell.x / 3.0), cell.y) + 3.3));
	return line * word;
}

void fragment() {
	vec3 p = v_rest * pattern_scale;
	vec3 tint = v_col.rgb;
	float rune_mask = v_col.a < 0.99 ? 1.0 - v_col.a : 0.0;
	vec3 col = albedo * tint;
	float rough = roughness;
	float metal = metallic;
	float spec = 0.5;
	float h = 0.0;          // height for bump
	vec3 emit = vec3(0.0);
	float n1 = n_fbm3(p * 0.6);
	float up = clamp(v_wn.y, -1.0, 1.0);

	if (mode == 0) {
		// Plate metal: brushed streaks, hammer dents, worn bright patches,
		// grime in the low parts, rust blooms.
		float streak = n_value3(p * vec3(6.0, 0.6, 6.0));
		float dents = n_value3(p * 2.2);
		float worn = smoothstep(0.62, 0.8, n1 + dents * 0.25) * wear;
		col *= 0.78 + 0.3 * streak;
		col = mix(col, col * 1.45 + 0.04, worn);
		rough = clamp(rough + (streak - 0.5) * 0.18 - worn * 0.2, 0.08, 1.0);
		float g = smoothstep(0.35, 0.75, n_fbm3(p * 0.35 + 7.0)) * grime;
		col *= 1.0 - g * 0.55;
		rough = mix(rough, 0.85, g * 0.6);
		float r = smoothstep(0.45, 0.7, n1 * 0.75 + n_value3(p * 1.4 + 3.0) * 0.45) * rust;
		col = mix(col, rust_color * (0.7 + 0.5 * dents), r);
		metal = mix(metal, 0.1, r);
		rough = mix(rough, 0.92, r);
		h = dents * 0.5 + streak * 0.15 - r * 0.3;
	} else if (mode == 1) {
		// Woven cloth: fine weave, folds of colour, dirt rising from the hem.
		vec2 uvw = (skinned ? v_rest.xy : v_rest.xz + v_rest.yy) * pattern_scale * 3.0;
		float weave = sin(uvw.x * 6.283) * sin(uvw.y * 6.283);
		col *= 0.82 + 0.28 * n1 + 0.05 * weave;
		col = mix(col, albedo2 * tint, smoothstep(0.55, 0.8, n_fbm3(p * 0.25 + 11.0)) * 0.35);
		float dirt = clamp(1.0 - (v_rest.y + 0.2) * 1.5, 0.0, 1.0) * grime;
		col = mix(col, col * vec3(0.55, 0.5, 0.42), dirt);
		rough = 0.92;
		spec = 0.25;
		h = weave * 0.08 + n1 * 0.5;
		if (tatter > 0.0) {
			// Holes and a ragged hem; v_param carries the distance down the cloth.
			float holes = n_fbm3(p * 0.9 + 5.0);
			float edge = v_param;
			if (edge > 1.0 - tatter * (0.35 + holes * 0.7)) {
				discard;
			}
			if (holes > 0.78 - tatter * 0.06 && edge > 0.35) {
				discard;
			}
			col *= 1.0 - smoothstep(0.6, 1.0, edge) * 0.35;
		}
	} else if (mode == 2) {
		// Stone skin: lumpy, cracked, lichen-dark in the cavities.
		vec3 vc = n_voronoi2(p.xz * 0.7 + p.yy * 0.35);
		float crack = 1.0 - smoothstep(0.0, 0.07, vc.y - vc.x);
		col *= 0.62 + 0.55 * n1;
		col = mix(col, albedo2 * tint, smoothstep(0.5, 0.8, n_fbm3(p * 0.3 + 2.0)) * 0.6);
		col *= 1.0 - crack * 0.6;
		rough = 0.9;
		spec = 0.3;
		h = n1 * 0.8 - crack * 0.6;
		emit += rune_color * rune_energy * crack * rune * (0.04 + power * 1.8) * smoothstep(0.45, 0.75, n_value3(p * 0.35 + TIME * 0.1));
	} else if (mode == 3) {
		// Crystal: glassy facets with a light inside.
		float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float fres = pow(1.0 - ndv, 2.5);
		float inner = n_fbm3(p * 0.8 + vec3(0.0, TIME * 0.15, 0.0));
		col = mix(col * 0.35, albedo2 * tint, fres);
		rough = 0.06;
		metal = 0.0;
		spec = 0.9;
		emit += glow_color * (glow + power * 1.5) * (0.25 + fres * 1.6 + smoothstep(0.55, 0.8, inner) * 1.2);
	} else if (mode == 4) {
		// Void: a hole in the world full of stars and slow nebulae.
		float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		vec3 sp = v_world * 0.9 + vec3(TIME * 0.05, 0.0, TIME * 0.03);
		vec3 cell = floor(sp * 3.0);
		float star = step(0.965, n_hash13(cell)) * (1.0 - smoothstep(0.05, 0.16, length(fract(sp * 3.0) - 0.5)));
		float neb = n_fbm3(v_world * 0.25 + vec3(0.0, TIME * 0.04, 0.0));
		col = albedo * 0.08;
		rough = 0.4;
		spec = 0.2;
		emit += vec3(0.9, 0.92, 1.0) * star * 6.0;
		emit += mix(glow_color, albedo2, neb) * smoothstep(0.45, 0.8, neb) * (glow + power) * 1.2;
		emit += glow_color * pow(1.0 - ndv, 3.0) * (1.5 + power * 2.0);
	} else if (mode == 5) {
		// Bone: ivory with hairline cracks and grime.
		col *= 0.8 + 0.3 * n1;
		float cr = 1.0 - smoothstep(0.0, 0.04, abs(n_value3(p * 3.0) - 0.5));
		col *= 1.0 - cr * 0.35 - grime * smoothstep(0.5, 0.8, n_fbm3(p * 0.5 + 4.0)) * 0.4;
		rough = 0.65;
		h = n1 * 0.4 - cr * 0.3;
	} else if (mode == 6) {
		// Leather: creased hide.
		float n = n_fbm3(p * vec3(1.0, 2.0, 1.0));
		float ridge = 1.0 - abs(n * 2.0 - 1.0);
		col *= 0.75 + 0.35 * ridge;
		rough = 0.7 - ridge * 0.15;
		spec = 0.35;
		h = ridge;
	} else if (mode == 7) {
		// Skin: mottled, slightly translucent at grazing angles.
		col *= 0.88 + 0.2 * n1;
		col = mix(col, albedo2 * tint, smoothstep(0.55, 0.8, n_fbm3(p * 0.5 + 9.0)) * 0.4);
		rough = 0.6;
		spec = 0.4;
		h = n1 * 0.3;
		emit += col * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0) * 0.25;
	} else if (mode == 8) {
		// Fur / hair: strands running down the part.
		float strands = n_value3(p * vec3(9.0, 0.7, 9.0));
		float clumps = n_value3(p * vec3(2.0, 0.35, 2.0));
		col *= 0.55 + 0.6 * strands * (0.6 + 0.4 * clumps);
		col = mix(col, albedo2 * tint, smoothstep(0.6, 0.9, clumps) * 0.5);
		rough = 0.85;
		spec = 0.2;
		h = strands * 0.8;
	} else if (mode == 9) {
		// Wood: grain along the part, knots.
		float grain = n_value3(p * vec3(8.0, 0.4, 8.0));
		float rings = fract(grain * 6.0);
		col *= 0.7 + 0.35 * rings * 0.5 + 0.2 * n1;
		col = mix(col, albedo2 * tint, smoothstep(0.65, 0.85, n_fbm3(p * 0.6 + 1.0)) * 0.6);
		rough = 0.85;
		spec = 0.25;
		h = rings * 0.4 + n1 * 0.4;
	}

	// Glowing engraved runes (parts whose vertex alpha marks them).
	if (rune > 0.0 && rune_mask > 0.0 && mode != 2) {
		vec2 rp = (skinned ? v_rest.xy : vec2(v_rest.x + v_rest.z, v_rest.y)) * rune_scale;
		float r = runes(rp) * rune_mask;
		float pulse = 0.75 + 0.25 * sin(TIME * 1.7 + v_world.y * 0.6);
		col = mix(col, col * 0.4, r);
		emit += rune_color * rune_energy * r * rune * pulse * (0.6 + power * 1.5);
		h -= r * 0.4;
	}

	// Frost and snow settle on the upper faces.
	if (frost > 0.0) {
		float f = smoothstep(0.35, 0.75, up + (n1 - 0.5) * 0.8 - (1.0 - frost) * 1.2);
		col = mix(col, vec3(0.82, 0.88, 0.95), f);
		rough = mix(rough, 0.55, f);
		metal = mix(metal, 0.0, f);
		emit += vec3(0.7, 0.85, 1.0) * f * step(0.985, n_hash13(floor(v_world * 40.0))) * 1.5;
	}

	// Bump from the height field (surface gradient, no tangents needed).
	float fade = 1.0 - smoothstep(bump_distance * 0.15, bump_distance, -VERTEX.z);
	float bh = h * bump * 0.03 * fade;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(bh);
	float dhy = dFdy(bh);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-9) {
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
	}

	if (dissolve > 0.0) {
		float d = n_fbm3(v_world * 1.7);
		if (d < dissolve) {
			discard;
		}
		float edge = 1.0 - smoothstep(dissolve, dissolve + 0.07, d);
		emit += (mode == 4 || mode == 3 ? glow_color : vec3(1.0, 0.42, 0.1)) * edge * 6.0;
		col *= 1.0 - edge * 0.8;
	}
	if (burn > 0.0) {
		float f = n_fbm3(v_world * 3.0 + vec3(0.0, -TIME * 1.6, 0.0));
		emit += vec3(1.0, 0.36, 0.07) * burn * pow(f, 3.0) * 7.0;
	}
	float ndv2 = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	emit += col * pow(1.0 - ndv2, 3.0) * rim;

	float wet_total = clamp(wetness * 0.5, 0.0, 1.0);
	rough = mix(rough, rough * 0.5, wet_total);
	// A little self-illumination keeps dark bosses readable as glyphs when back-lit.
	emit += col * 0.08;
	ALBEDO = mix(col, flash_color, hit_flash);
	METALLIC = metal * (1.0 - hit_flash);
	EMISSION = emit + flash_color * hit_flash * 1.6;
	ROUGHNESS = ascii_roughness(rough, ascii_id);
	SPECULAR = spec;
}
