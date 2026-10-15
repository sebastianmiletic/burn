class_name ElementalModel
extends CreatureModel
## Fire elemental of the Cinder Wastes and the underworld: a white-hot core
## wrapped in a cage of molten rock shards that orbit and breathe, two
## "arms" of shards that wind up and hurl fire, and a column of flame and
## embers instead of legs. Lights its surroundings. Faces -Z.

var size := 2.2

var core: Node3D
var shards: Array = []   # [node, orbit radius, height, speed, phase]
var arms: Array = []     # [pivot, side]
var _core_glow: MeshInstance3D
var _flames: GPUParticles3D
var _light: OmniLight3D


func _init(variant_seed := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	size = rng.randf_range(2.0, 2.5)
	dissolve_delay = 0.6
	dissolve_time = 1.0


func _ember_extents() -> Vector3:
	return Vector3(0.4, 0.8, 0.4) * size * 0.5


func _lod_size() -> float:
	return size


func _build() -> void:
	var s := size / 2.2
	var rock := CreatureSkin.rock(Color(0.16, 0.1, 0.08), {"glow_mode": 2, "glow_color": Color(1.0, 0.45, 0.1), "glow_amount": 0.45, "glow_energy": 6.0, "glow_pulse": 0.8, "pattern_scale": 3.0})
	core = ModelKit.joint(self, "Core", Vector3(0, 1.4 * s, 0))
	_core_glow = ModelKit.part(core, ModelKit.sphere(0.32 * s, 14), ModelKit.glow(Color(1.0, 0.7, 0.35), 4.0, 0.6))
	ModelKit.part(core, ModelKit.sphere(0.5 * s, 14), MaterialLibrary.fx(Color(1.0, 0.6, 0.25), Color(1.0, 0.25, 0.05), 1.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 14:
		var r := rng.randf_range(0.45, 0.75) * s
		var h := rng.randf_range(-0.55, 0.6) * s
		var node := Node3D.new()
		core.add_child(node)
		ModelKit.part(node, OrganicMesh.blob("elem_shard_%d" % (i % 5), Vector3(0.16, 0.22, 0.13) * s, 0.35, 50 + i % 5, 8), rock, Vector3.ZERO, Vector3(rng.randf() * 360, rng.randf() * 360, 0))
		shards.append([node, r, h, rng.randf_range(0.6, 1.4) * (1.0 if i % 2 else -1.0), rng.randf() * TAU])
	for side: float in [-1.0, 1.0]:
		var pivot := ModelKit.joint(core, "Arm", Vector3(side * 0.7 * s, 0.2 * s, 0))
		for j in 4:
			var d := 0.25 + j * 0.22
			ModelKit.part(pivot, OrganicMesh.blob("elem_arm_%d" % j, Vector3(0.15 - j * 0.02, 0.13, 0.13) * s, 0.35, 60 + j, 8), rock, Vector3(side * d * 0.4, -d, -d * 0.2) * s)
		ModelKit.part(pivot, ModelKit.sphere(0.12 * s, 8), ModelKit.glow(Color(1.0, 0.6, 0.2), 6.0, 0.8), Vector3(side * 0.4, -1.0, -0.2) * s)
		arms.append([pivot, side])
	_flames = ModelKit.embers(self, 50, Vector3(0.3, 0.5, 0.3) * s, 0.8, 0.3 * s, 2.5)
	_flames.position = Vector3(0, 0.6 * s, 0)
	_flames.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 3.0
	_light.omni_range = 9.0 * s
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 2.0
	core.add_child(_light)


func _animate(delta: float) -> void:
	var s := size / 2.2
	var p := action_progress()
	var w := action_weight()
	var flare := 1.0
	var throw_side := 1.0
	var throw := 0.0
	if p >= 0.0:
		match _action:
			"throw", "attack", "cast":
				throw = keys(p, [[0, 0], [0.45, -1.0], [0.6, 1.0], [1, 0]]) * w
				flare = 1.0 + maxf(0.0, throw) * 0.8
			"roar":
				flare = 1.0 + w
			"hit":
				flare = 0.6
	if _dead:
		flare = maxf(0.0, 1.0 - _dead_t)
		_flames.emitting = _dead_t < 0.5
	core.position = Vector3(0, 1.4 * s + sin(_time * 2.0) * 0.08 * s, 0)
	core.rotation.y += delta * 0.6
	var breathe := 1.0 + sin(_time * 3.0) * 0.06 + (flare - 1.0) * 0.3
	for sh: Array in shards:
		var node: Node3D = sh[0]
		var a: float = float(sh[4]) + _time * float(sh[3])
		var r: float = float(sh[1]) * breathe
		node.position = Vector3(cos(a) * r, float(sh[2]) + sin(_time * 1.3 + a) * 0.06 * s, sin(a) * r)
		node.rotate_y(delta * float(sh[3]))
	for arm: Array in arms:
		var side: float = arm[1]
		var t := Vector3(0.2 + sin(_time * 1.5 + side) * 0.1, 0, side * 0.2)
		if side == throw_side and throw != 0.0:
			t = Vector3(0.2 - throw * 1.6, 0, side * 0.2)
		pose(arm[0], t, 10.0, delta)
	_core_glow.set_instance_shader_parameter(&"intensity", flare)
	_light.light_energy = 3.0 * flare + sin(_time * 13.0) * 0.3
