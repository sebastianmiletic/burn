class_name HadesArena
extends RefCounted
## Hades' places: the Throne of Hades (underworld throne hall) and the Gates
## of Hades (the monumental portal in the cavern under the Cinder Crater).
## Geometry mirrors Battlegrounds.throne / gates_of_hades (centre-relative cells).

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")

const BLACK := Color(0.16, 0.14, 0.16)
const BASALT := Color(0.36, 0.3, 0.3)
const SOUL := Color(0.35, 0.85, 1.0)


static func throne(b: ArenaBuild) -> void:
	var c := b.center
	b.params = {"soot": 0.25, "grime": 0.3, "grime_color": Color(0.25, 0.18, 0.16), "ambient": 0.8}
	var k := b.shell
	var d := b.detail
	for kit: K in [k, d]:
		kit.push(Transform3D(Basis.IDENTITY, c))
		kit.ao_floor = 0.0
	# --- Floor: polished black marble, a red runner with gold borders, the seal.
	k.ao_floor = -INF
	k.mat(K.MARBLE, Color(0.16, 0.14, 0.16), 0.3)
	var skip := func(x: float, z: float) -> bool:
		return absf(x) < 4.2 and z > -32.0 and z < 21.0
	k.flagstones(-20.5, -32.5, 20.5, 21.5, 0.0, 2.4, 0.04, 0.4, 0.0, skip)
	for side: float in [-1.0, 1.0]:
		k.flagstones(minf(side * 22.6, side * 24.5), -32.5, maxf(side * 22.6, side * 24.5), 32.5, 0.0, 1.6, 0.04, 0.4)
	k.mat(K.CLAY, Color(0.34, 0.06, 0.05), 0.5)
	k.flagstones(-4.0, -32.5, 4.0, 21.5, 0.0, 2.0, 0.03, 0.4)
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	for x: float in [-4.15, 4.15]:
		k.box(Vector3(x, -0.02, -5.5), Vector3(0.3, 0.06, 54.0), 0.01)
	# The seal around the boss's place.
	_seal(k, Vector3(0, 0.01, 12.0), 7.0)
	# Forecourt beyond the gate.
	k.mat(K.MARBLE, Color(0.2, 0.17, 0.18), 0.3)
	k.flagstones(-24.5, -50.5, 24.5, -42.5, 0.0, 2.2, 0.04, 0.4)
	k.flagstones(-24.5, -37.5, 24.5, -35.5, 0.0, 2.2, 0.04, 0.4)
	k.flagstones(-5.5, -42.5, 5.5, -37.5, 0.0, 1.8, 0.04, 0.4)
	k.ao_floor = 0.0
	# Lava channel kerbs.
	k.mat(K.DARK, BASALT, 0.4)
	for side: float in [-1.0, 1.0]:
		for x: float in [20.75, 22.25 + 0.5]:
			k.box(Vector3(side * x, -0.25, 0), Vector3(0.5, 0.7, 65.0), 0.06)
	for side: float in [-1.0, 1.0]:
		for z in range(-30, 31, 6):
			b.light(c + Vector3(side * 21.5, 0.6, z), Color(1.0, 0.32, 0.08), 1.8, 7.0, 0, 0.15, 0.6)
	# --- Walls ------------------------------------------------------------------------
	var wall := Color(0.3, 0.26, 0.27)
	k.mat(K.CASTLE, wall, 0.25)
	k.box(Vector3(26.0, 12.0, 0), Vector3(3.0, 24.0, 71.0), 0.0)
	k.box(Vector3(-26.0, 12.0, 0), Vector3(3.0, 24.0, 71.0), 0.0)
	k.box(Vector3(0, 14.0, 34.0), Vector3(55.0, 28.0, 3.0), 0.0)
	# gate wall with its opening
	k.box(Vector3(-16.75, 10.0, -34.0), Vector3(21.5, 20.0, 3.0), 0.0)
	k.box(Vector3(16.75, 10.0, -34.0), Vector3(21.5, 20.0, 3.0), 0.0)
	k.box(Vector3(0, 14.25, -34.0), Vector3(12.0, 11.5, 3.0), 0.0)
	# forecourt walls
	k.box(Vector3(26.0, 4.0, -43.0), Vector3(3.0, 8.0, 15.0), 0.0)
	k.box(Vector3(-26.0, 4.0, -43.0), Vector3(3.0, 8.0, 15.0), 0.0)
	# Pilasters, niches with statues and spiked cresting on the side walls.
	for side: float in [-1.0, 1.0]:
		var face := side * 24.5
		k.mat(K.CASTLE, wall * Color(1.1, 1.05, 1.05), 0.25)
		k.moulding(Vector3(face, 0, 34.5), Vector3(face, 0, -32.5), Vector3(-side, 0, 0), PackedVector2Array([Vector2(0.5, 0), Vector2(0.45, 0.4), Vector2(0.0, 1.6)]))
		for z in range(-26, 27, 9):
			k.box(Vector3(face - side * 0.45, 12.0, z), Vector3(0.9, 24.0, 2.2), 0.05)
			k.box(Vector3(face - side * 0.7, 23.0, z), Vector3(1.4, 2.0, 2.6), 0.08)
		for z in range(-21, 23, 9):
			# dark niche with a hooded guardian
			k.mat(K.DARK, Color(0.06, 0.05, 0.05), 0.4)
			k.box(Vector3(face + side * 0.02, 8.5, float(z) + 0.5), Vector3(0.05, 13.0, 4.6), 0.0)
			k.mat(K.CASTLE, wall * Color(1.15, 1.1, 1.1), 0.3)
			k.push(Transform3D(Basis(Vector3.UP, -side * PI / 2.0), Vector3(face, 15.0, float(z) + 0.5)))
			k.arch(4.6, 0.0, 0.6, 0.6, 9, 0.25)
			k.pop()
			P.statue(k, Vector3(face - side * 1.4, 1.2, float(z) + 0.5), -side * PI / 2.0, 11.0, K.TRI + K.DARK, Color(0.42, 0.38, 0.4), false, true)
		k.mat(K.IRON, Color(1, 1, 1), 1.0)
		var z0 := -33.0
		while z0 < 33.0:
			k.spike(Vector3(face + side * 0.8, 24.0, z0), Vector3.UP, 1.4, 0.12, 4, int(z0))
			z0 += 1.6
	# Back wall: rose window of souls above the throne.
	_rose(b, k, Vector3(0, 19.0, 32.4), 6.5)
	# --- Columns ----------------------------------------------------------------------
	var cols: Array = b.prop["columns"]
	for cp: Vector3 in cols:
		_column(b, k, d, cp)
	# architraves along the colonnades and arches to the walls
	k.mat(K.CASTLE, wall * Color(1.1, 1.05, 1.05), 0.25)
	for side: float in [-1.0, 1.0]:
		k.box(Vector3(side * 14.0, 23.3, -3.5), Vector3(2.8, 1.6, 47.0), 0.08)
		k.moulding(Vector3(side * 14.0 - 1.4, 22.5, 20.0), Vector3(side * 14.0 - 1.4, 22.5, -27.0), Vector3(-1, 0, 0), PackedVector2Array([Vector2(0, 0), Vector2(0.25, 0.2), Vector2(0.25, 0.5)]))
		for z in range(-26, 27, 9):
			k.push(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(side * 19.25, 15.5, float(z))))
			k.arch(9.6, 0.0, 1.1, 1.6, 13, 0.0)
			k.pop()
	# --- Gate -----------------------------------------------------------------------------
	_gate(b, k, d)
	# --- Dais and throne ------------------------------------------------------------
	_dais(b, k, d)
	# --- River of souls and the bridge ----------------------------------------------
	var river := b.flow("souls", {"deep_color": Color(0.01, 0.03, 0.05), "glow_color": Color(0.1, 0.45, 0.75), "hot_color": Color(0.6, 1.0, 1.0),
			"energy": 2.4, "speed": 0.35, "crust": 0.2, "wisps": 1.6})
	river.push(Transform3D(Basis.IDENTITY, c))
	river.raw = true
	for seg: Array in [[-27.5, -5.5], [5.5, 27.5]]:
		var x0 := float(seg[0])
		var x1 := float(seg[1])
		var n := int((x1 - x0) / 1.0)
		for i in n:
			var xa := x0 + (x1 - x0) * i / n
			var xb := x0 + (x1 - x0) * (i + 1) / n
			river.quad(Vector3(xa, -0.35, -42.5), Vector3(xb, -0.35, -42.5), Vector3(xb, -0.35, -37.5), Vector3(xa, -0.35, -37.5),
					Vector2(0, xa), Vector2(0, xb), Vector2(1, xb), Vector2(1, xa), Vector3.UP)
	k.mat(K.DARK, BASALT, 0.4)
	for z: float in [-42.75, -37.25]:
		k.box(Vector3(-16.5, -0.5, z), Vector3(22.0, 1.2, 0.5), 0.05)
		k.box(Vector3(16.5, -0.5, z), Vector3(22.0, 1.2, 0.5), 0.05)
	k.mat(K.DARK, Color(0.05, 0.05, 0.06), 0.4)
	k.box(Vector3(-16.5, -1.02, -40.0), Vector3(22.0, 0.05, 5.0), 0.0)
	k.box(Vector3(16.5, -1.02, -40.0), Vector3(22.0, 0.05, 5.0), 0.0)
	# culverts where the river leaves the forecourt
	for side: float in [-1.0, 1.0]:
		k.mat(K.DARK, Color(0.02, 0.02, 0.02), 0.5)
		k.box(Vector3(side * 24.48, 0.4, -40.0), Vector3(0.05, 2.6, 5.0), 0.0)
		k.mat(K.CASTLE, wall * Color(1.15, 1.1, 1.1), 0.3)
		k.push(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(side * 24.5, -0.6, -40.0)))
		k.arch(5.0, 0.0, 0.7, 0.8, 9)
		k.pop()
	# bridge parapets with soul lamps
	k.mat(K.CASTLE, wall * Color(1.1, 1.05, 1.05), 0.25)
	for side: float in [-1.0, 1.0]:
		k.box(Vector3(side * 5.75, 0.55, -40.0), Vector3(0.5, 1.1, 6.0), 0.06)
		for z: float in [-43.0, -37.0]:
			k.box(Vector3(side * 5.75, 1.0, z), Vector3(0.9, 2.0, 0.9), 0.06)
			k.mat(K.IRON, Color(1, 1, 1), 1.0)
			k.lathe(PackedVector2Array([Vector2(0.1, 2.0), Vector2(0.38, 2.25), Vector2(0.42, 2.45)]), 10)
			b.flame(c + Vector3(side * 5.75, 2.3, z), 1.0, "soul")
			k.mat(K.CASTLE, wall * Color(1.1, 1.05, 1.05), 0.25)
		b.light(c + Vector3(side * 5.75, 3.0, -40.0), SOUL, 2.2, 10.0, 0, 0.2, 1.2)
	for x in range(-24, 25, 8):
		b.light(c + Vector3(x, 0.5, -40.0), Color(0.3, 0.8, 1.0), 1.4, 7.0, 0, 0.1, 1.5)


## Inlaid seal: gold rings and glowing runes.
static func _seal(k: K, at: Vector3, r: float) -> void:
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	for rr: float in [r, r - 0.6, r * 0.45]:
		k.lathe(PackedVector2Array([Vector2(rr - 0.12, at.y), Vector2(rr - 0.1, at.y + 0.03), Vector2(rr + 0.1, at.y + 0.03), Vector2(rr + 0.12, at.y)]), 48)
	k.push(Transform3D(Basis.IDENTITY, Vector3(at.x, 0, at.z)))
	k.mat(K.GLOW, Color(1.0, 0.25, 0.08), 1.0, 2.5)
	var runes := 24
	for i in runes:
		var a := TAU * i / runes
		var dir := Vector3(cos(a), 0, sin(a))
		var tan := Vector3(-dir.z, 0, dir.x)
		var p := dir * (r - 0.3)
		var seed := i * 7
		for j in 3:
			var a0 := p + tan * (float((seed + j * 3) % 5) - 2.0) * 0.07 + dir * (float((seed + j) % 3) - 1.0) * 0.1
			var a1 := a0 + (tan * float((seed + j) % 3 - 1) + dir * 1.0).normalized() * 0.22
			k.beam(a0 + Vector3(0, 0.02, 0), a1 + Vector3(0, 0.02, 0), 0.035, 0.02, 0.0)
	# star of lines in the inner circle
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * (i + 2) / 5.0
		k.beam(Vector3(cos(a0), 0.02, sin(a0)) * r * 0.45, Vector3(cos(a1), 0.02, sin(a1)) * r * 0.45, 0.06, 0.02, 0.0)
	k.pop()


static func _column(b: ArenaBuild, k: K, d: K, at: Vector3) -> void:
	k.push_at(at)
	k.mat(K.MARBLE, Color(0.18, 0.16, 0.18), 0.3)
	k.box(Vector3(0, 0.5, 0), Vector3(5.2, 1.0, 5.2), 0.08)
	k.box(Vector3(0, 1.4, 0), Vector3(4.4, 0.8, 4.4), 0.08)
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	k.lathe(PackedVector2Array([Vector2(2.3, 1.8), Vector2(2.35, 1.95), Vector2(2.1, 2.2), Vector2(1.95, 2.35)]), 28)
	k.mat(K.MARBLE, Color(0.14, 0.12, 0.14), 0.25)
	k.column(Vector3(0, 2.2, 0), 19.8, 1.8, "fluted", 0.0, 28)
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	for y: float in [8.0, 15.0]:
		k.lathe(PackedVector2Array([Vector2(1.78, y - 0.3), Vector2(1.92, y - 0.2), Vector2(1.92, y + 0.2), Vector2(1.78, y + 0.3)]), 28)
	k.lathe(PackedVector2Array([Vector2(1.75, 20.4), Vector2(2.4, 21.0), Vector2(2.6, 21.6), Vector2(2.4, 21.9)]), 28)
	k.pop()
	# soul fire bowls on the plinth corners facing the nave
	var nave := Vector3(-signf(at.x), 0, 0)
	for s: float in [-1.0, 1.0]:
		var bp := at + nave * 1.9 + Vector3(0, 1.8, s * 1.9)
		d.push_at(bp)
		d.mat(K.IRON, Color(1, 1, 1), 1.0)
		d.lathe(PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.45, 0.25), Vector2(0.55, 0.45), Vector2(0.48, 0.48)]), 12)
		d.pop()
		b.flame(b.center + bp + Vector3(0, 0.35, 0), 1.3, "soul")
	b.light(b.center + at + nave * 2.6 + Vector3(0, 3.0, 0), SOUL, 3.0, 13.0, 0, 0.25, 1.5)


static func _rose(b: ArenaBuild, k: K, at: Vector3, r: float) -> void:
	k.push(Transform3D(Basis.IDENTITY, at))
	k.mat(K.GLOW, Color(0.25, 0.75, 1.0), 1.0, 2.2)
	k.box(Vector3(0, 0, 0.2), Vector3(r * 2.0, r * 2.0, 0.1), 0.0)
	k.mat(K.MARBLE, Color(0.16, 0.14, 0.16), 0.3)
	# tracery: rings and spokes in front of the glowing panes
	k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO))
	for rr: float in [r, r * 0.62, r * 0.22]:
		k.lathe(PackedVector2Array([Vector2(rr - 0.35, -0.4), Vector2(rr + 0.35, -0.4), Vector2(rr + 0.35, 0.2), Vector2(rr - 0.35, 0.2)]), 40)
	k.pop()
	for i in 12:
		var a := TAU * i / 12.0
		k.beam(Vector3(cos(a), sin(a), 0) * r * 0.22, Vector3(cos(a), sin(a), 0) * r, 0.3, 0.6, 0.03, Vector3.FORWARD)
	# square frame filling the wall around the circle
	k.mat(K.CASTLE, Color(0.33, 0.29, 0.3), 0.25)
	var frame := PackedVector2Array([Vector2(-r - 1.2, -r - 1.2), Vector2(r + 1.2, -r - 1.2), Vector2(r + 1.2, r + 1.2), Vector2(-r - 1.2, r + 1.2)])
	for i in 4:
		var a := frame[i]
		var e := frame[(i + 1) % 4]
		k.beam(Vector3(a.x, a.y, -0.3), Vector3(e.x, e.y, -0.3), 0.7, 0.8, 0.05, Vector3.FORWARD)
	k.pop()
	b.light(b.center + at + Vector3(0, 0, -3.0), Color(0.35, 0.85, 1.0), 3.0, 22.0, 0, 0.1, 2.0)


static func _gate(b: ArenaBuild, k: K, d: K) -> void:
	var z := -34.0
	var wall := Color(0.34, 0.3, 0.31)
	for face: float in [-1.0, 1.0]:
		var fz := z + face * 1.55
		# jambs with gold capitals
		for s: float in [-1.0, 1.0]:
			k.mat(K.MARBLE, Color(0.15, 0.13, 0.15), 0.3)
			k.box(Vector3(s * 7.3, 4.0, fz), Vector3(1.6, 8.0, 0.6), 0.06)
			k.mat(K.GOLD, Color(1, 1, 1), 1.0)
			k.box(Vector3(s * 7.3, 8.2, fz), Vector3(1.9, 0.4, 0.8), 0.05)
		# lintel and a pointed relief arch with a tympanum above the opening
		k.mat(K.MARBLE, Color(0.15, 0.13, 0.15), 0.3)
		k.box(Vector3(0, 8.9, fz), Vector3(16.0, 1.4, 0.7), 0.06)
		k.mat(K.CASTLE, wall * Color(1.15, 1.1, 1.1), 0.3)
		k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, fz)))
		k.arch(14.6, 9.6, 1.2, 0.8, 17, 0.4)
		k.pop()
		if face < 0.0:
			# Hades' sigil on the outer tympanum: a horned skull with burning eyes.
			k.mat(K.TRI + K.DARK, Color(0.5, 0.45, 0.42), 0.35)
			k.rock(Vector3(0, 12.4, fz - 0.3), Vector3(1.6, 1.8, 0.6), 0.1, 2, 31)
			k.rock(Vector3(0, 11.0, fz - 0.4), Vector3(1.0, 0.6, 0.45), 0.1, 2, 32)
			for s: float in [-1.0, 1.0]:
				var hp := K.bezier(Vector3(s * 1.2, 13.4, fz - 0.4), Vector3(s * 3.4, 14.6, fz - 0.6), Vector3(s * 3.6, 16.6, fz - 0.4), 8)
				var hr := PackedFloat32Array()
				for i in hp.size():
					hr.append(lerpf(0.45, 0.05, float(i) / (hp.size() - 1)))
				k.sweep(hp, hr, 8)
			k.mat(K.GLOW, Color(1.0, 0.3, 0.06), 1.0, 4.0)
			for s: float in [-1.0, 1.0]:
				k.rock(Vector3(s * 0.6, 12.5, fz - 0.75), Vector3(0.32, 0.26, 0.15), 0.05, 1, 33)
			b.light(b.center + Vector3(0, 12.5, fz - 2.0), Color(1.0, 0.35, 0.1), 2.0, 10.0, 0, 0.3, 1.0)
		# braziers flanking the gate
		for s: float in [-1.0, 1.0]:
			P.fire_basin(b, k, Vector3(s * 10.5, 0, fz + face * 2.0), b.center + Vector3(s * 10.5, 0, fz + face * 2.0), 0.9, "hell", K.MARBLE, Color(1.0, 0.4, 0.15), 1 if face < 0.0 else 0)
	# portcullis grooves
	k.mat(K.DARK, Color(0.03, 0.03, 0.03), 0.5)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 6.47, 4.0, z), Vector3(0.08, 8.0, 0.4), 0.0)
	var g := K.new(77)
	g.mat(K.IRON, Color(1, 1, 1), 1.0)
	var bars := 22
	for i in bars + 1:
		var x := -6.5 + 13.0 * float(i) / bars
		g.box(Vector3(x, 4.2, 0), Vector3(0.14, 8.4, 0.14), 0.02, false)
		g.spike(Vector3(x, 0.05, 0), Vector3.DOWN, 0.6, 0.1, 4, i)
	for j in 6:
		var y := 0.8 + j * 1.45
		g.box(Vector3(0, y, 0), Vector3(13.2, 0.16, 0.22), 0.02, false)
		for i in range(0, bars + 1, 2):
			var x := -6.5 + 13.0 * float(i) / bars
			g.spike(Vector3(x, y, 0.1), Vector3.BACK, 0.35, 0.07, 4, i + j)
	b.gate(int(b.prop.get("gate", 0)), g, Transform3D(Basis.IDENTITY, b.center + Vector3(0, 0, z)), "drop", 8.6)


static func _dais(b: ArenaBuild, k: K, d: K) -> void:
	# Four tiers (1 m collision cells), each drawn as two 0.5 m steps.
	for step in 4:
		var hx := 9.5 - step * 2.0
		var z0 := 21.5 + step
		k.mat(K.MARBLE, Color(0.17, 0.15, 0.17), 0.3)
		k.box(Vector3(0, step + 0.25, (z0 + 32.5) * 0.5), Vector3(hx * 2.0, 0.5, 32.5 - z0), 0.03)
		k.box(Vector3(0, step + 0.75, (z0 + 0.5 + 32.5) * 0.5), Vector3(hx * 2.0 - 0.4, 0.5, 32.5 - z0 - 0.5), 0.03)
		k.mat(K.GOLD, Color(1, 1, 1), 1.0)
		k.box(Vector3(0, step + 0.5, z0 + 0.02), Vector3(hx * 2.0, 0.06, 0.06), 0.01)
		k.box(Vector3(0, step + 1.0, z0 + 0.52), Vector3(hx * 2.0 - 0.4, 0.06, 0.06), 0.01)
	# The throne: black stone and gold, a crown of spikes, a ring of soul light.
	var t := Vector3(0, 4.0, 30.5)
	k.push(Transform3D(Basis.IDENTITY, t))
	k.mat(K.MARBLE, Color(0.12, 0.1, 0.12), 0.3)
	k.box(Vector3(0, 0.5, -0.3), Vector3(5.0, 1.0, 3.0), 0.08)
	k.box(Vector3(0, 6.5, 1.25), Vector3(6.4, 13.0, 1.4), 0.1)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 2.75, 1.6, -0.3), Vector3(0.7, 1.4, 3.0), 0.08)
		k.mat(K.BONE, Color(0.85, 0.8, 0.7), 0.7)
		k.rock(Vector3(s * 2.75, 2.45, -1.75), Vector3(0.42, 0.45, 0.48), 0.12, 2, 40 + int(s))
		k.mat(K.MARBLE, Color(0.12, 0.1, 0.12), 0.3)
	k.mat(K.CLOTH, Color(0.32, 0.04, 0.05), 1.0)
	k.box(Vector3(0, 1.1, -0.4), Vector3(4.0, 0.25, 2.4), 0.12)
	k.box(Vector3(0, 3.6, 0.48), Vector3(4.2, 4.6, 0.2), 0.08)
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	k.box(Vector3(0, 13.1, 1.25), Vector3(6.8, 0.3, 1.6), 0.05)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 3.25, 6.5, 1.25), Vector3(0.18, 13.0, 1.5), 0.03)
	for i in 9:
		var a := lerpf(-1.1, 1.1, float(i) / 8.0)
		var dir := Vector3(sin(a), cos(a), 0)
		k.spike(Vector3(sin(a) * 2.6, 13.0 + cos(a) * 0.4, 1.25), dir, 2.0 + (1.6 if i == 4 else 0.0) - absf(a) * 0.6, 0.22, 5, i)
	k.mat(K.GLOW, SOUL, 1.0, 3.0)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 9.0, 2.1)))
	k.lathe(PackedVector2Array([Vector2(3.6, -0.15), Vector2(3.9, -0.15), Vector2(3.9, 0.15), Vector2(3.6, 0.15)]), 40)
	k.pop()
	k.pop()
	# Giant soul braziers flanking the throne.
	for s: float in [-1.0, 1.0]:
		var at := Vector3(s * 6.5, 4.0, 27.0)
		P.fire_basin(b, k, at, b.center + at, 1.25, "soul", K.MARBLE, SOUL, 2)


# --- Gates of Hades ------------------------------------------------------------------

static func gates(b: ArenaBuild) -> void:
	var c := b.center
	b.params = {"soot": 0.35, "grime": 0.35, "grime_color": Color(0.25, 0.2, 0.18), "ambient": 0.5}
	var k := b.shell
	var d := b.detail
	for kit: K in [k, d]:
		kit.push(Transform3D(Basis.IDENTITY, c))
		kit.ao_floor = 0.0
	var gz := float(b.prop["gate_z"])
	var wall := Color(0.32, 0.27, 0.27)
	# Paving: forecourt and avenue.
	k.ao_floor = -INF
	k.mat(K.CASTLE, Color(0.42, 0.36, 0.34), 0.3)
	k.flagstones(-13.5, gz - 4.5, 13.5, gz + 9.5, 0.0, 1.8, 0.05, 0.6, 0.04)
	k.flagstones(-8.5, gz + 9.5, 8.5, 24.5, 0.0, 1.8, 0.05, 0.6, 0.08)
	k.ao_floor = 0.0
	k.mat(K.DARK, BASALT, 0.4)
	for side: float in [-1.0, 1.0]:
		k.box(Vector3(side * 8.7, -0.1, (gz + 9.5 + 24.5) * 0.5), Vector3(0.5, 0.6, 24.5 - gz - 9.5), 0.05)
	# Pylons: battered towers with carved bands and spikes.
	for side: float in [-1.0, 1.0]:
		var px := side * 10.0
		k.mat(K.CASTLE, wall, 0.25)
		k.box(Vector3(px, 13.5, gz), Vector3(5.0, 27.0, 5.0), 0.1)
		k.moulding(Vector3(px - 2.5, 0, gz - 2.5), Vector3(px + 2.5, 0, gz - 2.5), Vector3(0, 0, -1), PackedVector2Array([Vector2(1.0, 0), Vector2(0.0, 3.0)]))
		k.moulding(Vector3(px + 2.5, 0, gz + 2.5), Vector3(px - 2.5, 0, gz + 2.5), Vector3(0, 0, 1), PackedVector2Array([Vector2(1.0, 0), Vector2(0.0, 3.0)]))
		k.moulding(Vector3(px + side * 2.5, 0, gz - 2.5), Vector3(px + side * 2.5, 0, gz + 2.5), Vector3(side, 0, 0), PackedVector2Array([Vector2(1.0, 0), Vector2(0.0, 3.0)]))
		k.mat(K.MARBLE, Color(0.14, 0.12, 0.14), 0.3)
		for y: float in [7.0, 14.0, 21.0]:
			k.box(Vector3(px, y, gz), Vector3(5.5, 0.6, 5.5), 0.08)
		# carved skull reliefs on the front of each pylon
		k.mat(K.BONE, Color(0.75, 0.7, 0.62), 0.7)
		for y: float in [10.5, 17.5]:
			k.rock(Vector3(px, y, gz + 2.55), Vector3(0.9, 1.1, 0.4), 0.12, 2, int(y))
			k.mat(K.DARK, Color(0.02, 0.02, 0.02), 0.5)
			for s: float in [-1.0, 1.0]:
				k.rock(Vector3(px + s * 0.35, y + 0.15, gz + 2.85), Vector3(0.22, 0.2, 0.12), 0.05, 1, 3)
			k.mat(K.BONE, Color(0.75, 0.7, 0.62), 0.7)
		k.mat(K.IRON, Color(1, 1, 1), 1.0)
		for i in 5:
			k.spike(Vector3(px - 2.0 + i * 1.0, 27.0, gz), Vector3.UP, 2.6 - absf(i - 2) * 0.5, 0.2, 5, i)
	# The arch over the portal and the lintel mass.
	k.mat(K.CASTLE, wall, 0.25)
	k.box(Vector3(0, 24.0, gz), Vector3(15.0, 6.0, 5.0), 0.08)
	var poly := PackedVector2Array([Vector2(-7.5, 13.0), Vector2(-7.5, 21.1), Vector2(7.5, 21.1), Vector2(7.5, 13.0)])
	for i in range(1, 16):
		poly.append(K._arch_pt(float(16 - i) / 16.0, 7.5, 13.0, 0.3))
	k.extrude(poly, gz - 2.5, gz + 2.5, true)
	k.mat(K.MARBLE, Color(0.15, 0.13, 0.15), 0.3)
	for face: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, gz + face * 2.6)))
		k.arch(15.0, 13.0, 1.3, 0.6, 17, 0.3)
		k.pop()
	# Great doors swung open against the pylons.
	for side: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis(Vector3.UP, side * 1.25), Vector3(side * 7.4, 0, gz + 2.6)))
		k.mat(K.IRON, Color(1, 1, 1), 1.0)
		k.box(Vector3(side * -3.5, 9.0, 0.25), Vector3(7.0, 18.0, 0.5), 0.05)
		k.mat(K.GOLD, Color(1, 1, 1), 1.0)
		for y: float in [3.0, 9.0, 15.0]:
			k.box(Vector3(side * -3.5, y, 0.55), Vector3(6.6, 0.4, 0.12), 0.02)
		for i in 4:
			k.rock(Vector3(side * -(1.0 + i * 1.6), 6.0, 0.6), Vector3(0.22, 0.22, 0.12), 0.0, 1, i)
			k.rock(Vector3(side * -(1.0 + i * 1.6), 12.0, 0.6), Vector3(0.22, 0.22, 0.12), 0.0, 1, i + 5)
		k.pop()
	# Chains hanging from the arch.
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	for s: float in [-1.0, 1.0]:
		d.chain(Vector3(s * 5.0, 20.5, gz + 2.7), Vector3(s * 9.0, 16.0, gz + 2.8), 0.5, 0.07, 1.6)
		d.chain(Vector3(s * 3.0, 20.5, gz - 2.7), Vector3(s * 3.0, 14.0, gz - 2.7), 0.5, 0.07, 0.0)
	# Guardian statues.
	for side: float in [-1.0, 1.0]:
		P.statue(k, Vector3(side * 18.0, 0, gz + 5.0), PI + side * 0.25, 17.0, K.TRI + K.DARK, Color(0.45, 0.4, 0.4), false, true)
		b.light(c + Vector3(side * 16.0, 13.0, gz + 9.0), Color(0.35, 0.85, 1.0), 2.0, 12.0, 0, 0.1, 0.8)
	# Soul-fire avenue.
	for bz: Vector3 in b.prop["braziers"]:
		P.fire_basin(b, k, bz, c + bz, 0.8, "soul", K.MARBLE, SOUL, 0)
	# Rock rims around the lava pools.
	for pl: Array in b.prop["pools"]:
		var pc: Vector3 = pl[0]
		var r := float(pl[1])
		k.mat(K.TRI + K.DARK, Color(0.35, 0.3, 0.3), 0.4)
		var n := int(r * 3.0)
		for i in n:
			var a := TAU * i / n + k.rng.randf_range(-0.1, 0.1)
			k.rock(pc + Vector3(cos(a) * (r + 0.6), 0.6, sin(a) * (r + 0.6)), Vector3(k.rng.randf_range(0.6, 1.1), k.rng.randf_range(0.3, 0.6), k.rng.randf_range(0.6, 1.0)), 0.35, 2, i)
		b.light(c + pc + Vector3(0, 1.5, 0), Color(1.0, 0.35, 0.08), 2.5, r * 3.0, 0, 0.2, 1.2)
	# The portal's own glow.
	b.light(c + Vector3(0, 8.0, gz + 3.0), Color(1.0, 0.4, 0.15), 4.0, 26.0, 1, 0.2, 2.0)
