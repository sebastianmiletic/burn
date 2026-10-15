shader_type spatial;
// Organic surface for creatures: scales, fur, chitin, rock, wrinkled hide,
// feathers and membranes, with bump detail from screen-space derivatives (no
// tangents needed), countershading (pale belly), wet sheen that follows the
// world's `wetness`, optional glowing spots / cracks, and the same per-instance
// hit flash, burn and dissolve state as models/creature.gdshader so
// CreatureModel drives both alike.
// Writes its ASCII class through ascii_roughness().

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
uniform vec3 belly : source_color = vec3(0.75, 0.7, 0.6);
uniform float belly_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 accent : source_color = vec3(0.15);
// 0 none, 1 stripes (across the body), 2 spots, 3 dorsal saddle
uniform int accent_mode = 0;
uniform float accent_amount : hint_range(0.0, 1.0) = 0.0;
uniform float accent_scale = 1.0;
// 0 smooth skin, 1 scales, 2 fur, 3 chitin, 4 rock, 5 hide, 6 feathers, 7 membrane
uniform int pattern = 0;
uniform float pattern_scale = 6.0;
// Skinned meshes carry their rest-pose surface coordinates (metres) in UV.
uniform bool use_uv = false;
// Skinned MobRig bodies carry their rest-pose position in CUSTOM0.xyz (w is
// the fur mask, see fur_shell.gdshader): 3D patterns stay glued to moving limbs.
uniform bool use_rest = false;
uniform float bump : hint_range(0.0, 2.0) = 0.6;
// Bump detail fades out by this distance (metres); big creatures keep it further.
uniform float bump_distance = 45.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.35;
uniform int ascii_id = 0;
uniform float rim = 0.3;
uniform float backlight = 0.0;   // thin membranes glow when lit from behind
// 0 none, 1 spots (photophores), 2 cracks (magma, crystal veins)
uniform int glow_mode = 0;
uniform vec3 glow_color : source_color = vec3(0.3, 0.9, 1.0);
uniform float glow_energy = 4.0;
uniform float glow_amount : hint_range(0.0, 1.0) = 0.15;
uniform float glow_pulse = 0.0;
// 0 = glow everywhere; towards 1 the cracks / spots only glow in scattered patches.
uniform float glow_sparsity : hint_range(0.0, 1.0) = 0.0;
// Belly scutes (skinned bodies, use_uv): transverse plates along UV.y on the underside.
uniform float plates : hint_range(0.0, 1.0) = 0.0;
uniform float plate_spacing = 0.5;
uniform vec3 plate_color : source_color = vec3(0.62, 0.5, 0.36);
// Inner fire seen through the seams of the plates / scales between UV.y = x..y
// metres (a dragon's throat and chest); strength per instance (`inner_glow`).
uniform vec2 inner_span = vec2(0.0, 0.0);
uniform vec3 inner_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float inner_energy = 5.0;

global uniform float wetness;

instance uniform float hit_flash = 0.0;
instance uniform vec3 flash_color = vec3(1.0, 1.0, 1.0);
instance uniform float burn = 0.0;
instance uniform float dissolve = 0.0;
instance uniform float inner_glow = 0.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_wnormal;

void vertex() {
	v_local = use_rest ? CUSTOM0.xyz : VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 3D cellular noise: x = F1, y = F2, z = id of the nearest cell.
vec3 voronoi3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 c = i + g;
				vec3 o = vec3(n_hash13(c), n_hash13(c + 17.3), n_hash13(c + 41.9));
				vec3 r = g + o * 0.85 + 0.075 - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
					id = n_hash13(c + 7.7);
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2), id);
}

vec3 cells(vec3 p) {
	if (use_uv) {
		vec3 v = n_voronoi2(p.xy);
		return v;
	}
	return voronoi3(p);
}

// Surface height (0..1) for bump mapping, plus a colour variation term.
vec2 surface(vec3 p, out vec3 cell) {
	cell = vec3(1.0, 1.0, 0.0);
	if (pattern == 1) {
		// Scales: overlapping domes with dark grooves between them.
		vec3 q = p * vec3(1.0, 1.0, 0.75);
		cell = cells(q);
		float edge = clamp((cell.y - cell.x) * 2.6, 0.0, 1.0);
		float dome = 1.0 - cell.x * cell.x * 0.9;
		return vec2(edge * dome, cell.z);
	} else if (pattern == 2) {
		// Fur: fine streaky strands with darker roots.
		// Fur: soft clumps with fine strands running along the body, darker roots.
		float clumps = n_fbm3(p * vec3(0.9, 0.9, 0.35));
		float strands = n_fbm3(p * vec3(2.2, 2.2, 0.5));
		return vec2(clumps * 0.65 + strands * 0.35, clumps);
	} else if (pattern == 3) {
		// Chitin: glossy plates with seams and pits.
		float band = abs(fract(p.z * 0.5) - 0.5) * 2.0;
		float seam = smoothstep(0.0, 0.12, 1.0 - band);
		float pits = smoothstep(0.55, 0.75, n_fbm3(p * 3.0));
		return vec2(seam * (1.0 - pits * 0.4), n_fbm3(p * 0.4));
	} else if (pattern == 4) {
		// Rock: lumpy with cracks.
		cell = cells(p * 0.7);
		float crack = smoothstep(0.0, 0.09, cell.y - cell.x);
		float lumps = n_fbm3(p * 1.3);
		return vec2(lumps * 0.6 + crack * 0.4, cell.z);
	} else if (pattern == 5) {
		// Hide: ridged wrinkles.
		float n = n_fbm3(p * vec3(1.0, 2.2, 1.0));
		float ridge = 1.0 - abs(n * 2.0 - 1.0);
		return vec2(ridge, n_fbm3(p * 0.5));
	} else if (pattern == 6) {
		// Feathers: elongated overlapping cells.
		cell = cells(p * vec3(1.6, 1.6, 0.8));
		float vane = clamp((cell.y - cell.x) * 2.0, 0.0, 1.0) * (1.0 - cell.x * 0.6);
		return vec2(vane, cell.z);
	} else if (pattern == 7) {
		// Membrane: veins.
		float v = 1.0 - abs(n_fbm3(p * vec3(0.8, 2.5, 0.8)) * 2.0 - 1.0);
		return vec2(pow(v, 6.0), 0.5);
	}
	return vec2(n_fbm3(p * 0.8) * 0.5, n_fbm3(p * 0.3));
}

void fragment() {
	vec3 p;
	if (use_uv) {
		p = vec3(UV * pattern_scale, 0.0);
	} else {
		p = v_local * pattern_scale;
	}
	vec3 cell;
	vec2 s = surface(p, cell);
	float h = s.x;

	// Countershading: pale underside, darker back.
	float down = clamp(-v_wnormal.y * 1.4 + 0.15, 0.0, 1.0);
	vec3 col = mix(albedo, belly, down * belly_mix);
	// Per-cell and large-scale variation keeps big surfaces alive.
	col *= 0.82 + 0.36 * s.y;
	if (pattern == 1 || pattern == 6) {
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.5, h));
	} else if (pattern == 2) {
		col *= mix(0.6, 1.08, h);
	} else if (pattern == 4) {
		col *= mix(0.5, 1.0, h);
	}
	// Accent markings.
	if (accent_mode > 0 && accent_amount > 0.0) {
		vec3 q = (use_uv ? vec3(UV, 0.0) : v_local) * accent_scale;
		float m = 0.0;
		if (accent_mode == 1) {
			float w = n_fbm3(q * 1.5) * 0.6;
			m = smoothstep(0.55, 0.75, abs(fract(q.z * 0.5 + w + (use_uv ? q.y * 0.5 : 0.0)) - 0.5) * 2.0);
		} else if (accent_mode == 2) {
			vec3 c = use_uv ? n_voronoi2(q.xy * 2.0) : voronoi3(q * 2.0);
			m = (1.0 - smoothstep(0.18, 0.32, c.x)) * step(0.45, c.z);
		} else {
			m = smoothstep(0.1, 0.6, v_wnormal.y) * smoothstep(0.35, 0.65, n_fbm3(q * 0.8) + 0.25);
		}
		col = mix(col, accent, m * accent_amount);
	}

	// Belly scutes: broad plates with deep seams across the underside.
	float under = 0.0;
	float seam = 0.0;
	if (plates > 0.0 && use_uv) {
		under = (1.0 - smoothstep(-0.55, -0.05, v_wnormal.y)) * plates;
		float band = fract(UV.y / plate_spacing);
		seam = 1.0 - smoothstep(0.0, 0.09, band) * (1.0 - smoothstep(0.86, 1.0, band));
		float plate_h = (1.0 - seam) * (0.75 + 0.25 * sin(band * 3.14159));
		h = mix(h, plate_h, under);
		vec3 pc = plate_color * (0.85 + 0.3 * n_fbm3(vec3(UV * 0.7, 1.0)));
		col = mix(col, pc * mix(1.0, 0.35, seam), under);
	}

	// Bump from the height field (Mikkelsen surface gradient).
	float fade = 1.0 - smoothstep(bump_distance * 0.15, bump_distance, -VERTEX.z);
	float bh = h * bump * 0.035 * fade;
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

	vec3 emit = vec3(0.0);
	if (glow_mode == 1) {
		vec3 c = use_uv ? n_voronoi2(p.xy * 0.35 + 3.1) : voronoi3(p * 0.35 + 3.1);
		float spot = (1.0 - smoothstep(0.08, 0.2, c.x)) * step(1.0 - glow_amount, c.z);
		float pulse = 1.0 - glow_pulse * 0.5 + glow_pulse * 0.5 * sin(TIME * 2.3 + c.z * 30.0);
		emit += glow_color * glow_energy * spot * pulse;
		col = mix(col, glow_color * 0.4, spot * 0.6);
	} else if (glow_mode == 2) {
		vec3 c = use_uv ? n_voronoi2(p.xy * 0.5) : voronoi3(p * 0.5);
		float crack = 1.0 - smoothstep(0.0, 0.06 + glow_amount * 0.1, c.y - c.x);
		if (glow_sparsity > 0.0) {
			float patch = n_fbm3((use_uv ? vec3(UV * 0.35, 0.5) : v_local * 1.3) + vec3(0.0, TIME * 0.03, 0.0));
			crack *= mix(1.0, smoothstep(0.35 + glow_sparsity * 0.25, 0.6 + glow_sparsity * 0.2, patch), glow_sparsity);
		}
		float pulse = 1.0 - glow_pulse * 0.5 + glow_pulse * 0.5 * sin(TIME * 1.7 + v_world.y);
		// inner_glow (per instance) stokes the cracks hotter (Cerberus' rage).
		emit += glow_color * glow_energy * crack * pulse * (1.0 + inner_glow);
		col *= 1.0 - crack * 0.7;
	}

	if (inner_glow > 0.0 && use_uv && inner_span.y > inner_span.x) {
		float span = smoothstep(inner_span.x, inner_span.x + 0.8, UV.y) * (1.0 - smoothstep(inner_span.y - 1.5, inner_span.y, UV.y));
		// Fire shows through the plate seams underneath and between the scales.
		float through = max(seam * under, (1.0 - h) * 0.15 * (1.0 - smoothstep(-0.6, 0.1, v_wnormal.y)));
		float flicker = 0.8 + 0.2 * sin(TIME * 7.0 + UV.y * 2.0) * sin(TIME * 3.1 + UV.x);
		emit += inner_color * inner_energy * inner_glow * span * through * flicker;
	}
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
	}
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (rim > 0.0) {
		emit += albedo * pow(1.0 - ndv, 3.0) * rim;
	}
	if (backlight > 0.0) {
		emit += col * backlight * pow(1.0 - ndv, 1.5) * 0.6;
	}

	float wet_total = clamp(wet + wetness * 0.6, 0.0, 1.0);
	float r = roughness;
	if (pattern == 3) {
		r = mix(r, r * 0.55, h);
	}
	r = mix(r, 0.18, wet_total * 0.8);
	col *= 1.0 - wet_total * 0.25;

	// A little self-illumination keeps creatures readable as glyphs when back-lit.
	emit += col * 0.12;
	ALBEDO = mix(col, flash_color, hit_flash);
	EMISSION = emit + flash_color * hit_flash * 1.6;
	ROUGHNESS = ascii_roughness(r, ascii_id);
	SPECULAR = mix(specular_amount, 0.7, wet_total);
}
