class_name EliteMark
extends Entity
## Marks a named elite (bounty quarry, raid captain, ring champion) on every
## machine: grows its model, wraps it in an ember aura and floats its name and
## health over it. Follows its target; the server removes it with the target.

var target_id := 0
var title := ""
var size := 1.3
var max_hp := 0.0
var _label: Label3D
var _bar: Label3D
var _aura: GPUParticles3D
var _ring: MeshInstance3D
var _scaled := false
var _gone_t := 0.0


func _init() -> void:
	kind = "act_elite"
	team = Team.NEUTRAL
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	target_id = int(data.get("target", 0))
	title = String(data.get("name", ""))
	size = float(data.get("size", 1.3))
	max_hp = float(data.get("max_health", 0.0))
	_label = Label3D.new()
	_label.text = title
	_label.font = UiTheme.MONO_BOLD
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.0035
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.72, 0.35)
	_label.outline_modulate = Color(0.08, 0.03, 0.0, 0.9)
	add_child(_label)
	_bar = Label3D.new()
	_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.font = UiTheme.MONO_BOLD
	_bar.font_size = 28
	_bar.pixel_size = 0.003
	_bar.outline_size = 6
	_bar.modulate = Color(0.95, 0.3, 0.2)
	add_child(_bar)
	_aura = ModelKit.embers(self, 40, Vector3(0.9, 0.2, 0.9), 1.2, 0.09, 1.6)
	_aura.emitting = true
	_ring = MeshInstance3D.new()
	_ring.mesh = ModelKit.arc(0.9, 1.15, 360.0, 40)
	_ring.material_override = ModelKit.glow(Color(1.0, 0.45, 0.15), 3.0, 0.6)
	_ring.rotation_degrees.x = -90.0
	_ring.position.y = 0.06
	add_child(_ring)


func _process(delta: float) -> void:
	var w := world()
	if w == null:
		return
	var t := w.entity(target_id)
	if t == null or t.dead:
		_aura.emitting = false
		_label.visible = false
		_bar.visible = false
		_ring.visible = false
		_gone_t += delta
		if is_server() and _gone_t > 3.0:
			_gone_t = -1000.0
			w.despawn_entity(self)
		return
	global_position = t.global_position
	if not _scaled:
		var m: Variant = t.get("model")
		if m is Node3D:
			(m as Node3D).scale = Vector3.ONE * size
			_scaled = true
			if max_hp <= 0.0:
				max_hp = maxf(t.health, t.max_health)
	var h := t.hit_height * size
	_label.position.y = h + 0.55
	_bar.position.y = h + 0.25
	var r := maxf(0.6, t.hit_radius * size * 1.6)
	_ring.scale = Vector3(r, r, r)
	var frac := clampf(t.health / maxf(max_hp, 1.0), 0.0, 1.0)
	var n := int(round(frac * 14.0))
	_bar.text = "█".repeat(n) + "░".repeat(14 - n)
