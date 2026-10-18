class_name Ogygia
extends RefCounted
## Ogygia, the island of second chances (dimension 3), home of Calypso.
##
## It cannot be reached by travel, portals or the map: the only way in is to
## black out under water and be among the rare few the sea gives back
## (RESCUE_CHANCE, rolled by the host). The way out is Calypso's raft, which
## carries you to your last shrine (or the starting spawn) with everything
## you carried. GameWorld prepares the dimension with OgygiaGen; this script
## holds the rules, the arrival/departure flow and the hand-built scenery.

const DIM := 3
## Chance that drowning ends on Ogygia instead of in death.
const RESCUE_CHANCE := 0.09
const LORE_ID := "lore_ogygia"


## Host side: does the sea give this one back?
static func rolls_rescue(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < RESCUE_CHANCE


static func beach_spawn(g: WorldGen) -> Vector3:
	var p := OgygiaGen.BEACH
	return Vector3(p.x, g.ground_level(p.x, p.z) + 0.05, p.z)


## Where Calypso tends her hearth, inside the grotto.
static func hearth(g: WorldGen) -> Vector3:
	var p := OgygiaGen.GROTTO + Vector3(0.0, 0.0, -2.0)
	return Vector3(p.x, OgygiaGen.SEA + 1.6, p.z)


## Local player: wake on the beach.
static func arrive(w: GameWorld) -> void:
	var p := w.local_player
	if p == null or not w.worlds.has(DIM):
		return
	w.travel(DIM)
	p.global_position = beach_spawn(w.gen_for(DIM))
	p.body.velocity = Vector3.ZERO
	p.health = p.max_health
	p.yaw = PI
	if p.camera != null:
		p.camera.yaw = 0.0  # facing the grotto (north)
		p.camera.pitch = -0.05
	p.invulnerable_until = Time.get_ticks_msec() / 1000.0 + 5.0
	Events.player_health_changed.emit(p.health, p.max_health)
	Events.notify.emit("You wake on warm sand. Someone has bound your wounds.", "info")
	if w.quests != null and w.quests.has_method("record_lore") and w.quests.record_lore(LORE_ID):
		Events.notify.emit("Journal: Ogygia", "quest")
	if Net.is_server():
		ensure_residents(w)


## Local player: the raft carries you home (last shrine, else the spawn).
static func depart(w: GameWorld) -> void:
	var p := w.local_player
	if p == null or p.dimension != DIM:
		return
	var dim := p.respawn_dimension if p.respawn_dimension != DIM and w.worlds.has(p.respawn_dimension) else 0
	w.travel(dim)
	var target := p.respawn_point if p.respawn_point != Vector3.ZERO and p.respawn_dimension == dim else w.default_spawn(dim)
	p.global_position = target
	p.body.velocity = Vector3.ZERO
	w.world_for(dim).focus = target
	Events.notify.emit("The raft runs aground. Ogygia is gone behind you, as if it never was.", "info")


## Host: Calypso and her raft exist once someone is on the island.
static func ensure_residents(w: GameWorld) -> void:
	var have := {}
	for e in w.all_entities():
		var ent := e as Entity
		if ent != null and ent.dimension == DIM:
			have[ent.kind] = true
	var g := w.gen_for(DIM)
	if not have.has("calypso"):
		w.spawn_entity("calypso", hearth(g) + Vector3(1.6, 0.0, 1.2), DIM, {"role": "calypso", "seed": 7})
	if not have.has("ogygia_raft"):
		var r := OgygiaGen.RAFT
		w.spawn_entity("ogygia_raft", Vector3(r.x, OgygiaGen.SEA + 0.35, r.z), DIM, {})


## Hand-built set dressing: the hearth, ivy and vines in the grotto, grapevines
## at its mouth, flowers in the meadow, the spring's reeds. Visible only on Ogygia.
static func build_scenery(g: WorldGen) -> Node3D:
	var root := Node3D.new()
	root.name = "OgygiaScenery"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1906
	# Hearth: a ring of stones, embers, a warm flickering light.
	var h := hearth(g)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.42, 0.4, 0.37)
	stone.roughness = 0.9
	for i in 9:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.26
		s.mesh = sm
		s.material_override = stone
		s.position = h + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 9.0) * 0.55 + Vector3(0, 0.08, 0)
		root.add_child(s)
	var embers := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.38
	em.height = 0.22
	embers.mesh = em
	embers.material_override = MaterialLibrary.emissive(Color(1.0, 0.42, 0.12), 3.0)
	embers.position = h + Vector3(0, 0.08, 0)
	root.add_child(embers)
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.18
	fm.height = 0.7
	flame.mesh = fm
	flame.material_override = MaterialLibrary.emissive(Color(1.0, 0.62, 0.22), 5.0)
	flame.position = h + Vector3(0, 0.42, 0)
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 2.6
	light.omni_range = 11.0
	light.shadow_enabled = true
	light.position = h + Vector3(0, 0.9, 0)
	light.set_script(_FLICKER)
	root.add_child(light)
	# Ivy and vines hanging from the grotto roof and around its mouth.
	var vine := StandardMaterial3D.new()
	vine.albedo_color = Color(0.2, 0.36, 0.14)
	vine.roughness = 0.8
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.26, 0.48, 0.18)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grape := StandardMaterial3D.new()
	grape.albedo_color = Color(0.3, 0.12, 0.32)
	grape.roughness = 0.35
	var vw_spots: Array[Vector3] = []
	for i in 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.5, 6.0)
		var top := OgygiaGen.GROTTO + Vector3(cos(a) * r, 0.0, sin(a) * r * 1.05)
		vw_spots.append(top)
	for i in 18:
		var t := rng.randf()
		var mouth := OgygiaGen.GROTTO_MOUTH + Vector3(rng.randf_range(-3.2, 3.2), 0.0, rng.randf_range(-1.0, 2.0))
		vw_spots.append(mouth.lerp(mouth + Vector3(0, 0.5, 0), t))
	for top: Vector3 in vw_spots:
		var ceil_y := _ceiling(g, top)
		if ceil_y == INF:
			continue
		var length := rng.randf_range(0.8, 2.8)
		var strand := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.012
		cm.height = length
		cm.radial_segments = 5
		strand.mesh = cm
		strand.material_override = vine
		strand.position = Vector3(top.x, ceil_y - length * 0.5, top.z)
		root.add_child(strand)
		for k in int(length * 4.0):
			var lf := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.16, 0.12)
			lf.mesh = q
			lf.material_override = leaf
			lf.position = Vector3(top.x, ceil_y - rng.randf() * length, top.z) + Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
			lf.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, 0)
			root.add_child(lf)
		if top.z > OgygiaGen.GROTTO.z + 7.0 and rng.randf() < 0.5:
			# Grapes on the vines at the grotto's mouth.
			for k in 7:
				var gr := MeshInstance3D.new()
				var gs := SphereMesh.new()
				gs.radius = 0.035
				gs.height = 0.07
				gr.mesh = gs
				gr.material_override = grape
				gr.position = Vector3(top.x, ceil_y - length + 0.2, top.z) + Vector3(rng.randf_range(-0.06, 0.06), -k * 0.035, rng.randf_range(-0.06, 0.06))
				root.add_child(gr)
	# Meadow flowers: violets, white asphodel and parsley, as Homer has it.
	var colours := [Color(0.5, 0.32, 0.75), Color(0.95, 0.95, 0.9), Color(0.95, 0.82, 0.3), Color(0.85, 0.35, 0.4)]
	var flower_mats: Array[StandardMaterial3D] = []
	for c: Color in colours:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.6
		flower_mats.append(m)
	var mm_stem := StandardMaterial3D.new()
	mm_stem.albedo_color = Color(0.25, 0.45, 0.2)
	for i in 260:
		var x := OgygiaGen.CENTER.x + rng.randf_range(-48, 48)
		var z := OgygiaGen.CENTER.y + rng.randf_range(-48, 48)
		var y := g.ground_level(x, z)
		if y < OgygiaGen.SEA + 2.6 or Vector2(x, z).distance_to(OgygiaGen.SPRING) < 5.0:
			continue
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = rng.randf_range(0.05, 0.09)
		hm.height = hm.radius * 1.2
		head.mesh = hm
		head.material_override = flower_mats[rng.randi() % flower_mats.size()]
		var stem_h := rng.randf_range(0.18, 0.4)
		head.position = Vector3(x, y + stem_h, z)
		root.add_child(head)
		var st := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.008
		sc.bottom_radius = 0.01
		sc.height = stem_h
		sc.radial_segments = 4
		st.mesh = sc
		st.material_override = mm_stem
		st.position = Vector3(x, y + stem_h * 0.5, z)
		root.add_child(st)
	# Reeds around the spring.
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.2, 5.6)
		var x := OgygiaGen.SPRING.x + cos(a) * r
		var z := OgygiaGen.SPRING.y + sin(a) * r
		var y := g.ground_level(x, z)
		var reed := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.006
		rm.bottom_radius = 0.016
		rm.height = rng.randf_range(0.7, 1.3)
		rm.radial_segments = 4
		reed.mesh = rm
		reed.material_override = mm_stem
		reed.position = Vector3(x, y + rm.height * 0.5, z)
		reed.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		root.add_child(reed)
	return root


## Height of the grotto's roof above `p` (INF where there is no roof nearby).
static func _ceiling(g: WorldGen, p: Vector3) -> float:
	var og := g as OgygiaGen
	if og == null:
		return INF
	var y := OgygiaGen.SEA + 2.0
	while y < OgygiaGen.SEA + 12.0:
		var air := og._grotto(Vector3(p.x, y, p.z)) > 0.0 and og.height(p.x, p.z) > y + 0.5
		if not air and y > OgygiaGen.SEA + 2.4:
			return y if y < og.height(p.x, p.z) else INF
		y += 0.25
	return INF


const _FLICKER := preload("res://world/ogygia/hearth_flicker.gd")
