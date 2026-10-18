class_name UnderwaterFx
extends CanvasLayer
## Screen effect for the local player's eyes, self-contained (does not touch
## the renderer): under water the view goes green-blue and murky, wobbles
## with refraction and catches a faint caustic shimmer; running out of air
## closes the view in from the edges, blurs and drains it to black. Fades
## out again when the player surfaces or wakes.

var player: Player
var _rect: ColorRect
var _mat := ShaderMaterial.new()
var _under := 0.0
var _t := 0.0

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float underwater = 0.0;
uniform float suffocate = 0.0;
uniform float time_s = 0.0;
uniform vec3 water_col = vec3(0.07, 0.24, 0.27);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c * vec2(1.7, 1.0));
	// Refraction wobble, stronger towards the edges, and a slow drunken sway when out of air.
	uv += underwater * (0.0025 + 0.004 * r) * vec2(sin(uv.y * 34.0 + time_s * 2.0), cos(uv.x * 27.0 + time_s * 1.6));
	uv += suffocate * 0.006 * vec2(sin(time_s * 0.9), cos(time_s * 0.7));
	float blur = underwater * 1.4 + suffocate * suffocate * 4.5 + r * underwater * 0.8;
	vec3 col = textureLod(screen, uv, blur).rgb;
	// Water swallows red first, then everything into a blue-green murk.
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 absorbed = col * vec3(0.45, 0.8, 0.9);
	vec3 murk = water_col * (0.55 + 0.5 * lum);
	vec3 wet = mix(absorbed, murk, 0.42 + 0.25 * r);
	// Caustic shimmer from above.
	float k = sin(uv.x * 48.0 + time_s * 1.3 + sin(uv.y * 31.0 + time_s * 0.8) * 2.0) * sin(uv.y * 41.0 - time_s * 1.1 + sin(uv.x * 23.0) * 1.5);
	wet += water_col * 0.35 * pow(max(k, 0.0), 3.0) * smoothstep(1.0, 0.0, uv.y);
	col = mix(col, wet, underwater);
	// Out of air: grey, then the dark creeps in from the edges to a full blackout.
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))), suffocate * 0.7);
	float edge = mix(1.25, -0.05, suffocate);
	float closing = smoothstep(edge - 0.5, edge, r);
	col *= 1.0 - closing;
	col *= 1.0 - smoothstep(0.75, 1.0, suffocate);
	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	layer = -9  # over the 3D view and WorldView's overlays (-10), under every UI layer
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_t += delta
	var cam_under := false
	if player.camera != null and player.water_surface > -INF:
		cam_under = player.camera.global_position.y < player.water_surface - 0.02
	_under = move_toward(_under, 1.0 if cam_under else 0.0, delta * 6.0)
	var s := player.suffocation
	_rect.visible = _under > 0.001 or s > 0.001
	if _rect.visible:
		_mat.set_shader_parameter(&"underwater", _under)
		_mat.set_shader_parameter(&"suffocate", s)
		_mat.set_shader_parameter(&"time_s", _t)
