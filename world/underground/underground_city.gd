class_name UndergroundCity
extends RefCounted
## Hearthold, the city of the Stonekin (world revision 5, UndergroundSites._hearthold): two
## rings of carved stone houses around the Heartcrystal, a market ring, a forge, and two
## gates in the cavern wall. `layout` is relative to the cavern floor centre; `blueprints`
## stamps it. Deterministic per seed. First pass: plain houses, villager NPCs as the
## Stonekin (no bridges, upper level or custom Stonekin model yet).

const RINGS := [[22.0, 8], [40.0, 12]]
const GATE_RADIUS := 57.0
const ROLES := ["villager", "villager", "blacksmith", "merchant", "villager", "guard"]


static func layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7349 + 11
	var houses: Array = []
	var npcs: Array = []
	for ring: Array in RINGS:
		var r := float(ring[0])
		var n := int(ring[1])
		var turn := rng.randf() * TAU
		for i in n:
			var a := turn + TAU * i / n
			var size := Vector3i(rng.randi_range(5, 7), rng.randi_range(4, 6), rng.randi_range(5, 7))
			houses.append({"pos": Vector3(cos(a) * r, 0, sin(a) * r), "size": size, "angle": a})
			if i % 2 == 0:
				npcs.append({"pos": Vector3(cos(a) * (r - 6.0), 0, sin(a) * (r - 6.0)), "role": ROLES[npcs.size() % ROLES.size()], "yaw": a + PI})
	var g := rng.randf() * TAU
	var gates: Array = []
	for k in 2:
		var a := g + k * PI
		gates.append({"pos": Vector3(cos(a) * GATE_RADIUS, 0, sin(a) * GATE_RADIUS), "angle": a})
	# Keep the gate roads clear of houses.
	houses = houses.filter(func(h: Dictionary) -> bool:
		for gate: Dictionary in gates:
			if absf(angle_difference(float(h["angle"]), float(gate["angle"]))) < 0.3:
				return false
		return true)
	return {"houses": houses, "npcs": npcs, "gates": gates, "forge": Vector3(cos(g + PI * 0.5) * 14.0, 0, sin(g + PI * 0.5) * 14.0)}


## Blueprints for the city around floor centre `fc` (the floor surface is fc.y).
static func blueprints(city: Dictionary, fc: Vector3i) -> Array[Blueprint]:
	var out: Array[Blueprint] = []
	for h: Dictionary in city["houses"]:
		var p: Vector3 = h["pos"]
		var s: Vector3i = h["size"]
		var o := fc + Vector3i(roundi(p.x) - s.x / 2, 0, roundi(p.z) - s.z / 2)
		var bp := Blueprint.new(o, s + Vector3i(0, 1, 0))
		bp.hollow(Vector3i.ZERO, Vector3i(s.x - 1, s.y - 1, s.z - 1), Blocks.GRANITE, Blocks.SLATE, Blocks.SLATE)
		bp.fill(Vector3i(0, s.y, 0), Vector3i(s.x - 1, s.y, s.z - 1), Blocks.SLATE)
		# A doorway facing the Heartcrystal, and a window either side.
		var inward := -Vector2(p.x, p.z).normalized()
		var dx := s.x / 2 + roundi(inward.x * (s.x / 2))
		var dz := s.z / 2 + roundi(inward.y * (s.z / 2))
		bp.fill(Vector3i(clampi(dx, 0, s.x - 1), 1, clampi(dz, 0, s.z - 1)), Vector3i(clampi(dx, 0, s.x - 1), 2, clampi(dz, 0, s.z - 1)), Blueprint.CARVE)
		bp.set_local(0, 2, s.z / 2, Blueprint.CARVE)
		bp.set_local(s.x - 1, 2, s.z / 2, Blueprint.CARVE)
		out.append(bp)
	# The Heartcrystal on its plinth, and the forge's ember pit.
	var heart := Blueprint.new(fc + Vector3i(-3, 0, -3), Vector3i(7, 9, 7))
	heart.fill(Vector3i(0, 0, 0), Vector3i(6, 1, 6), Blocks.MARBLE)
	heart.fill(Vector3i(2, 2, 2), Vector3i(4, 7, 4), Blocks.AMETHYST)
	heart.set_local(3, 8, 3, Blocks.AMETHYST)
	out.append(heart)
	var fp: Vector3 = city["forge"]
	var forge := Blueprint.new(fc + Vector3i(roundi(fp.x) - 2, -1, roundi(fp.z) - 2), Vector3i(5, 3, 5))
	forge.fill(Vector3i(0, 0, 0), Vector3i(4, 1, 4), Blocks.BASALT)
	forge.fill(Vector3i(1, 1, 1), Vector3i(3, 1, 3), Blocks.MAGMA_ROCK)
	out.append(forge)
	return out
