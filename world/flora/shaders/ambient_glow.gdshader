shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;
// Ambient light specks drawn after the ASCII pass (they glow over the glyphs):
//   mode 0  pollen / dust motes drifting with the wind in a field that wraps around the camera
//           (INSTANCE_CUSTOM.xyz = random 0..1 home in the field, w = phase)
//   mode 1  fireflies wandering around homes placed on the ground by AmbientLife
//           (instance origin = home, INSTANCE_CUSTOM.w = phase)

global uniform vec2 wind_dir;
global uniform float wind_strength;

uniform int mode = 0;
uniform vec3 field = vec3(26.0, 9.0, 26.0);
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.7);
uniform float intensity = 1.0;
uniform float size = 0.03;

varying float v_alpha;

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	float ph = cu.w;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 centre;
	float a = 1.0;
	if (mode == 0) {
		vec2 wd = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(1.0, 0.0);
		vec3 drift = vec3(wd.x, 0.0, wd.y) * TIME * (0.25 + wind_strength * 1.6)
				+ vec3(sin(TIME * 0.31 + ph * 6.28), sin(TIME * 0.23 + ph * 4.1) * 0.6 + TIME * 0.02, cos(TIME * 0.27 + ph * 5.3)) * 0.7;
		vec3 p = cu.xyz * field + drift;
		vec3 rel = mod(p - cam + field * 0.5, field) - field * 0.5;
		rel.y -= field.y * 0.15;
		centre = cam + rel;
		// Fade at the wrap edges and right in front of the lens.
		vec3 e = abs(rel) / (field * 0.5);
		a = (1.0 - smoothstep(0.7, 1.0, max(e.x, max(e.y, e.z)))) * smoothstep(0.4, 1.5, length(rel));
		a *= 0.55 + 0.45 * sin(TIME * (1.3 + ph * 2.0) + ph * 30.0);
	} else {
		vec3 home = MODEL_MATRIX[3].xyz;
		vec3 wander = vec3(sin(TIME * 0.37 + ph * 6.28) + 0.5 * sin(TIME * 0.91 + ph * 3.0),
				0.6 * sin(TIME * 0.53 + ph * 9.0),
				cos(TIME * 0.29 + ph * 5.0) + 0.5 * cos(TIME * 0.77 + ph * 7.0)) * 1.4;
		centre = home + wander + vec3(0.0, 0.9, 0.0);
		// Slow glow pulses with dark gaps.
		float blink = sin(TIME * (0.9 + ph * 0.5) + ph * 40.0);
		a = smoothstep(0.1, 0.9, blink);
		a *= smoothstep(1.0, 3.0, distance(centre, cam));
	}
	v_alpha = a * intensity;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float s = size * (mode == 1 ? 1.0 : (0.6 + ph));
	vec3 world = centre + (right * (UV.x - 0.5) + up * (UV.y - 0.5)) * s * 2.0;
	if (v_alpha <= 0.002) {
		world = cam - vec3(0.0, 1000.0, 0.0);
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = exp(-r * r * 6.0);
	float halo = exp(-r * r * 1.8) * 0.35;
	ALBEDO = tint * (core + halo) * v_alpha;
}
