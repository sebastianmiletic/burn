shader_type spatial;
// PBR surface for items, tools, armour and crafting stations.
// One shader, several procedural "finishes" so every material reads as what
// it is up close (icons) and still writes its ASCII class for the world pass.
//
// finish: 0 plain, 1 forged metal, 2 wood, 3 stone, 4 gem / glass, 5 leather,
//         6 ore rock (accent flecks), 7 cloth, 8 bark, 9 bone / ivory
// emission_mode: 0 none, 1 uniform, 2 molten veins, 3 inner fresnel glow, 4 shimmer

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.6);
uniform vec3 accent : source_color = vec3(0.2);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform int ascii_id = 0;
uniform int finish = 0;
uniform float detail_scale = 1.0;
uniform float bump_amount = 1.0;
uniform float wear = 0.3;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform int emission_mode = 0;
uniform float rim = 0.0;
uniform float self_lit = 0.06;
uniform vec3 grain_dir = vec3(0.0, 1.0, 0.0);
uniform float sparkle_amount = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 p = v_local * detail_scale;
	vec3 col = albedo;
	float rough = roughness;
	float metal = metallic;
	float spec = specular_amount;
	float h = 0.0;          // height for bump mapping (metres-ish, scaled below)
	vec3 emit = vec3(0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);

	if (finish == 1) {
		// Forged metal: brushed along the item's length, hammer dents, fine scratches, darker grime in hollows.
		float brushed = n_value3(p * vec3(90.0, 3.0, 90.0));
		float dents = n_fbm3(p * 16.0);
		float scratch = smoothstep(0.9, 1.0, n_value3(p * vec3(380.0, 9.0, 60.0)));
		float grime = smoothstep(0.42, 0.2, n_fbm3(p * 5.0 + 3.0)) * wear;
		col *= 0.88 + brushed * 0.14 + (dents - 0.5) * 0.14;
		col = mix(col, col * 0.45 + accent * 0.25, grime);
		rough = clamp(rough + (brushed - 0.5) * 0.12 + scratch * 0.18 + grime * 0.35, 0.04, 1.0);
		h = dents * 0.7 - scratch * 0.1;
	} else if (finish == 2) {
		// Wood: growth rings around the length (Y), long streaky grain, knots.
		vec3 g = normalize(grain_dir);
		float along = dot(p, g);
		vec3 across = p - g * along;
		vec3 q = across + g * along * 0.12;
		float warp = n_fbm3(q * 2.5) * 7.0;
		float rings = sin(length(across) * 140.0 + warp) * 0.5 + 0.5;
		float grain = n_value3(across * 90.0 + g * along * 3.0);
		float knot = smoothstep(0.8, 0.93, n_fbm3(q * 6.0 + 11.0));
		col *= 0.66 + rings * 0.22 + grain * 0.22;
		col = mix(col, accent, knot * 0.55);
		rough = clamp(rough + (grain - 0.5) * 0.1, 0.2, 1.0);
		h = rings * 0.35 + grain * 0.5 - knot * 0.4;
	} else if (finish == 3 || finish == 6) {
		// Stone: mottled fbm, mineral speckle, hairline cracks.
		float n = n_fbm3(p * 9.0);
		float speck = n_value3(p * 70.0);
		float crack = (1.0 - smoothstep(0.0, 0.012, abs(n_fbm3(p * 7.0 + 7.0) - 0.5))) * 0.6;
		col *= 0.7 + n * 0.45 + (speck - 0.5) * 0.18;
		col = mix(col, accent, smoothstep(0.62, 0.8, n_fbm3(p * 3.0 + 1.3)) * 0.35);
		col *= 1.0 - crack * 0.35;
		h = n * 0.8 + speck * 0.25 - crack * 0.5;
		if (finish == 6) {
			// Ore rock: glinting metallic flecks of the ore colour.
			float fl = smoothstep(0.66, 0.74, n_value3(p * 26.0 + 5.0)) * smoothstep(0.35, 0.6, n);
			col = mix(col, accent, fl);
			metal = mix(metal, 0.85, fl);
			rough = mix(rough, 0.3, fl);
			h += fl * 0.6;
		}
	} else if (finish == 4) {
		// Gem / glass: deep colour, bright facet edges, inner sparkle.
		vec3 refl = reflect(-VIEW, NORMAL);
		float sparkle = pow(n_value3(refl * 6.0 + p * 4.0), 6.0);
		col = albedo * (0.25 + 0.5 * (1.0 - fres));
		emit += albedo * (fres * 0.9 + sparkle * 2.5 * sparkle_amount) + vec3(sparkle * 0.6 * sparkle_amount);
		rough = roughness;
		spec = 0.9;
	} else if (finish == 5) {
		// Leather: pores and creases.
		float pores = n_value3(p * 160.0);
		float crease = n_fbm3(p * vec3(20.0, 60.0, 20.0));
		col *= 0.78 + pores * 0.12 + crease * 0.2;
		rough = clamp(rough + pores * 0.1, 0.3, 1.0);
		h = pores * 0.3 + crease * 0.6;
	} else if (finish == 7) {
		// Cloth / cord: woven threads.
		float wx = sin(p.x * 900.0 + sin(p.y * 900.0) * 1.5);
		float wy = sin(p.y * 900.0 + sin(p.z * 900.0) * 1.5);
		float weave = 0.5 + 0.25 * (wx + wy);
		col *= 0.78 + weave * 0.3;
		h = weave * 0.4;
	} else if (finish == 8) {
		// Bark: deep vertical furrows.
		float furrow = n_fbm3(p * vec3(30.0, 5.0, 30.0));
		float plates = smoothstep(0.35, 0.65, furrow);
		col *= 0.45 + plates * 0.65;
		col = mix(col, accent, smoothstep(0.7, 0.9, n_fbm3(p * 9.0)) * 0.4);
		h = plates * 1.6;
	} else if (finish == 9) {
		// Bone / ivory: smooth with porous patches and faint growth lines.
		float pore = n_value3(p * 120.0);
		float lines = sin(p.y * 260.0 + n_fbm3(p * 8.0) * 4.0) * 0.5 + 0.5;
		col *= 0.88 + pore * 0.08 + lines * 0.06;
		col = mix(col, accent, smoothstep(0.6, 0.85, n_fbm3(p * 6.0)) * 0.35);
		h = pore * 0.2 + lines * 0.15;
	} else {
		float n = n_fbm3(p * 8.0);
		col *= 0.9 + (n - 0.5) * 0.2;
		h = n * 0.3;
	}

	// Bump mapping from the procedural height (Mikkelsen surface gradient).
	if (bump_amount > 0.0) {
		float hs = h * 0.0012 * bump_amount;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhx = dFdx(hs);
		float dhy = dFdy(hs);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		if (abs(det) > 1e-12) {
			vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
			NORMAL = normalize(abs(det) * NORMAL - grad);
		}
	}

	if (emission_mode == 1) {
		emit += emission_color * emission_energy;
	} else if (emission_mode == 2) {
		// Molten veins crawling slowly through the material.
		float v = abs(n_fbm3(p * 5.0 + vec3(0.0, TIME * 0.12, 0.0)) - 0.5);
		float vein = 1.0 - smoothstep(0.0, 0.07, v);
		float pulse = 0.8 + 0.2 * sin(TIME * 2.3 + p.y * 9.0);
		emit += emission_color * emission_energy * vein * pulse;
		col *= 1.0 - vein * 0.85;
		rough = mix(rough, 0.9, vein);
	} else if (emission_mode == 3) {
		emit += emission_color * emission_energy * (0.25 + fres);
	} else if (emission_mode == 4) {
		float sh = 0.5 + 0.5 * sin(TIME * 1.4 + p.y * 14.0 + n_fbm3(p * 6.0) * 6.0);
		emit += emission_color * emission_energy * (0.15 + fres) * sh;
	}
	emit += albedo * rim * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	emit += col * self_lit * (1.0 - metal * 0.5);

	ALBEDO = col;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	ROUGHNESS = ascii_roughness(rough, ascii_id);
}
