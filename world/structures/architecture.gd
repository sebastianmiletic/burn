class_name Architecture
extends Node3D
## Continuous building meshes, batched by material per location. Collision stays
## in the authoritative field but STRUCTURE samples are never drawn as cubes.
var _built := {}
var _poll := 0.0

static func box(loc: Location, at: Vector3, extent: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	loc.props.append({"type": "box", "at": at, "size": extent, "material": material, "rotation": rotation})

static func house(loc: Location, bp: Blueprint, c: Vector3i, w: int, d: int, height: int) -> void:
	var x0 := c.x - w / 2
	var z0 := c.z - d / 2
	var x1 := x0 + w - 1
	var z1 := z0 + d - 1
	var origin := Vector3(bp.origin)
	var center := origin + Vector3(x0 + w * 0.5, c.y, z0 + d * 0.5)
	box(loc, center + Vector3(0, 0.5, 0), Vector3(w + 2, 1, d + 2), "stone")
	# Merge horizontal runs, preserving the blueprint's doors and windows.
	for y in range(c.y + 1, c.y + height + 1):
		for z in [z0, z1]:
			var start := -1
			for x in range(x0, x1 + 2):
				var occupied := x <= x1 and bp.get_local(x, y, z) != Blueprint.CARVE
				if occupied and start < 0:
					start = x
				if not occupied and start >= 0:
					box(loc, origin + Vector3((start + x) * 0.5, y + 0.5, z + 0.5), Vector3(x - start, 1, 1), "plaster")
					start = -1
		for x in [x0, x1]:
			var start := -1
			for z in range(z0 + 1, z1 + 1):
				var occupied := z < z1 and bp.get_local(x, y, z) != Blueprint.CARVE
				if occupied and start < 0:
					start = z
				if not occupied and start >= 0:
					box(loc, origin + Vector3(x + 0.5, y + 0.5, (start + z) * 0.5), Vector3(1, 1, z - start), "plaster")
					start = -1
	# Exposed timber frame, fascia and a genuinely pitched roof (no steps).
	for x in [x0, x1]:
		for z in [z0, z1]:
			box(loc, origin + Vector3(x + 0.5, c.y + 1 + height * 0.5, z + 0.5), Vector3(1.04, height, 1.04), "timber")
	for z in [z0, z1]:
		for h in [1.12, float(height) + 0.85]:
			box(loc, origin + Vector3(x0 + w * 0.5, c.y + h, z + 0.5), Vector3(w + 0.12, 0.22, 1.1), "timber")
	var half := (d + 2.0) * 0.5
	var eave := float(c.y + height + 1)
	for side in [-1.0, 1.0]:
		box(loc, Vector3(center.x, origin.y + eave + half * 0.5, center.z + side * half * 0.5), Vector3(w + 2.6, 0.28, half * sqrt(2.0)), "roof", Vector3(side * PI / 4.0, 0, 0))
	for x in [x0 - 0.5, x1 + 1.5]:
		loc.props.append({"type": "gable", "at": Vector3(origin.x + x, origin.y + eave, center.z), "size": Vector3(half, half, 0.3), "material": "plaster", "rotation": Vector3(0, PI / 2.0, 0)})
	# Replace only this house's geometry with invisible collision. Keep lights.
	for y in range(c.y, c.y + height + d / 2 + 4):
		for z in range(z0 - 1, z1 + 2):
			for x in range(x0 - 1, x1 + 2):
				if bp.get_local(x, y, z) in [Blocks.COBBLE, Blocks.PLANKS, Blocks.LOG, Blocks.THATCH]:
					bp.set_local(x, y, z, Blocks.STRUCTURE)

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0:
		return
	_poll = 0.2
	var w := GameWorld.instance
	if w == null or w.local_player == null:
		return
	var wanted := {}
	var budget := 1
	for loc in w.locations(w.local_dimension):
		if loc.props.is_empty() or loc.center.distance_to(w.local_player.global_position) > 240:
			continue
		wanted[loc.id] = true
		if not _built.has(loc.id) and budget > 0:
			var node := build(loc)
			add_child(node)
			_built[loc.id] = node
			budget -= 1
	for id in _built.keys():
		if not wanted.has(id):
			(_built[id] as Node).queue_free()
			_built.erase(id)

static func build(loc: Location) -> Node3D:
	var node := Node3D.new()
	node.position = loc.center
	var batches := {}
	for prop: Dictionary in loc.props:
		var mat_name: String = prop["material"]
		if not batches.has(mat_name):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[mat_name] = st
		var mesh: Mesh
		var s: Vector3 = prop["size"]
		if prop["type"] == "gable":
			mesh = ModelKit.slab(PackedVector2Array([Vector2(-s.x, 0), Vector2(s.x, 0), Vector2(0, s.y)]), s.z)
		else:
			mesh = ModelKit.box(s)
		var xf := Transform3D(Basis.from_euler(prop.get("rotation", Vector3.ZERO)), (prop["at"] as Vector3) - loc.center)
		(batches[mat_name] as SurfaceTool).append_from(mesh, 0, xf)
	var colors := {"plaster": Color(0.65, 0.59, 0.46), "timber": Color(0.2, 0.13, 0.08), "roof": Color(0.25, 0.29, 0.31), "stone": Color(0.43, 0.42, 0.37)}
	for key: String in batches:
		var instance := MeshInstance3D.new()
		instance.mesh = (batches[key] as SurfaceTool).commit()
		instance.material_override = ModelKit.mat(colors.get(key, Color(0.5, 0.4, 0.3)), AsciiMaterialId.SOLID, 0.85, 0.28, 0.0)
		instance.visibility_range_end = 270
		node.add_child(instance)
	return node
