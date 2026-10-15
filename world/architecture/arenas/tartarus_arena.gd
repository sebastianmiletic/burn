class_name TartarusArena
extends RefCounted
## Tartarus (Cerberus): a round fortress pit of black stone. Spiked walls with
## four chained gates (portcullises hung on chains), bridges over the lava moat,
## four bastions crowned with hellfire, Cerberus' broken chains converging on
## the centre, glowing cracks in the floor. Mirrors Battlegrounds.tartarus.

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")

const STONE := Color(0.27, 0.23, 0.24)
const HELLFIRE := Color(1.0, 0.38, 0.12)


static func build(b: ArenaBuild) -> void:
	var c := b.center
	b.params = {"soot": 0.4, "grime": 0.35, "grime_color": Color(0.28, 0.18, 0.15), "ambient": 0.8}
	var k := b.shell
	var d := b.detail
	for kit: K in [k, d]:
		kit.push(Transform3D(Basis.IDENTITY, c))
		kit.ao_floor = 0.0
	var r_in := 29.0
	var r_out := 32.5
	var wall_h := 12.0
	var gap := 2.6 / 30.0   # half-angle of each gateway
	# --- Floor: concentric rings of black stone, glowing cracks, the centre seal.
	k.ao_floor = -INF
	k.mat(K.MARBLE, Color(0.2, 0.17, 0.18), 0.35)
	var r := 3.0
	var ring := 0
	while r < 27.6:
		var w := 2.2
		var n := int(TAU * (r + w * 0.5) / 2.4)
		var off := k.rng.randf() * TAU
		for i in n:
			var a0 := off + TAU * i / n + 0.012
			var a1 := off + TAU * (i + 1) / n - 0.012
			if (i * 7 + ring * 3) % 23 == 0:
				continue   # a missing tile shows the glow below
			var h := k.rng.randf_range(-0.03, 0.02)
			k.vary(0.12)
			k.lathe(PackedVector2Array([Vector2(r + 0.03, -0.3), Vector2(r + 0.03, h), Vector2(r + w - 0.03, h), Vector2(r + w - 0.03, -0.3)]), 3, a0, a1)
		r += w
		ring += 1
	k.mat(K.MARBLE, Color(0.15, 0.13, 0.14), 0.35)
	k.lathe(PackedVector2Array([Vector2(0.0, 0.02), Vector2(3.0, 0.02), Vector2(3.0, -0.3)]), 32)
	# glow bed under the floor (seen through cracks and missing tiles)
	k.mat(K.GLOW, Color(1.0, 0.32, 0.06), 1.0, 1.6)
	k.lathe(PackedVector2Array([Vector2(28.0, -0.32), Vector2(2.9, -0.32)]), 48)
	# Radial lava cracks.
	for i in 9:
		var a := TAU * i / 9.0 + 0.2
		var dir := Vector3(cos(a), 0, sin(a))
		var p := dir * 4.0
		var steps := 10
		for j in steps:
			var q := p + dir * 2.3 + Vector3(-dir.z, 0, dir.x) * k.rng.randf_range(-0.6, 0.6)
			k.mat(K.GLOW, Color(1.0, 0.35, 0.07), 1.0, 2.2)
			k.beam(p + Vector3(0, 0.015, 0), q + Vector3(0, 0.015, 0), 0.22 - j * 0.015, 0.03, 0.0)
			p = q
		b.light(c + dir * 14.0 + Vector3(0, 0.6, 0), Color(1.0, 0.35, 0.08), 1.4, 7.0, 0, 0.2, 0.6)
	k.ao_floor = 0.0
	# Cerberus' broken chains: from three wall anchors to a shattered collar.
	k.mat(K.IRON, Color(1, 1, 1), 1.0)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.35, 0)))
	k.lathe(PackedVector2Array([Vector2(1.6, -0.35), Vector2(2.2, -0.35), Vector2(2.2, 0.35), Vector2(1.6, 0.35)]), 24, 0.3, TAU - 0.5)
	k.pop()
	for i in 3:
		var a := TAU * i / 3.0 + 0.6
		var dir := Vector3(cos(a), 0, sin(a))
		var anchor := dir * (r_in - 0.3) + Vector3(0, 3.0, 0)
		k.mat(K.IRON, Color(1, 1, 1), 1.0)
		k.push(Transform3D(Basis(Vector3.UP, -a), anchor))
		k.box(Vector3.ZERO, Vector3(0.4, 1.2, 1.2), 0.05)
		k.pop()
		d.mat(K.IRON, Color(1, 1, 1), 1.0)
		d.chain(anchor, dir * 14.0 + Vector3(0, 0.12, 0), 0.75, 0.1, 0.0)
		d.chain(dir * 14.0 + Vector3(0, 0.12, 0), dir * 2.3 + Vector3(0, 0.12, 0), 0.75, 0.1, 0.0)
	# --- Spiked ledge and wall ------------------------------------------------------
	var spans: Array = []
	for i in 4:
		var mid := TAU * i / 4.0
		spans.append([mid + gap, mid + TAU / 4.0 - gap])
	for sp: Array in spans:
		var a0 := float(sp[0])
		var a1 := float(sp[1])
		var segs := int((a1 - a0) * r_in / 1.2)
		k.mat(K.CASTLE, STONE, 0.25)
		k.lathe(PackedVector2Array([Vector2(r_in - 1.4, 0.0), Vector2(r_in - 1.4, 1.0), Vector2(r_in, 1.0)]), segs, a0, a1)
		# wall body: battered outer face, inner face, wall-walk
		k.lathe(PackedVector2Array([Vector2(r_out + 1.0, 0.0), Vector2(r_out, 3.0), Vector2(r_out, wall_h), Vector2(r_in, wall_h), Vector2(r_in, 0.0)]), segs, a0, a1)
		k.mat(K.MARBLE, Color(0.16, 0.14, 0.15), 0.3)
		k.lathe(PackedVector2Array([Vector2(r_in - 0.25, 5.8), Vector2(r_in - 0.25, 6.3), Vector2(r_in, 6.4)]), segs, a0, a1)
		k.lathe(PackedVector2Array([Vector2(r_in - 0.3, wall_h - 0.3), Vector2(r_in - 0.3, wall_h + 0.4), Vector2(r_out + 0.3, wall_h + 0.4), Vector2(r_out + 0.3, wall_h - 0.3)]), segs, a0, a1)
		# buttress ribs on the inner face
		var ribs := int((a1 - a0) * r_in / 6.0)
		for j in range(1, ribs):
			var a := lerpf(a0, a1, float(j) / ribs)
			k.mat(K.CASTLE, STONE * Color(1.1, 1.05, 1.05), 0.25)
			k.push(Transform3D(Basis(Vector3.UP, -a + PI / 2.0), Vector3(cos(a), 0, sin(a)) * (r_in - 0.5)))
			k.box(Vector3(0, wall_h * 0.5, 0), Vector3(1.4, wall_h, 1.0), 0.06)
			k.pop()
		# iron spikes on the ledge and the wall top, skulls on some
		var n_sp := int((a1 - a0) * (r_in - 0.7) / 0.9)
		for j in n_sp:
			var a := lerpf(a0, a1, (float(j) + 0.5) / n_sp)
			var dir := Vector3(cos(a), 0, sin(a))
			d.mat(K.IRON, Color(1, 1, 1), 1.0)
			d.spike(dir * (r_in - 0.7) + Vector3(0, 1.0, 0), (Vector3.UP - dir * 0.35).normalized(), 1.3 + 0.3 * sin(j * 2.1), 0.07, 4, j)
			k.mat(K.IRON, Color(1, 1, 1), 1.0)
			if j % 2 == 0:
				k.spike(dir * (r_in + 0.2) + Vector3(0, wall_h + 0.4, 0), (Vector3.UP - dir * 0.25).normalized(), 1.7, 0.1, 4, j)
			if j % 9 == 4:
				d.mat(K.BONE, Color(0.85, 0.8, 0.7), 0.7)
				d.rock(dir * (r_in + 0.15) + Vector3(0, wall_h + 1.55, 0), Vector3(0.22, 0.26, 0.24), 0.1, 2, j)
	# --- Gates: towers flanking each gap, a lintel, the chained portcullis.
	var gates: Array = b.prop.get("gates", [0, 1, 2, 3])
	for i in 4:
		var a := TAU * i / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var mid := dir * ((r_in + r_out) * 0.5)
		for s: float in [-1.0, 1.0]:
			var tp := mid + side * s * 3.6
			P.round_tower(k, tp, 1.7, wall_h + 3.0, false, false, K.CASTLE, STONE * Color(1.1, 1.05, 1.05))
			k.mat(K.IRON, Color(1, 1, 1), 1.0)
			k.spike(tp + Vector3(0, wall_h + 5.1, 0), Vector3.UP, 2.2, 0.2, 5, i)
			P.fire_basin(b, d, tp + Vector3(0, wall_h + 3.0 - 1.85 * 0.6, 0) - dir * 0.0, c + tp + Vector3(0, wall_h + 3.0 - 1.85 * 0.6, 0), 0.6, "hell", K.MARBLE, HELLFIRE, 1 if i % 2 == 0 else 0)
		# lintel over the 5 m gap (cells 8..12)
		k.mat(K.CASTLE, STONE, 0.25)
		k.push(Transform3D(Basis(Vector3.UP, -a + PI / 2.0), mid))
		k.box(Vector3(0, 10.0 + 0.25, 0), Vector3(5.6, 4.5, 3.5), 0.08)
		k.mat(K.MARBLE, Color(0.15, 0.13, 0.14), 0.3)
		k.box(Vector3(0, 7.85, 0), Vector3(6.0, 0.5, 3.8), 0.06)
		# horned skull over the gate
		k.mat(K.BONE, Color(0.82, 0.76, 0.66), 0.7)
		for face: float in [-1.0, 1.0]:
			k.rock(Vector3(0, 10.3, face * 1.85), Vector3(0.75, 0.85, 0.35), 0.12, 2, i * 3)
			for hs: float in [-1.0, 1.0]:
				k.sweep(K.bezier(Vector3(hs * 0.6, 10.8, face * 1.9), Vector3(hs * 1.7, 11.4, face * 2.0), Vector3(hs * 1.8, 12.4, face * 1.9), 6),
						PackedFloat32Array([0.22, 0.19, 0.16, 0.12, 0.09, 0.06, 0.03]), 6)
		k.pop()
		# bridge over the moat
		var bp := dir * 35.25
		k.push(Transform3D(Basis(Vector3.UP, -a + PI / 2.0), bp))
		k.mat(K.CASTLE, STONE * Color(1.1, 1.05, 1.05), 0.25)
		k.box(Vector3(0, -0.6, 0), Vector3(5.4, 1.2, 5.0), 0.05)
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(s * 2.9, 0.5, 0), Vector3(0.5, 1.0, 5.2), 0.05)
			for z: float in [-2.4, 2.4]:
				k.box(Vector3(s * 2.9, 0.9, z), Vector3(0.8, 1.8, 0.8), 0.06)
				k.mat(K.IRON, Color(1, 1, 1), 1.0)
				k.spike(Vector3(s * 2.9, 1.8, z), Vector3.UP, 0.8, 0.1, 4, int(z))
				k.mat(K.CASTLE, STONE * Color(1.1, 1.05, 1.05), 0.25)
		k.pop()
		for s: float in [-1.0, 1.0]:
			d.mat(K.IRON, Color(1, 1, 1), 1.0)
			d.chain(bp + side * s * 2.9 - dir * 2.4 + Vector3(0, 1.6, 0), bp + side * s * 2.9 + dir * 2.4 + Vector3(0, 1.6, 0), 0.45, 0.05, 0.5)
		# the portcullis on chains
		var g := K.new(90 + i)
		g.mat(K.IRON, Color(1, 1, 1), 1.0)
		var w := 5.0
		var h := 7.2
		var pc := P.portcullis(w, h, 90 + i)
		g = pc
		g.mat(K.IRON, Color(1, 1, 1), 1.0)
		for s: float in [-1.0, 1.0]:
			g.chain(Vector3(s * 2.0, h, 0), Vector3(s * 2.0, h + 6.0, 0), 0.45, 0.06, 0.0)
		var gate_index := int(gates[i]) if i < gates.size() else i
		var basis := Basis(Vector3.UP, -a + PI / 2.0)
		b.gate(gate_index, g, Transform3D(basis, c + dir * 31.0), "drop", 7.6)
	# --- Moat edges -------------------------------------------------------------------
	k.mat(K.DARK, Color(0.3, 0.26, 0.26), 0.4)
	for rr: float in [33.0, 37.6]:
		k.lathe(PackedVector2Array([Vector2(rr - 0.35, -0.6), Vector2(rr - 0.35, 0.2), Vector2(rr + 0.35, 0.2), Vector2(rr + 0.35, -0.6)]), 96)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		b.light(c + Vector3(cos(a), 0, sin(a)) * 35.3 + Vector3(0, 1.0, 0), Color(1.0, 0.33, 0.07), 2.6, 9.0, 0, 0.2, 0.8)
	# --- Bastions -----------------------------------------------------------------------
	for bs: Vector3 in b.prop["bastions"]:
		P.round_tower(k, bs, 4.6, 18.0, false, false, K.CASTLE, STONE)
		k.mat(K.IRON, Color(1, 1, 1), 1.0)
		for j in 10:
			var a := TAU * j / 10.0
			k.spike(bs + Vector3(cos(a) * 4.6, 20.0, sin(a) * 4.6), (Vector3(cos(a), 1.6, sin(a))).normalized(), 2.0, 0.16, 4, j)
		P.fire_basin(b, k, bs + Vector3(0, 18.0, 0), c + bs + Vector3(0, 18.0, 0), 1.4, "hell", K.MARBLE, HELLFIRE, 0)
	# Bone piles against the inner wall.
	for i in 7:
		var a := k.rng.randf() * TAU
		if fmod(a + gap * 2.0, TAU / 4.0) < gap * 4.0:
			continue
		_bones(d, Vector3(cos(a), 0, sin(a)) * (r_in - 3.0), i)


static func _bones(d: K, at: Vector3, seed_value: int) -> void:
	d.mat(K.BONE, Color(0.84, 0.79, 0.68), 0.7)
	for j in 9:
		var a := d.rng.randf() * TAU
		var p := at + Vector3(cos(a), 0, sin(a)) * d.rng.randf_range(0.0, 1.4)
		var dir := Vector3(d.rng.randf_range(-1, 1), d.rng.randf_range(-0.2, 0.3), d.rng.randf_range(-1, 1)).normalized()
		var l := d.rng.randf_range(0.5, 1.0)
		d.sweep(PackedVector3Array([p + Vector3(0, 0.1, 0), p + dir * l * 0.5 + Vector3(0, 0.1, 0), p + dir * l + Vector3(0, 0.1, 0)]), PackedFloat32Array([0.07, 0.045, 0.07]), 5)
	for j in 3:
		var p := at + Vector3(d.rng.randf_range(-0.8, 0.8), 0.18, d.rng.randf_range(-0.8, 0.8))
		d.rock(p, Vector3(0.2, 0.22, 0.24), 0.1, 2, seed_value * 5 + j)
