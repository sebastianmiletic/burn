shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
// Underwater plants (world/flora/sea_flora.gd): kelp, seagrass, corals, anemones.
// A slow current sways them (more towards the tips); corals barely move.
//   COLOR.r sway weight (0 root .. 1 tip), COLOR.g random, COLOR.b glow mask, COLOR.a occlusion
//   INSTANCE_CUSTOM.rgb colour, .a random

uniform float sway = 0.3;
uniform float speed = 0.8;
uniform float translucency = 0.5;
uniform float glow = 0.0;
uniform int pattern = 0;   // 0 plain, 1 polyps, 2 brain grooves, 3 fan lattice
uniform float fade_end = 70.0;

varying vec3 v_tint;
varying vec3 v_world;
varying float v_rnd;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_tint = INSTANCE_CUSTOM.rgb;
	v_rnd = INSTANCE_CUSTOM.a;
	vec3 root = MODEL_MATRIX[3].xyz;
	float d = distance(root, CAMERA_POSITION_WORLD);
	float grow = 1.0 - smoothstep(fade_end * 0.8, fade_end, d);
	vec3 rel = (VERTEX - root) * grow;
	float w = pow(COLOR.r, 1.4);
	float h = max(rel.y, 0.0);
	float ph = v_rnd * 37.0 + COLOR.g * 5.0 + root.x * 0.11 + root.z * 0.07;
	vec2 current = vec2(sin(TIME * speed + ph), cos(TIME * speed * 0.77 + ph * 1.3)) * sway * w;
	// The surge: a slow common push so whole meadows lean together.
	current += vec2(sin(TIME * 0.31 + root.x * 0.02), cos(TIME * 0.27 + root.z * 0.02)) * sway * 0.6 * w;
	rel.xz += current * (0.4 + h * 0.35);
	rel.y -= dot(current, current) * h * 0.08;
	VERTEX = root + rel;
	v_world = VERTEX;
}

void fragment() {
	vec3 col = v_tint * (0.8 + 0.4 * COLOR.g);
	col *= mix(0.45, 1.0, COLOR.a);
	if (pattern == 1) {
		// Polyps: fine pale dots over the branches.
		float dots = smoothstep(0.62, 0.8, vn(v_world.xz * 38.0 + v_world.y * 31.0));
		col = mix(col, col * 1.5 + 0.08, dots);
	} else if (pattern == 2) {
		// Brain coral: meandering grooves.
		float g = vn(UV * vec2(18.0, 9.0) + v_rnd * 13.0) + 0.5 * vn(UV * vec2(36.0, 18.0));
		float groove = smoothstep(0.08, 0.0, abs(fract(g * 2.2) - 0.5) - 0.32);
		col *= 1.0 - 0.45 * groove;
	} else if (pattern == 3 && COLOR.b > 0.25) {
		// Fan lattice on the panel quads: a fine net, cut out between the threads.
		vec2 q = UV * vec2(22.0, 20.0);
		float net = min(abs(fract(q.x + q.y * 0.35) - 0.5), abs(fract(q.y - q.x * 0.3) - 0.5));
		vec2 c = UV - vec2(0.5, 0.0);
		if (net > 0.12 || length(c * vec2(1.0, 0.95)) > 0.52 || UV.y < 0.05) {
			discard;
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
	BACKLIGHT = col * translucency;
	EMISSION = col * glow * COLOR.b * (0.7 + 0.3 * sin(TIME * 1.7 + v_rnd * 20.0));
}
