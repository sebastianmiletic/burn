shader_type spatial;
render_mode cull_back;
// Crisp cube blocks (walls, floors, posts, roofs). Vertex data from ChunkMesher:
//   COLOR.rgb  ambient occlusion (torches/lanterns: their colour)
//   COLOR.a    ASCII material class / 7
//   UV         position on the face (0..1)
//   UV2        (block id, skylight 0..1)
// Textures and the material table are shared with terrain.gdshader (TerrainTextures).

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform float wetness;
global uniform float snow_cover;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 mat_a[128];
uniform vec4 mat_tint[128];
uniform vec4 mat_ore[128];
uniform vec4 mat_emit[128];
uniform float cave_darkness : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying flat float v_block;
varying float v_sky;

void vertex() {
	v_block = UV2.x;
	v_sky = UV2.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int b = int(v_block + 0.5);
	vec3 p = v_world;
	vec3 n = v_wnormal;
	if (b == 29 || b == 40) {
		// Torch and lantern: plain glowing props.
		ALBEDO = COLOR.rgb;
		EMISSION = COLOR.rgb * 4.0;
		ROUGHNESS = ascii_roughness(0.6, ASCII_EMISSIVE);
	} else {
		vec4 a = mat_a[b];
		vec4 tint = mat_tint[b];
		// Planar mapping by face; side textures stay upright.
		vec2 uv;
		vec3 tu;
		vec3 tv;
		if (abs(n.y) > 0.5) { uv = p.xz; tu = vec3(1, 0, 0); tv = vec3(0, 0, -1); }
		else if (abs(n.x) > 0.5) { uv = vec2(p.z * sign(n.x), -p.y); tu = vec3(0, 0, sign(n.x)); tv = vec3(0, 1, 0); }
		else { uv = vec2(-p.x * sign(n.z), -p.y); tu = vec3(-sign(n.z), 0, 0); tv = vec3(0, 1, 0); }
		uv *= a.z;
		vec4 alb = texture(albedo_tex, vec3(uv, a.x));
		vec4 nr = texture(normal_tex, vec3(uv, a.x));
		vec2 tn = nr.xy * 2.0 - 1.0;
		vec3 wn = normalize(n + tu * tn.x + tv * tn.y);
		// Per-block variation so walls don't look printed.
		float var_ = n_hash13(floor(p - n * 0.5)) - 0.5;
		vec3 col = alb.rgb * tint.rgb * (1.0 + var_ * 0.12);
		vec4 em = mat_emit[b];
		vec4 ore = mat_ore[b];
		vec3 emit = vec3(0.0);
		float metal = em.a;
		if (ore.a > 0.0) {
			// Runestone glyph grooves glow.
			float g = smoothstep(0.32, 0.2, nr.a);
			emit = em.rgb * g;
		}
		float up = smoothstep(0.6, 0.9, n.y) * smoothstep(0.6, 0.95, v_sky);
		float snow = clamp(snow_cover * 1.3 - (1.0 - up), 0.0, 1.0);
		col = mix(col, vec3(0.92, 0.94, 0.97), snow);
		float wet = wetness * smoothstep(0.6, 0.95, v_sky) * (0.4 + 0.6 * up);
		col *= 1.0 - wet * 0.35;
		ALBEDO = col;
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		METALLIC = metal;
		EMISSION = emit;
		float rough = clamp(nr.z * a.w, 0.05, 1.0);
		rough = mix(rough, 0.15, wet * 0.6);
		ROUGHNESS = ascii_roughness(rough, int(tint.a + 0.5));
		SPECULAR = 0.4;
	}
	// Skylight only dims ambient light, so torches still light caves fully.
	AO = COLOR.a > -1.0 ? (b == 29 || b == 40 ? 1.0 : COLOR.r) * mix(1.0, v_sky, cave_darkness) : 1.0;
	AO_LIGHT_AFFECT = 0.0;
}
