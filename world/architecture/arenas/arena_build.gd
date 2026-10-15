class_name ArenaBuild
extends RefCounted
## Everything one arena needs, produced on a worker thread from the arena's
## Location prop (pure data) and turned into nodes by ArenaInstance.
##
## Builders write geometry into kits:
##   shell   big architecture, visible up to SHELL_RANGE, casts shadows
##   detail  small props (candles, bones, chains), visible up to DETAIL_RANGE
##   web     silk quads for arena_web.gdshader (UV 0..1, UV2 = seed, style)
##   flows   name -> kit for arena_flow.gdshader ribbons (lava, souls)
## plus flames (MultiMesh billboards), lights (pooled at runtime), embers,
## and gates (animated pieces driven by the arena_gate state).

const SHELL_RANGE := 420.0
const DETAIL_RANGE := 90.0
const CELL := 28.0

var kind := ""
var center := Vector3.ZERO
var radius := 40.0
var prop := {}
var shell: ArenaKit
var detail: ArenaKit
var web: ArenaKit
var flows := {}            # name -> ArenaKit
var flow_params := {}      # name -> {deep_color, glow_color, hot_color, energy, speed, crust, wisps}
## Shader parameters of the arena material: frost, soot, moss, ambient, outdoor, grime...
var params := {}
## [position, size (height m), kind: "fire" | "soul" | "green" | "candle"]
var flames: Array = []
## {pos, color, energy, range, flicker, shadow: int priority (higher first), fog}
var lights: Array = []
## [position, extents, amount, kind]
var embers: Array = []
## {index: arena_gate spawn index, kit: ArenaKit (in gate space), xf: Transform3D (closed pose),
##  style: "drop" | "web" | "slab", travel: float (m)}
var gates: Array = []
## Results of finish(): [{arrays, material, aabb, range, shadow}]
var meshes: Array = []


func _init(arena_prop: Dictionary) -> void:
	prop = arena_prop
	kind = String(prop.get("arena", ""))
	center = prop.get("center", Vector3.ZERO)
	radius = float(prop.get("radius", 40.0))
	var s := int(prop.get("seed", hash(kind)))
	shell = _kit(s)
	detail = _kit(s + 1)
	web = _kit(s + 2)


func _kit(s: int) -> ArenaKit:
	var k := ArenaKit.new(s)
	# Builders work in world coordinates; meshes are stored relative to the arena node.
	k.push(Transform3D(Basis.IDENTITY, -center))
	return k


func flow(flow_name: String, settings: Dictionary) -> ArenaKit:
	if not flows.has(flow_name):
		flows[flow_name] = _kit(hash(flow_name))
		flow_params[flow_name] = settings
	return flows[flow_name]


func flame(pos: Vector3, height: float, flame_kind := "fire") -> void:
	flames.append([pos, height, flame_kind])


func light(pos: Vector3, color: Color, energy: float, light_range: float, shadow := 0, flicker := 0.25, fog := 1.0) -> void:
	lights.append({"pos": pos, "color": color, "energy": energy, "range": light_range, "flicker": flicker, "shadow": shadow, "fog": fog})


## kit: the gate built in its own space (y up, opening centred on x); closed: its world pose.
func gate(index: int, kit: ArenaKit, closed: Transform3D, style: String, travel: float) -> void:
	gates.append({"index": index, "kit": kit, "xf": Transform3D(closed.basis, closed.origin - center), "style": style, "travel": travel})


## Worker thread: split the kits into culling cells.
func finish() -> void:
	for pair: Array in [[shell, "main", SHELL_RANGE, true], [detail, "main", DETAIL_RANGE, false]]:
		var kit: ArenaKit = pair[0]
		if kit.is_empty():
			continue
		var cells := kit.split(CELL)
		for key: Vector2i in cells:
			meshes.append({"arrays": cells[key], "material": pair[1], "range": pair[2], "shadow": pair[3]})
	if not web.is_empty():
		meshes.append({"arrays": web.arrays(), "material": "web", "range": SHELL_RANGE * 0.5, "shadow": false})
	for flow_name: String in flows:
		var kit: ArenaKit = flows[flow_name]
		if not kit.is_empty():
			meshes.append({"arrays": kit.arrays(), "material": "flow:" + flow_name, "range": SHELL_RANGE, "shadow": false})
