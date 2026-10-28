class_name OceanMood
extends RefCounted
## The look of the sea around the local camera (revision 5). Drives the global
## shader parameter `dark_ocean_amount` (0..1, project.godot [shader_globals]):
## out on the Dark Ocean the water turns near-black and the underwater murk
## closes in (voxel_liquid.gdshader, UnderwaterFx, WorldView's DepthEffects).
## Eased over a few seconds so crossing the edge is a slow dimming, not a cut.
## LocationTracker calls update() every frame.

const PARAM := &"dark_ocean_amount"
## Seconds to fade fully in or out.
const FADE_SECONDS := 6.0

## Current eased amount (read by the underwater effects).
static var dark := 0.0
## The WorldGen.Sea kind under the camera (Sea.NONE on land / other dimensions).
static var kind := 0
static var _target := 0.0
static var _sample_t := 0.0
static var _sent := -1.0


## Ease towards the Dark Ocean amount at `pos` (sampled 4x a second) and publish it.
static func update(gen: Variant, pos: Vector3, dimension: int, delta: float) -> void:
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = 0.25
		_target = 0.0
		kind = 0
		if dimension == 0 and gen is WorldGen:
			var g := gen as WorldGen
			kind = g.ocean_kind_at(pos.x, pos.z)
			_target = g.dark_ocean_amount(pos.x, pos.z)
	dark = move_toward(dark, _target, delta / FADE_SECONDS)
	_publish()


## Jump straight to a value (world load, teleports, tests).
static func reset(value := 0.0) -> void:
	dark = clampf(value, 0.0, 1.0)
	_target = dark
	_sample_t = 0.0
	_publish()


static func _publish() -> void:
	if absf(dark - _sent) < 0.002:
		return
	_sent = dark
	RenderingServer.global_shader_parameter_set(PARAM, dark)
