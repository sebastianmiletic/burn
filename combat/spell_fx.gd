class_name SpellFx
extends RefCounted
## What spells look like when they go off (played on every machine by SpellNet).

const COLORS := {
	"fireball": [Color(1.0, 0.85, 0.5), Color(1.0, 0.35, 0.08)],
	"frost_lance": [Color(0.85, 0.97, 1.0), Color(0.3, 0.65, 1.0)],
	"blink": [Color(0.9, 0.75, 1.0), Color(0.5, 0.25, 1.0)],
	"mend": [Color(0.85, 1.0, 0.8), Color(0.3, 0.9, 0.4)],
	"second_wind": [Color(1.0, 0.95, 0.75), Color(0.9, 0.7, 0.3)],
	"ward": [Color(0.8, 0.9, 1.0), Color(0.35, 0.55, 1.0)],
	"war_cry": [Color(1.0, 0.8, 0.5), Color(1.0, 0.35, 0.1)],
	"cleave": [Color(1.0, 0.95, 0.85), Color(0.9, 0.6, 0.3)],
	"earthshatter": [Color(0.85, 0.75, 0.6), Color(0.45, 0.35, 0.25)],
	"whirlwind": [Color(0.95, 0.95, 1.0), Color(0.6, 0.65, 0.75)],
	"arcane_nova": [Color(0.9, 0.8, 1.0), Color(0.55, 0.3, 1.0)],
	"chain_lightning": [Color(0.9, 0.95, 1.0), Color(0.45, 0.6, 1.0)],
	"rain_of_arrows": [Color(1.0, 0.95, 0.8), Color(0.7, 0.6, 0.4)],
	"meteor": [Color(1.0, 0.8, 0.4), Color(1.0, 0.25, 0.05)],
	"volley": [Color(1.0, 0.95, 0.8), Color(0.7, 0.6, 0.4)],
	"fizzle": [Color(0.75, 0.72, 0.7), Color(0.35, 0.33, 0.32)],
	"brew_explosion": [Color(1.0, 0.9, 0.6), Color(1.0, 0.4, 0.1)],
	"brew_poison": [Color(0.75, 1.0, 0.5), Color(0.25, 0.6, 0.1)],
}


static func play(world: Node3D, spell: String, pos: Vector3, dir: Vector3, power: float, pts: PackedVector3Array) -> void:
	var c: Array = COLORS.get(spell, [Color.WHITE, Color(0.6, 0.6, 0.6)])
	var hot: Color = c[0]
	var cool: Color = c[1]
	var s := clampf(power, 0.3, 1.0)
	match spell:
		"fizzle":
			ModelKit.burst(world, pos, 16, 0.15, 1.5, 0.25, hot, cool, 0.6)
			Audio.play("block_hit", pos, -10.0, 0.6)
		"blink":
			ModelKit.burst(world, pos, 40, 0.5, 4.0, 0.4, hot, cool, 0.5)
			if not pts.is_empty():
				ModelKit.burst(world, pts[0], 40, 0.5, 4.0, 0.4, hot, cool, 0.5)
			ModelKit.flash_light(world, pos, cool, 3.0, 6.0)
			Audio.play("fireball_cast", pos, -8.0, 1.8)
		"mend", "second_wind":
			ModelKit.burst(world, pos, 50, 0.8, 2.5, 0.35, hot, cool, 1.0)
			for p in pts:
				ModelKit.burst(world, p + Vector3(0, 1.0, 0), 30, 0.5, 2.0, 0.3, hot, cool, 0.9)
			ModelKit.flash_light(world, pos, cool, 3.0, 7.0, 0.6)
			Audio.play("potion", pos, -2.0, 1.3)
		"ward", "war_cry":
			ModelKit.burst(world, pos, 60, 1.0, 3.0, 0.4, hot, cool, 0.8)
			ModelKit.flash_light(world, pos, cool, 4.0, 8.0, 0.5)
			_ring(world, pos - Vector3(0, 0.9, 0), 1.6 if spell == "ward" else 4.0, cool, 0.6)
			Audio.play("levelup" if spell == "war_cry" else "hit_metal", pos, -4.0, 0.8)
		"cleave":
			for i in 7:
				var a := (float(i) / 6.0 - 0.5) * 2.4
				var d := dir.rotated(Vector3.UP, a)
				ModelKit.burst(world, pos + d * 2.2, 10, 0.2, 2.0, 0.3, hot, cool, 0.35)
			Audio.play("swing_heavy", pos, -2.0, 0.9)
		"earthshatter", "whirlwind", "arcane_nova":
			var r := 6.0 if spell == "earthshatter" else (5.0 if spell == "whirlwind" else 7.0)
			_ring(world, pos, r * s, cool, 0.5)
			ModelKit.burst(world, pos, 90, r * 0.5, 7.0, 0.6, hot, cool, 0.7)
			ModelKit.flash_light(world, pos + Vector3(0, 1, 0), cool, 5.0, r * 2.0)
			Audio.play("explosion", pos, -4.0, 1.4 if spell == "arcane_nova" else 0.8)
			Events.screen_shake.emit(0.35 * s)
		"chain_lightning":
			for i in range(1, pts.size()):
				_beam(world, pts[i - 1], pts[i], cool, hot)
				ModelKit.burst(world, pts[i], 20, 0.2, 3.0, 0.3, hot, cool, 0.4)
			ModelKit.flash_light(world, pos, cool, 5.0, 12.0, 0.25)
			Audio.play("explosion", pos, -8.0, 1.7)
		"rain_of_arrows", "meteor":
			_ring(world, pos + Vector3(0, 0.15, 0), 5.0, cool, 1.4)
		"brew_explosion":
			ModelKit.burst(world, pos, 120, 0.8, 9.0, 0.7, hot, cool, 0.8)
			ModelKit.flash_light(world, pos, cool, 7.0, 12.0, 0.5)
			Audio.play("explosion", pos, 0.0, 1.0)
			Events.screen_shake.emit(0.5)
		"brew_poison":
			for i in 5:
				var t := world.get_tree().create_timer(i * 0.5)
				t.timeout.connect(func() -> void:
					if is_instance_valid(world):
						ModelKit.burst(world, pos + Vector3(0, 0.8, 0), 60, 1.6, 1.2, 1.0, hot, cool, 1.6))
			Audio.play("splash", pos, -4.0, 0.6)


## A flat ring of light on the ground that widens and fades.
static func _ring(world: Node3D, pos: Vector3, radius: float, color: Color, seconds: float) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	mi.mesh = torus
	mi.material_override = MaterialLibrary.fx(color.lightened(0.4), color, 6.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(0.2, 0.2, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "transparency", 1.0, seconds)
	tw.chain().tween_callback(mi.queue_free)


## A jagged bolt between two points that flickers out.
static func _beam(world: Node3D, a: Vector3, b: Vector3, color: Color, hot: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var n := 8
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t)
		if i < n:
			p += Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
		st.add_vertex(prev)
		st.add_vertex(p)
		prev = p
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = hot
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 8.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.3)
	tw.tween_callback(mi.queue_free)
