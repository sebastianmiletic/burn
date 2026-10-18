shader_type canvas_item;
// Colour-vision filter over the whole screen (Settings > Accessibility).
// Daltonisation: simulate how the image looks with the chosen deficiency
// (LMS cone space, Viénot/Brettel style matrices), take what is lost and
// shift that error into channels the viewer can still tell apart.
// mode: 1 protanopia, 2 deuteranopia, 3 tritanopia.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int mode = 0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

const mat3 RGB2LMS = mat3(
	vec3(17.8824, 3.45565, 0.0299566),
	vec3(43.5161, 27.1554, 0.184309),
	vec3(4.11935, 3.86714, 1.46709));
const mat3 LMS2RGB = mat3(
	vec3(0.0809444479, -0.0102485335, -0.000365296938),
	vec3(-0.130504409, 0.0540193266, -0.00412161469),
	vec3(0.116721066, -0.113614708, 0.693511405));

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 lms = RGB2LMS * c;
	vec3 sim = lms;
	if (mode == 1) {
		sim.x = 2.02344 * lms.y - 2.52581 * lms.z;
	} else if (mode == 2) {
		sim.y = 0.494207 * lms.x + 1.24827 * lms.z;
	} else if (mode == 3) {
		sim.z = -0.395913 * lms.x + 0.801109 * lms.y;
	}
	vec3 seen = LMS2RGB * sim;
	vec3 err = c - seen;
	// Red-green losses move into green/blue; blue-yellow losses into red/green.
	vec3 fix = mode == 3 ? vec3(err.r + 0.7 * err.b, err.g + 0.7 * err.b, 0.0)
		: vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
	COLOR = vec4(clamp(c + fix * strength, 0.0, 1.0), 1.0);
}
