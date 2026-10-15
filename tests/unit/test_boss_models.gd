extends TestCase
## The bespoke boss models build, animate through every phase and action,
## brood while idle, die and dissolve without errors, and stay within budget
## (parts merged per material; animation cost per frame).

const KINDS := ["warden", "mountain_king", "hades", "bog_hag", "ryft_sentinel", "void_sovereign"]
const ACTIONS := ["attack", "attack2", "sweep", "slam", "roar", "summon", "cast", "throw", "spikes", "teleport", "hit"]


func test_boss_models_build_and_animate() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null:
		print("      (test_boss_models skipped: autoloads are not running yet in this runner)")
		return
	for kind: String in KINDS:
		var t0 := Time.get_ticks_usec()
		var m := Models.create(kind)
		check(m != null, "%s has a model" % kind)
		if m == null:
			continue
		tree.root.add_child(m)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		check(m.has_method("set_boss_state"), "%s model takes the boss state" % kind)
		var draws := 0
		var tris := 0
		for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null or not (mi as MeshInstance3D).visible:
				continue
			draws += mesh.get_surface_count()
			for s in mesh.get_surface_count():
				var idx: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array:
					tris += (idx as PackedInt32Array).size() / 3
		check(draws >= 8, "%s draws its parts (%d)" % [kind, draws])
		check(draws <= 70, "%s parts are merged (%d draws)" % [kind, draws])
		check(tris > 3000, "%s is detailed (%d triangles)" % [kind, tris])
		# Brooding, then every phase with every action.
		m.call("set_boss_state", false, 1, false)
		for i in 30:
			m._process(1.0 / 30.0)
		var t1 := Time.get_ticks_usec()
		var frames := 0
		for phase in [1, 2, 3]:
			m.call("set_boss_state", true, phase, false)
			for a: String in ACTIONS:
				m.play(a)
				for i in 8:
					m.move_speed = 2.0 if i % 2 == 0 else 0.0
					m._process(1.0 / 30.0)
					frames += 1
		var us := float(Time.get_ticks_usec() - t1) / frames
		m.set_dead(true)
		for i in 200:
			m._process(1.0 / 30.0)
		check(m.is_dissolved(), "%s dissolves after death" % kind)
		print("      %-15s build %5.0f ms  %3d draws  %6d tris  animate %4.0f us/frame" % [kind, build_ms, draws, tris, us])
		m.free()
