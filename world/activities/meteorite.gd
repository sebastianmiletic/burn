class_name Meteorite
extends Entity
## The starmetal core of a fallen star, buried under the crater's star-ore.
## Dig down to it, wait for it to cool (it glows less), then pry it out with a
## pickaxe: first come, first served. State replicates through `anim`:
## 0 hot, 1 cooled, 2 taken.

const HOT := 0
const COOL := 1
const TAKEN := 2

var cool_at := 0.0
var exposed := false
var _core: MeshInstance3D
var _embers: GPUParticles3D
var _light: OmniLight3D
var _check := 0.0
var _shown := -1


func _init() -> void:
	kind = "act_meteor"
	team = Team.NEUTRAL
	hit_radius = 0.9
	hit_height = 1.2
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	cool_at = float(data.get("cool_at", 0.0))
	var model := Node3D.new()
	add_child(model)
	_core = ActivityModels.meteorite(model, int(data.get("seed", 1)))
	_embers = ModelKit.embers(self, 60, Vector3(1.4, 0.3, 1.4), 2.2, 0.1, 3.5)
	_embers.position.y = 1.2
	_embers.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.light_energy = 4.0
	_light.omni_range = 14.0
	_light.light_volumetric_fog_energy = 2.0
	_light.position.y = 2.6
	add_child(_light)


func _process(delta: float) -> void:
	if is_server() and anim == HOT and Time.get_ticks_msec() / 1000.0 >= cool_at:
		anim = COOL
	if anim != _shown:
		_shown = anim
		match anim:
			COOL:
				_core.material_override = ItemMats.molten(Color(0.14, 0.13, 0.16), Color(0.55, 0.65, 1.0), 2.5)
				_light.light_color = Color(0.6, 0.7, 1.0)
				_light.light_energy = 2.0
				_embers.amount_ratio = 0.3
			TAKEN:
				_core.visible = false
				_embers.emitting = false
				_light.light_energy = 0.0
	_check -= delta
	if _check <= 0.0:
		_check = 0.3
		exposed = is_exposed()


func is_exposed() -> bool:
	var vw := voxels()
	if vw == null or not vw.is_area_loaded(global_position):
		return false
	var top := global_position + Vector3(0, 1.4, 0)
	return vw.field(top) < 0.5 or vw.field(top + Vector3(0.6, -0.1, 0)) < 0.5 or vw.field(top + Vector3(-0.6, -0.1, 0)) < 0.5


func seconds_to_cool() -> float:
	return maxf(0.0, cool_at - Time.get_ticks_msec() / 1000.0)


func interact_prompt(_p: Player) -> String:
	if anim == TAKEN or not exposed:
		return ""
	if anim == HOT:
		return "Starmetal core (too hot to touch)"
	return "Pry out the starmetal core"


func local_interact(p: Player) -> void:
	if anim == HOT:
		Events.notify.emit("It is still white-hot. Wait for it to cool.", "warn")
		return
	if ItemDB.kind_of(p.held_item()) != "pickaxe":
		Events.notify.emit("You need a pickaxe in hand to pry it loose.", "warn")
		return
	world().replicator.request_interact(net_id)


func server_interact(p: Player) -> void:
	if anim != COOL or not is_exposed() or ItemDB.kind_of(p.held_item()) != "pickaxe":
		return
	anim = TAKEN
	var w := world()
	var count := randi_range(2, 3)
	w.replicator.give_item_to(p.peer_id, "starmetal", count)
	w.replicator.give_xp_to(p.peer_id, 90, "")
	w.replicator.broadcast_entity_event(net_id, "taken", p.display_name)
	var acts := ActivityDirector.of(w)
	if acts != null:
		acts.events.on_core_taken(p, count)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(self) and world() != null:
			world().despawn_entity(self))


func on_event(event: String, arg: Variant) -> void:
	if event == "taken":
		anim = TAKEN
		Audio.play("break_crystal", global_position + Vector3(0, 1, 0), 2.0, 0.8)
		ModelKit.burst(self, Vector3(0, 1.0, 0), 50, 0.6, 6.0, 0.12, Color(0.8, 0.9, 1.0), Color(0.4, 0.55, 1.0), 1.0)
		if arg != null and world() != null and String(arg) != world().local_player.display_name:
			Events.notify.emit("%s claimed the starmetal core." % String(arg), "info")
