extends RefCounted
## Implementation of tests/tools/char_bench.gd (loaded after autoloads exist).


func run(tree: SceneTree) -> void:
	var root := Node3D.new()
	tree.get_root().add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 2, 8)
	var styles := {}
	for i in 8:
		styles["player%d" % i] = Models.player_style(i)
	for k: String in ["skeleton", "archer", "ghoul", "troll", "warden", "mountain_king", "hades"]:
		styles[k] = (Models.create(k) as HumanoidModel).style
	for i in 24:
		var role: String = ["villager", "villager", "blacksmith", "merchant", "guard", "elder", "chief", "villager"][i % 8]
		styles["%s_%d" % [role, i]] = CharStyles.villager(role, i * 131 + 7)
	CharBody.profile = OS.get_cmdline_user_args().has("--profile")
	var total_ms := 0.0
	var max_tris := 0
	for key: String in styles:
		var t0 := Time.get_ticks_usec()
		var b := CharBody.get_body(styles[key])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total_ms += ms
		max_tris = maxi(max_tris, int(b["tris"]))
		print("%-16s tris %5d verts %5d bones %2d  build %6.1f ms" % [key, b["tris"], b["verts"], (b["rest"] as PackedVector3Array).size(), ms])
	print("styles %d, unique meshes %d, total build %.0f ms, max tris %d" % [styles.size(), CharBody.cached_count(), total_ms, max_tris])

	# Drive a crowd.
	var models: Array[HumanoidModel] = []
	var keys_list := styles.keys()
	for i in 20:
		var m := HumanoidModel.new(styles[keys_list[i % keys_list.size()]])
		m.position = Vector3((i % 5) * 2.0 - 4.0, 0, -float(i / 5) * 2.0)
		root.add_child(m)
		m.set_process(false)
		models.append(m)
	models[0].set_held("sword_iron")
	var dt := 1.0 / 60.0
	var usec := 0
	var frames := 360
	var per_frame := PackedFloat32Array()
	HumanoidModel.prof = PackedInt64Array([0, 0, 0, 0, 0])
	for f in frames:
		var frame_usec := 0
		for i in models.size():
			var m := models[i]
			var phase := float(f) / frames
			var spd := 1.4 if phase < 0.3 else (4.6 if phase < 0.6 else 7.4)
			m.velocity = Vector3(0, 0, -spd)
			m.move_speed = spd
			m.sprinting = spd > 7.0
			m.grounded = not (f % 120 > 60 and f % 120 < 90)
			if f % 120 == 60:
				m.on_jump()
				m.velocity.y = 9.0
			if f % 120 == 90:
				m.on_land(14.0 if i % 2 == 0 else 6.0)
			if f % 90 == 10:
				m.play("attack" if i % 3 == 0 else ("attack2" if i % 3 == 1 else "dodge"))
			if f == 300 and i % 4 == 0:
				m.set_dead(true)
			var t0 := Time.get_ticks_usec()
			m._process(dt)
			var u := Time.get_ticks_usec() - t0
			usec += u
			frame_usec += u
		per_frame.append(frame_usec / 1000.0 / models.size())
	per_frame.sort()
	var pf := HumanoidModel.prof
	var n := float(frames * models.size()) * 1000.0
	print("  stages (mean ms/model): locomotion %.3f pose %.3f apply %.3f cloth %.3f fx %.3f" % [pf[0] / n, pf[1] / n, pf[2] / n, pf[3] / n, pf[4] / n])
	HumanoidModel.prof = PackedInt64Array()
	print("model update: mean %.3f ms, median %.3f ms, p10 %.3f ms per model per frame (%d models, %d frames)" % [
		usec / 1000.0 / (frames * models.size()), per_frame[frames / 2], per_frame[frames / 10], models.size(), frames])
	# Reference workload to compare runs on a loaded machine.
	var refs := PackedFloat32Array()
	for r in 9:
		var t1 := Time.get_ticks_usec()
		var acc := Vector3.ZERO
		for k in 20000:
			acc += Quaternion.from_euler(Vector3(k * 0.001, 0.2, 0.1)) * Vector3.UP
		refs.append((Time.get_ticks_usec() - t1) / 1000.0)
	refs.sort()
	print("reference loop (20k quaternion ops): median %.2f ms, min %.2f ms" % [refs[4], refs[0]])
	var ok := true
	for m in models:
		if m.skeleton == null or m.mesh_instance == null:
			ok = false
	print("CHAR_BENCH ", "OK" if ok else "FAIL")
	tree.quit(0 if ok else 1)
