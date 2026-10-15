shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
// Wildflowers, ferns, irises, heather, asphodel: small instanced plants whose petal and
// leaf outlines are cut procedurally from the quad UVs (alpha test -> ASCII FOLIAGE).
//   COLOR.r part: 0 stem/leaf, 0.5 flower centre, 1 petal
//   COLOR.g random, COLOR.b shape id / 7, COLOR.a height fraction (bend weight)
//   INSTANCE_CUSTOM.rgb petal colour (or leaf tint for ferns), .a random (thinning)

#include "res://world/flora/shaders/flora_common.gdshaderinc"

uniform vec3 leaf_color : source_color = vec3(0.2, 0.3, 0.08);
uniform vec3 centre_color : source_color = vec3(0.85, 0.65, 0.1);
uniform bool tint_leaves = false;   // ferns: the instance colour tints the fronds
uniform float fade_end = 50.0;
uniform float fade_len = 8.0;
uniform float thin_start = 16.0;
uniform float thin_min = 0.4;
uniform float flex = 0.9;
uniform float translucency = 0.6;

varying vec3 v_tint;
varying vec3 v_nw;
varying float v_shape;

void vertex() {
	v_tint = INSTANCE_CUSTOM.rgb;
	v_shape = COLOR.b * 7.0 + 0.5;
	vec3 root = MODEL_MATRIX[3].xyz;
	float hsh = INSTANCE_CUSTOM.a;
	float d = distance(root, CAMERA_POSITION_WORLD);
	float far_t = smoothstep(thin_start, fade_end, d);
	float grow = 1.0 - smoothstep(fade_end - fade_len, fade_end, d);
	if (hsh > mix(1.0, thin_min, far_t) || grow <= 0.001) {
		VERTEX = vec3(0.0);
		v_nw = vec3(0.0, 1.0, 0.0);
	} else {
		vec3 rel = VERTEX - root;
		rel *= mix(1.0, 1.35, far_t);
		rel.y *= grow;
		vec3 v = root + rel;
		float t = COLOR.a;
		vec2 wd = fl_wind_dir();
		float gust = fl_gust(root.xz, TIME);
		float ph = hsh * 41.0 + COLOR.g * 7.0;
		float nod = sin(TIME * (2.2 + COLOR.g) + ph) * (0.05 + 0.1 * wind_strength) * flex;
		vec2 bend = wd * (wind_strength * (0.1 + 0.8 * gust) * flex + nod * 0.5) + vec2(-wd.y, wd.x) * nod * 0.5;
		if (d < 30.0) {
			bend += fl_push(root) * 0.85;
		}
		VERTEX = fl_bend(v, root, bend, t);
		v_nw = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.45));
	}
}

// Procedural outlines in quad UV space. Returns true when the fragment is inside.
bool shape_inside(int id, vec2 uv) {
	vec2 c = uv - 0.5;
	if (id == 1) {          // petal: rounded, narrower at the base (uv.y = 0)
		float w = 0.5 * pow(sin(PI * clamp(uv.y, 0.0, 1.0)), 0.55) * (0.55 + 0.45 * uv.y);
		return abs(c.x) < w;
	} else if (id == 2) {   // disc / cup petal
		return length(c) < 0.5;
	} else if (id == 3) {   // fern frond: pinnate leaflets along the midrib
		float y = uv.y;
		float env = 0.5 * pow(1.0 - y, 0.6) * smoothstep(0.0, 0.12, y);
		float ax = abs(c.x);
		// Leaflets sweep toward the tip.
		float seg = fract(y * 15.0 - ax * 1.05);
		float lobe = env * (0.3 + 0.7 * sin(seg * PI));
		return ax < 0.025 || ax < lobe;
	} else if (id == 4) {   // sword leaf
		return abs(c.x) < 0.5 * pow(max(1.0 - uv.y, 0.0), 0.45);
	} else if (id == 5) {   // six-pointed star flower
		float a = atan(c.y, c.x);
		float r = length(c);
		return r < 0.5 * (0.45 + 0.55 * pow(abs(cos(a * 3.0)), 1.5));
	} else if (id == 6) {   // bell / hooded flower
		float w = 0.5 * (0.55 + 0.45 * sqrt(clamp(uv.y, 0.0, 1.0)));
		return abs(c.x) < w && uv.y > 0.02 && length(vec2(c.x * 0.8, max(uv.y - 0.75, 0.0) * 2.0)) < 0.5;
	} else if (id == 7) {   // dot cluster (heather buds, seeds)
		vec2 g = fract(uv * 3.0) - 0.5;
		return length(g) < 0.38 && length(c) < 0.5;
	}
	return true;
}

void fragment() {
	int id = int(v_shape);
	if (!shape_inside(id, UV)) {
		discard;
	}
	vec3 col;
	float part = COLOR.r;
	if (part < 0.25) {
		col = tint_leaves ? v_tint : leaf_color;
		col *= 0.75 + 0.5 * COLOR.g;
		col *= mix(0.45, 1.0, smoothstep(0.0, 0.5, COLOR.a));
		if (id == 3) {
			col *= 0.85 + 0.25 * fract(UV.y * 15.0);
		}
	} else if (part < 0.75) {
		col = centre_color * (0.8 + 0.3 * COLOR.g);
	} else {
		col = v_tint * (0.85 + 0.3 * COLOR.g);
		// Petals darken toward their base and show faint veins.
		col *= mix(0.62, 1.0, smoothstep(0.0, 0.45, UV.y));
		col *= 1.0 - 0.08 * sin(UV.x * 40.0);
	}
	col = fl_wet_albedo(col, 0.4);
	col = fl_snow(col, v_nw.y, 0.7);
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_nw, 0.0)).xyz);
	AO = mix(0.4, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.2;
	BACKLIGHT = col * translucency;
	SPECULAR = mix(0.3, 0.55, wetness);
	ROUGHNESS = ascii_roughness(fl_wet_rough(0.55), ASCII_FOLIAGE);
}
