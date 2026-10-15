class_name RyftArena
extends RefCounted
## Crystal arenas on the Ryft's floating isles (Battlegrounds.ryft_lair):
## a dais of dark ryft stone with a glowing rune ring, crystal pillars, drifting
## shards. Variant 1 (Broken Observatory, Prism Sentinel): the ribs of a fallen
## dome and an armillary ring. Variant 2 (Crown of the Ryft, Void Sovereign): a
## crown of towering crystal spires.

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")

const STONE := Color(0.32, 0.29, 0.38)
const PRISM := Color(0.55, 0.85, 1.0)
const VOID := Color(0.75, 0.4, 1.0)


static func build(b: ArenaBuild) -> void:
	var pr := b.prop
	var variant := int(pr.get("variant", 1))
	var glow := PRISM if variant == 1 else VOID
	var r := float(pr.get("r", 15.0))
	b.params = {"grime": 0.3, "grime_color": Color(0.3, 0.26, 0.36), "outdoor": 1.0}
	var k := b.shell
	var d := b.detail
	for kit: K in [k, d]:
		kit.push(Transform3D(Basis.IDENTITY, b.center))
		kit.ao_floor = 0.0
	var rng := k.rng
	# Dais: rings of dark stone tiles, a raised rim, a rune ring and the inner seal.
	k.ao_floor = -INF
	var rr := float(pr.get("inner", 2.0))
	var ring := 0
	while rr < r:
		var w := minf(2.2, r - rr)
		var n := int(TAU * (rr + w * 0.5) / 2.2)
		var off := rng.randf() * TAU
		for i in n:
			var a0 := off + TAU * i / n + 0.012
			var a1 := off + TAU * (i + 1) / n - 0.012
			k.mat(K.MARBLE, STONE * (1.0 + rng.randf_range(-0.12, 0.1)), 0.4)
			var h := rng.randf_range(-0.03, 0.02)
			k.lathe(PackedVector2Array([Vector2(rr + 0.03, -0.5), Vector2(rr + 0.03, h), Vector2(rr + w - 0.03, h), Vector2(rr + w - 0.03, -0.5)]), 3, a0, a1)
		rr += w
		ring += 1
	k.ao_floor = 0.0
	k.mat(K.CARVED, STONE * 1.15, 0.4)
	k.lathe(PackedVector2Array([Vector2(r + 1.2, -3.0), Vector2(r + 0.4, 0.0), Vector2(r + 0.4, 0.45), Vector2(r - 0.2, 0.45), Vector2(r - 0.2, 0.0)]), 64, 0.0, TAU, 0.03)
	k.mat(K.GLOW, glow, 1.0, 2.4)
	for rad: float in [r - 2.0, float(pr.get("inner", 2.0)) + 0.4]:
		k.lathe(PackedVector2Array([Vector2(rad - 0.12, -0.01), Vector2(rad - 0.1, 0.02), Vector2(rad + 0.1, 0.02), Vector2(rad + 0.12, -0.01)]), 64)
	for i in 24:
		var a := TAU * i / 24.0
		var dir := Vector3(cos(a), 0, sin(a))
		var tan := Vector3(-dir.z, 0, dir.x)
		var c := dir * (r - 3.0)
		k.beam(c - tan * 0.35 + Vector3(0, 0.015, 0), c + tan * 0.35 + dir * 0.4 + Vector3(0, 0.015, 0), 0.06, 0.02, 0.0)
		k.beam(c + Vector3(0, 0.015, 0), c - dir * 0.5 + Vector3(0, 0.015, 0), 0.06, 0.02, 0.0)
	b.light(b.center + Vector3(0, 1.5, -10.0), glow, 2.4, 14.0, 0, 0.1, 1.0)
	# Crystal pillars on the ring (collision cells), each a cluster of shards.
	for pp: Vector3 in pr["pillars"]:
		_cluster(k, pp, rng.randf_range(5.0, 9.0) if variant == 1 else rng.randf_range(8.0, 14.0), glow, int(pp.x * 31.0 + pp.z * 7.0))
		b.light(b.center + pp + Vector3(0, 2.5, 0), glow, 2.2, 10.0, 0, 0.12, 1.0)
	# Shards drifting above the arena (no collision).
	d.mat(K.GLOW, glow, 1.0, 1.6)
	for i in 14:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(r + 2.0, r + 9.0) + Vector3(0, rng.randf_range(3.0, 12.0), 0)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		d.spike(p - dir * 0.6, dir, rng.randf_range(0.8, 2.2), rng.randf_range(0.12, 0.3), 5, i)
		d.spike(p - dir * 0.6, -dir, rng.randf_range(0.4, 1.0), rng.randf_range(0.12, 0.3), 5, i + 50)
	if variant == 1:
		_observatory(b, k, d, r, glow)
	else:
		_crown(b, k, d, r, glow)


static func _cluster(k: K, at: Vector3, h: float, glow: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.mat(K.TRI + K.DARK, STONE, 0.5)
	k.rock(at + Vector3(0, 0.2, 0), Vector3(1.6, 0.7, 1.5), 0.35, 2, seed_value, 0.5, 0.3)
	k.mat(K.TRI + K.SNOW, glow, 0.6, 1.3)
	k.spike(at, Vector3(rng.randf_range(-0.1, 0.1), 1, rng.randf_range(-0.1, 0.1)).normalized(), h, 0.75, 6, seed_value)
	for i in 6:
		var dir := Vector3(rng.randf_range(-0.7, 0.7), 1.0, rng.randf_range(-0.7, 0.7)).normalized()
		k.spike(at + Vector3(rng.randf_range(-0.7, 0.7), 0.1, rng.randf_range(-0.7, 0.7)), dir, h * rng.randf_range(0.25, 0.6), rng.randf_range(0.25, 0.5), 6, seed_value + i)


static func _observatory(b: ArenaBuild, k: K, d: K, r: float, glow: Color) -> void:
	# Fallen dome: broken stone ribs arching over the far side, an armillary ring.
	k.mat(K.CARVED, STONE * 1.2, 0.35)
	for i in 5:
		var a := PI + 0.4 + i * 0.35
		var dir := Vector3(cos(a), 0, sin(a))
		var path := K.bezier(dir * (r + 0.5), dir * (r * 0.6) + Vector3(0, 16.0, 0), dir * (r * 0.15) + Vector3(0, 18.0, 0), 14)
		path = path.slice(0, 8 + (i % 3) * 2)
		var prev := path[0]
		for j in range(1, path.size()):
			k.beam(prev, path[j], 0.8, 0.6, 0.06)
			prev = path[j]
	b.light(b.center + Vector3(0, 12.0, 0), glow, 3.0, 22.0, 1, 0.1, 1.5)


static func _crown(b: ArenaBuild, k: K, d: K, r: float, glow: Color) -> void:
	# Towering crystal spires leaning outwards like the points of a crown.
	for i in 5:
		var a := TAU * i / 5.0 + 0.6
		var at := Vector3(cos(a), 0, sin(a)) * (r + 2.5)
		_cluster(k, at, 18.0 + (i % 2) * 6.0, glow, 700 + i)
	k.mat(K.GLOW, glow, 1.0, 3.0)
	k.rock(Vector3(0, 16.0, 0), Vector3(1.4, 1.4, 1.4), 0.25, 2, 9, 1.0, 0.5)
	b.light(b.center + Vector3(0, 14.0, 0), glow, 3.5, 24.0, 1, 0.1, 1.5)
