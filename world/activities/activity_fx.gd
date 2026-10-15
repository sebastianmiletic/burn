class_name ActivityFx
extends RefCounted
## One-shot visuals for activities, played on every machine by
## ActivityDirector.fx(): a falling star and its impact, war horns, reward bursts.

static func play(gw: GameWorld, kind: String, data: Dictionary) -> void:
	var dim := int(data.get("dim", 0))
	if dim != gw.local_dimension:
		return
	match kind:
		"meteor":
			_meteor(gw, data.get("from", Vector3.ZERO), data.get("to", Vector3.ZERO), float(data.get("eta", 5.0)))
		"horn":
			var at: Vector3 = data.get("pos", Vector3.ZERO)
			Audio.play("roar_big", at, 4.0, 0.42)
			gw.get_tree().create_timer(0.9).timeout.connect(func() -> void: Audio.play("roar_big", at, 2.0, 0.38))
		"burst":
			var at2: Vector3 = data.get("pos", Vector3.ZERO)
			var c: Color = data.get("color", Color(1.0, 0.8, 0.4))
			ModelKit.burst(gw, at2, 36, 0.4, 5.0, 0.12, c.lightened(0.4), c, 0.9)
			ModelKit.flash_light(gw, at2, c, 4.0, 8.0, 0.5)


## A star falling from high in the sky along a slanted path, then the impact.
static func _meteor(gw: GameWorld, from: Vector3, to: Vector3, eta: float) -> void:
	var star := Node3D.new()
	star.name = "FallingStar"
	gw.add_child(star)
	star.global_position = from
	var head := MeshInstance3D.new()
	head.mesh = ModelKit.sphere(1.1, 12)
	head.material_override = ModelKit.glow(Color(1.0, 0.75, 0.45), 9.0)
	star.add_child(head)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 8.0
	light.omni_range = 60.0
	light.shadow_enabled = false
	star.add_child(light)
	var trail := ModelKit.embers(star, 90, Vector3(0.8, 0.8, 0.8), 1.6, 0.9, 0.2)
	trail.local_coords = false
	trail.emitting = true
	Audio.play("fireball_cast", to, 6.0, 0.35)
	var tw := star.create_tween()
	tw.tween_property(star, "global_position", to, eta).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_impact(gw, to)
		head.visible = false
		light.visible = false
		trail.emitting = false
		star.get_tree().create_timer(2.0).timeout.connect(star.queue_free))


static func _impact(gw: GameWorld, at: Vector3) -> void:
	ModelKit.burst(gw, at + Vector3(0, 0.6, 0), 120, 1.4, 14.0, 0.5, Color(1.0, 0.9, 0.6), Color(1.0, 0.35, 0.08), 1.4)
	ModelKit.flash_light(gw, at + Vector3(0, 2, 0), Color(1.0, 0.6, 0.3), 14.0, 50.0, 0.9)
	Audio.play("explosion", at, 8.0, 0.7)
	Audio.play("thunder", at, 2.0, 1.3)
	var p := gw.local_player
	if p != null:
		var d := p.global_position.distance_to(at)
		var k := clampf(1.0 - d / 140.0, 0.0, 1.0)
		if k > 0.0:
			Events.screen_shake.emit(0.9 * k)
			gw.view.flash = maxf(gw.view.flash, 0.5 * k)
