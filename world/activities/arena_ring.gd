class_name ArenaRing
extends Entity
## The Proving Ring's stones, braziers and war horn (at the centre: the
## entity's position). The braziers burn while a Proving runs. Interacting
## with the horn offers to start one and shows the honours.

var radius := 14.0
var _fires: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _lit := -1


func _init() -> void:
	kind = "act_arena"
	team = Team.NEUTRAL
	hit_radius = 0.8
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	radius = float(data.get("radius", 14.0))
	var root := Node3D.new()
	add_child(root)
	var vw := voxels()
	ActivityModels.horn_post(root)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		var h := _ground(vw, p)
		ActivityModels.standing_stone(root, 2.4 + 0.5 * float((i * 7) % 3), 31 + i, Vector3(p.x, h - 0.25, p.z), -a + PI * 0.5)
		var b := a + TAU / 16.0
		var bp := Vector3(cos(b) * (radius - 0.6), 0.0, sin(b) * (radius - 0.6))
		var top := ActivityModels.brazier(root, Vector3(bp.x, _ground(vw, bp) - 0.05, bp.z))
		var fire := ModelKit.embers(root, 24, Vector3(0.25, 0.1, 0.25), 0.9, 0.22, 1.6)
		fire.position = top
		fire.emitting = false
		_fires.append(fire)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.25)
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.position = top + Vector3(0, 0.6, 0)
		l.shadow_enabled = false
		root.add_child(l)
		_lights.append(l)
	if not Events.dialog_choice.is_connected(_on_choice):
		Events.dialog_choice.connect(_on_choice)


## Ground height under a local offset (the ring follows the terrain).
func _ground(vw: VoxelWorld, local: Vector3) -> float:
	var p := global_position + local
	if vw != null and vw.is_area_loaded(p):
		var g := vw.ground_below(p.x, p.y + 6.0, p.z, 12.0)
		if absf(g) < 1e6:
			return g - global_position.y
	return 0.0


func _acts() -> ActivityDirector:
	return ActivityDirector.of(world()) if world() != null else null


func _process(_delta: float) -> void:
	var acts := _acts()
	if acts == null:
		return
	var running := 1 if bool(acts.ring.state().get("running", false)) else 0
	if running != _lit:
		_lit = running
		for f in _fires:
			f.emitting = running == 1
		for l in _lights:
			l.light_energy = 2.4 if running == 1 else 0.0
	if running == 1:
		var t := Time.get_ticks_msec() * 0.001
		for i in _lights.size():
			_lights[i].light_energy = 2.2 + sin(t * 9.0 + i) * 0.25


func interact_prompt(_p: Player) -> String:
	var acts := _acts()
	if acts != null and bool(acts.ring.state().get("running", false)):
		return "Read the honours stone"
	return "Sound the war horn"


func local_interact(_p: Player) -> void:
	var acts := _acts()
	if acts == null:
		return
	var running := bool(acts.ring.state().get("running", false))
	var options: Array = []
	if not running:
		options.append({"text": "Sound the horn — begin the Proving", "id": "start"})
	options.append({"text": "Step back.", "id": "bye"})
	var intro := "Waves of monsters come over the stones, more each time, a champion every fifth. Stay inside the ring.\n\n" if not running else ""
	Events.dialog_open.emit(self, "The Proving Ring", PackedStringArray([intro + acts.ring.honours_text()]), options)


func _on_choice(npc: Node, id: String) -> void:
	if npc != self:
		return
	Events.dialog_close.emit()
	if id == "start":
		var acts := _acts()
		if acts != null:
			acts.request("arena_start")
