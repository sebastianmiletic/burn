class_name BossBar
extends Control
## Top-centre boss health: Cinzel name, a long bar, phase pips on the left
## and the numbers on the right of the line below (never overlapping).

const ROMAN := ["I", "II", "III", "IV"]

var _boss: Object
var _name := ""
var _health := 1.0
var _max := 1.0
var _phase := 1
var _shown := 1.0
var _trail := 1.0
var _alpha := 0.0
var _visible_target := false
var _defeated_timer := 0.0
var _hit_flash := 0.0
var _phase_flash := 0.0
var _grace := 0.0          # seconds after an engage event before `engaged` is trusted
var _near := true


## True while the local player is actually at this boss's fight: same
## dimension, within the arena (at least 60 m), and the boss still engaged.
func _player_at_fight() -> bool:
	if _boss == null or not is_instance_valid(_boss) or not (_boss is Node3D):
		return true  # no live boss to measure against (gallery, defeat banner)
	var player := UiContext.player()
	if player == null:
		return true
	var bdim: Variant = _boss.get("dimension")
	var pdim: Variant = player.get("dimension")
	if bdim != null and pdim != null and int(bdim) != int(pdim):
		return false
	var reach := 60.0
	var arena: Variant = _boss.get("arena_radius")
	if arena != null:
		reach = maxf(reach, float(arena) + 20.0)
	if (player as Node3D).global_position.distance_to((_boss as Node3D).global_position) > reach:
		return false
	if _grace <= 0.0 and _boss.has_method("is_engaged") and not _boss.call("is_engaged"):
		return false
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(640, 74)
	UiContext.on("boss_engaged", _on_engaged)
	UiContext.on("boss_health_changed", _on_health)
	UiContext.on("boss_defeated", _on_defeated)
	UiContext.on("boss_disengaged", _on_disengaged)


func _on_engaged(boss: Node, display_name: String) -> void:
	_boss = boss
	_name = display_name
	_phase = 1
	_visible_target = true
	_defeated_timer = 0.0
	_grace = 2.0
	if boss != null:
		var h: Variant = boss.get("health")
		var mx: Variant = boss.get("max_health")
		if h != null and mx != null:
			_health = float(h)
			_max = maxf(float(mx), 1.0)
		# A wounded boss re-engages in the phase it was left in.
		var ph: Variant = boss.get("phase")
		if ph != null:
			_phase = clampi(int(ph), 1, 3)
	_shown = _health / _max
	_trail = _shown


## Another boss giving up (one left behind in another arena) must not hide or
## take over the bar of the boss being fought.
func _on_disengaged(boss: Node) -> void:
	if boss != _boss and _boss != null:
		return
	_visible_target = false
	_boss = null


func _on_health(boss: Node, health: float, max_health: float, phase: int) -> void:
	if not BossBar.accepts(_boss, boss):
		return
	if _boss == null and boss != null:
		# Adopt a boss that is being fought (a client that joined mid-fight).
		_boss = boss
		var n: Variant = boss.get("display_name")
		if n != null:
			_name = String(n)
	if health < _health:
		_hit_flash = 1.0
	if phase != _phase:
		_phase_flash = 1.0
	_health = health
	_max = maxf(max_health, 1.0)
	_phase = phase
	_visible_target = true


func _on_defeated(_kind: String, display_name: String) -> void:
	_name = display_name
	_health = 0.0
	_defeated_timer = 3.0


func _process(delta: float) -> void:
	if _defeated_timer > 0.0:
		_defeated_timer -= delta
		if _defeated_timer <= 0.0:
			_visible_target = false
			_boss = null
	elif _boss != null and not is_instance_valid(_boss):
		_visible_target = false
		_boss = null
	_grace = maxf(0.0, _grace - delta)
	if _defeated_timer <= 0.0:
		_near = _player_at_fight()
	_alpha = move_toward(_alpha, 1.0 if (_visible_target and (_near or _defeated_timer > 0.0)) else 0.0, delta * 3.0)
	visible = _alpha > 0.0
	var ratio := clampf(_health / _max, 0.0, 1.0)
	_shown = move_toward(_shown, ratio, delta * 1.5)
	_trail = move_toward(_trail, _shown, delta * 0.35) if _trail > _shown else _shown
	_hit_flash = maxf(0.0, _hit_flash - delta * 4.0)
	_phase_flash = maxf(0.0, _phase_flash - delta * 1.2)
	modulate.a = _alpha
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var title_font := UiTheme.title_font(700)
	var tfs := 22
	var name_text := _name.to_upper()
	var ts := title_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs)
	var name_col := UiTheme.ACCENT_HOT.lerp(Color(1, 1, 1), _phase_flash * 0.6)
	# Ornament lines either side of the name.
	var ny := 22.0
	draw_line(Vector2(0, ny - 7), Vector2((w - ts.x) * 0.5 - 14, ny - 7), UiTheme.BORDER, 1.0)
	draw_line(Vector2((w + ts.x) * 0.5 + 14, ny - 7), Vector2(w, ny - 7), UiTheme.BORDER, 1.0)
	draw_string(title_font, Vector2((w - ts.x) * 0.5, ny), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, name_col)
	var bar := Rect2(0, 32, w, 12)
	draw_rect(bar.grow(2), Color(0, 0, 0, 0.75))
	draw_rect(bar.grow(1), UiTheme.BORDER, false, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * _trail, bar.size.y)), Color(1.0, 0.85, 0.6, 0.85))
	var fill := Rect2(bar.position, Vector2(bar.size.x * _shown, bar.size.y))
	draw_rect(fill, Color(0.62, 0.08, 0.05))
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 4)), Color(0.95, 0.3, 0.15))
	# Phase thresholds at 66% and 33%.
	for t: float in [0.66, 0.33]:
		var x := bar.position.x + bar.size.x * t
		draw_line(Vector2(x, bar.position.y - 3), Vector2(x, bar.end.y + 3), UiTheme.ACCENT_DIM, 1.0)
	if _hit_flash > 0.0:
		draw_rect(fill, Color(1, 1, 1, _hit_flash * 0.25))
	var font := UiTheme.MONO
	var y := 62.0
	if _defeated_timer > 0.0:
		var vt := "— VANQUISHED —"
		var vs := title_font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(title_font, Vector2((w - vs.x) * 0.5, y + 2), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.ACCENT_HOT)
		return
	# Phase pips (left) and numbers (right) share a line but never overlap.
	var x := 0.0
	draw_string(font, Vector2(x, y), "PHASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
	x += 48.0
	for i in 3:
		var on := i < _phase
		var c := Vector2(x + i * 16.0, y - 4)
		var d := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
		if on:
			draw_colored_polygon(d, UiTheme.ACCENT)
		else:
			draw_polyline(d + PackedVector2Array([d[0]]), UiTheme.BORDER, 1.0)
	var phase_label: String = ROMAN[clampi(_phase - 1, 0, 3)]
	draw_string(font, Vector2(x + 52.0, y), phase_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.ACCENT)
	var nums := "%s / %s" % [UiTheme.format_int(ceili(_health)), UiTheme.format_int(roundi(_max))]
	var ns := font.get_string_size(nums, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(w - ns.x, y), nums, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT)


## Health updates are shown for the tracked boss, or (with none tracked) only
## for a boss that is actually engaged - never for one resetting elsewhere.
static func accepts(tracked: Object, boss: Object) -> bool:
	if tracked != null:
		return boss == tracked
	if boss == null:
		return true
	var e: Variant = boss.get("engaged")
	return e == null or bool(e)
