class_name Projectile
extends Node3D
## Fireballs, arrows, boulders and soul bolts.
##
## Every machine moves the projectile and plays its effects; only the server
## (solo counts as server) applies damage. Collides with solid voxels and with
## entities of the opposing team.

const KINDS := {
	"fireball": {"gravity": 0.0, "radius": 0.45, "explode": 2.2, "damage_kind": "fire", "life": 6.0, "visual": "fire", "size": 1.1},
	"player_fireball": {"gravity": 0.0, "radius": 0.5, "explode": 2.8, "damage_kind": "fire", "life": 4.0, "visual": "fire_bright", "size": 1.0},
	"arrow": {"gravity": 9.0, "radius": 0.18, "explode": 0.0, "damage_kind": "hit", "life": 5.0, "visual": "arrow", "size": 1.0},
	"boulder": {"gravity": 16.0, "radius": 1.0, "explode": 3.4, "damage_kind": "hit", "life": 7.0, "visual": "boulder", "size": 1.0},
	"soul_bolt": {"gravity": 0.0, "radius": 0.4, "explode": 1.2, "damage_kind": "fire", "life": 6.0, "visual": "soul", "size": 0.9, "homing": 1.6},
	# Creature venom / bile: lobbed globs that splash (Leviathan, spiders, the Bog Hag).
	"bile": {"gravity": 9.0, "radius": 0.5, "explode": 2.6, "damage_kind": "hit", "life": 6.0, "visual": "bile", "size": 1.2},
	"venom": {"gravity": 6.0, "radius": 0.3, "explode": 1.2, "damage_kind": "hit", "life": 4.0, "visual": "bile", "size": 0.6},
}

var kind := "fireball"
var velocity := Vector3.ZERO
var owner_id := 0
var team := 1
var dimension := 0
var damage := 10.0

var _cfg := {}
var _life := 6.0
var _done := false
var _spin: Node3D


func setup(projectile_kind: String, origin: Vector3, vel: Vector3, owner: int, owner_team: int, dim: int, dmg: float) -> Projectile:
	kind = projectile_kind
	velocity = vel
	owner_id = owner
	team = owner_team
	dimension = dim
	damage = dmg
	_cfg = KINDS.get(kind, KINDS["fireball"])
	_life = float(_cfg["life"])
	position = origin
	return self


func _ready() -> void:
	if _cfg.is_empty():
		_cfg = KINDS[kind]
	_build_visual()
	if kind in ["fireball", "player_fireball"]:
		Audio.play("fireball_cast", global_position, -4.0)
	elif kind == "arrow":
		Audio.play("arrow", global_position, -6.0)


func _is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_life -= delta
	if _life <= 0.0:
		_impact(global_position, null)
		return
	velocity.y -= float(_cfg["gravity"]) * delta
	var homing := float(_cfg.get("homing", 0.0))
	if homing > 0.0:
		var target := _nearest_target(global_position, 30.0)
		if target != null:
			var want := (target.center() - global_position).normalized() * velocity.length()
			velocity = velocity.lerp(want, clampf(homing * delta, 0.0, 1.0))
	var from := global_position
	var to := from + velocity * delta
	var radius := float(_cfg["radius"])
	var world := GameWorld.instance
	var voxels: VoxelWorld = world.world_for(dimension) if world != null else null
	# March the segment so fast projectiles can't tunnel.
	var steps := maxi(1, ceili(from.distance_to(to) / 0.3))
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		var hit := _entity_hit(p, radius)
		if hit != null:
			_impact(p, hit)
			return
		if voxels != null and voxels.is_loaded(Vector3i(p.floor())) and voxels.is_solid(Vector3i(p.floor())):
			_impact(p - velocity.normalized() * 0.2, null)
			return
	global_position = to
	if kind == "arrow" and velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
	elif _spin != null:
		_spin.rotate_x(delta * 6.0)
		_spin.rotate_z(delta * 3.0)


func _target_team() -> int:
	return Entity.Team.MONSTERS if team == Entity.Team.PLAYERS else Entity.Team.PLAYERS


func _entity_hit(p: Vector3, radius: float) -> Entity:
	var world := GameWorld.instance
	if world == null:
		return null
	for e: Entity in world.entities_near(p, radius + 4.0, dimension, _target_team()):
		if e.dead or e.net_id == owner_id:
			continue
		var c := e.global_position
		var horiz := Vector2(p.x - c.x, p.z - c.z).length()
		if horiz <= radius + e.hit_radius and p.y >= c.y - radius and p.y <= c.y + e.hit_height + radius:
			return e
	return null


func _nearest_target(p: Vector3, max_dist: float) -> Entity:
	var world := GameWorld.instance
	if world == null:
		return null
	var best: Entity = null
	var best_d := max_dist
	for e: Entity in world.entities_near(p, max_dist, dimension, _target_team()):
		if e.dead:
			continue
		var d := e.center().distance_to(p)
		if d < best_d:
			best_d = d
			best = e
	return best


func _impact(point: Vector3, hit: Entity) -> void:
	_done = true
	var world := GameWorld.instance
	var dkind := String(_cfg["damage_kind"])
	var explode := float(_cfg["explode"])
	if _is_server() and world != null:
		if hit != null:
			world.damage(hit, damage, owner_id, dkind)
		if explode > 0.0:
			for e: Entity in world.entities_near(point, explode + 2.0, dimension, _target_team()):
				if e == hit or e.dead:
					continue
				var d := e.center().distance_to(point)
				if d <= explode + e.hit_radius:
					world.damage(e, damage * lerpf(0.75, 0.35, clampf(d / explode, 0.0, 1.0)), owner_id, dkind)
	_play_impact(point, explode)
	queue_free()


func _play_impact(point: Vector3, explode: float) -> void:
	var parent := get_parent() as Node3D
	if parent == null:
		return
	match String(_cfg["visual"]):
		"fire", "fire_bright":
			ModelKit.burst(parent, point, 50, 0.4, 6.0 + explode, 0.7)
			ModelKit.flash_light(parent, point, Color(1.0, 0.5, 0.2), 6.0, explode * 4.0 + 4.0)
			Audio.play("fireball_hit", point)
			_shake(point, 0.35)
		"soul":
			ModelKit.burst(parent, point, 30, 0.3, 5.0, 0.6, Color(0.7, 0.9, 1.0), Color(0.2, 0.4, 1.0))
			ModelKit.flash_light(parent, point, Color(0.4, 0.6, 1.0), 4.0, 6.0)
			Audio.play("fireball_hit", point, -3.0, 1.3)
		"boulder":
			ModelKit.burst(parent, point, 40, 0.8, 7.0, 0.8, Color(0.75, 0.72, 0.68), Color(0.35, 0.33, 0.3), 0.9)
			Audio.play("explosion", point)
			_shake(point, 0.6)
		"arrow":
			Audio.play("block_hit", point, -8.0, 1.4)
		"bile":
			CreatureFx.play(parent, "venom", point, maxf(0.8, explode * 0.6))
			Audio.play("splash", point, -2.0, 1.4)


func _shake(point: Vector3, strength: float) -> void:
	var world := GameWorld.instance
	if world != null and world.local_player != null:
		var d := world.local_player.global_position.distance_to(point)
		if d < 25.0:
			Events.screen_shake.emit(strength * (1.0 - d / 25.0))


func _build_visual() -> void:
	match String(_cfg["visual"]):
		"fire", "fire_bright":
			var bright := String(_cfg["visual"]) == "fire_bright"
			var size := float(_cfg["size"])
			var core := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(size, size)
			core.mesh = quad
			core.material_override = MaterialLibrary.fx(Color(1.0, 0.95, 0.75) if bright else Color(1.0, 0.85, 0.5), Color(1.0, 0.4, 0.08), 9.0)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(core)
			var trail := ModelKit.embers(self, 50, Vector3(0.15, 0.15, 0.15), 0.6, size * 0.55, 0.3)
			trail.emitting = true
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.2)
			light.light_energy = 2.5
			light.omni_range = 7.0
			light.light_volumetric_fog_energy = 2.0
			add_child(light)
		"soul":
			var core := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.8, 0.8)
			core.mesh = quad
			core.material_override = MaterialLibrary.fx(Color(0.8, 0.95, 1.0), Color(0.2, 0.45, 1.0), 8.0)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(core)
			var light := OmniLight3D.new()
			light.light_color = Color(0.4, 0.6, 1.0)
			light.light_energy = 2.0
			light.omni_range = 6.0
			add_child(light)
		"bile":
			var size := float(_cfg["size"])
			var core := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(size, size)
			core.mesh = quad
			core.material_override = MaterialLibrary.fx(Color(0.85, 1.0, 0.5), Color(0.2, 0.55, 0.05), 5.0)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(core)
			var drip := CreatureFx.emitter(self, "venom", 24, Vector3(0.1, 0.1, 0.1), 0.6)
			drip.emitting = true
		"arrow":
			var wood := ModelKit.mat(Color(0.45, 0.32, 0.2))
			ModelKit.part(self, ModelKit.cylinder(0.015, 0.015, 0.8, 4), wood, Vector3(0, 0, 0.1), Vector3(90, 0, 0))
			ModelKit.part(self, ModelKit.cone(0.04, 0.12, 4), ModelKit.metal(Color(0.6, 0.6, 0.62)), Vector3(0, 0, -0.32), Vector3(-90, 0, 0))
			ModelKit.part(self, ModelKit.box(Vector3(0.1, 0.01, 0.15)), ModelKit.cloth(Color(0.8, 0.75, 0.7)), Vector3(0, 0, 0.45))
		"boulder":
			_spin = Node3D.new()
			add_child(_spin)
			var rock := MeshInstance3D.new()
			rock.mesh = MeshFactory.rock(0.9, randi())
			rock.material_override = ModelKit.mat(Color(0.5, 0.52, 0.56), AsciiMaterialId.SOLID, 0.9, 0.35)
			_spin.add_child(rock)
			ModelKit.part(_spin, ModelKit.box(Vector3(0.4, 0.4, 0.4)), ModelKit.glow(Color(0.5, 0.85, 1.0), 2.5), Vector3(0.6, 0.2, 0.0))
