class_name LocationTracker
extends Node
## Local: works out where the player is for the HUD ("Unknown Structure",
## "Unknown Biome", "Hall of the Mountain King", "Caverns — 34 m deep"),
## handles discovery, and drives ambience and the cave darkness.

const UNKNOWN_BIOME_SECONDS := 6.0

var underground := false
var depth := 0.0
var current_title := ""
var current_subtitle := ""

var _timer := 0.0
var _known_biomes := {}
var _biome_time := 0.0
var _last_biome := -1


func gw() -> GameWorld:
	return get_parent() as GameWorld


func _process(delta: float) -> void:
	var w := gw()
	if w == null or w.local_player == null:
		return
	_timer -= delta
	_biome_time += delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var p := w.local_player
	var pos := p.global_position
	var dim := p.dimension
	var g := w.gen_for(dim)
	var surface := float(g.surface_height(int(pos.x), int(pos.z)))
	depth = surface - pos.y
	underground = depth > 6.0 and not w.world_for(dim).raycast(pos + Vector3(0, 1.6, 0), Vector3.UP, 48.0).is_empty()

	var title := ""
	var subtitle := ""
	var first := false
	var loc := w.location_at(pos, dim)
	if loc != null:
		if not w.discovered.has(loc.id):
			w.discover(loc)
			first = true
		title = loc.name
		subtitle = loc.kind_label() if loc.kind != Location.Kind.VILLAGE else "Village · safe haven"
	else:
		var near := _nearest_unknown_structure(w, pos, dim)
		if near != null:
			title = "Unknown Structure"
			subtitle = "%d m away" % int(Vector2(pos.x - near.center.x, pos.z - near.center.z).length())
		elif underground and dim == 0:
			if pos.y < -90:
				title = "The Abyss"
			elif pos.y < -40:
				title = "The Deep"
			else:
				title = "Caverns"
			subtitle = "%d m below the surface" % int(depth)
		else:
			var biome := g.biome_at(int(pos.x), int(pos.z))
			if biome != _last_biome:
				_last_biome = biome
				_biome_time = 0.0
			if _known_biomes.has(biome) or _biome_time > UNKNOWN_BIOME_SECONDS:
				if not _known_biomes.has(biome):
					_known_biomes[biome] = true
					first = true
				title = WorldGen.BIOME_NAMES[biome]
				subtitle = "Underworld" if dim == 1 else "Wilds"
			else:
				title = "Unknown Biome"
				subtitle = "Explore to learn its name"
	if title != current_title or subtitle != current_subtitle:
		current_title = title
		current_subtitle = subtitle
		Events.location_changed.emit(title, subtitle, first)
	_update_ambience(w, loc)


func _nearest_unknown_structure(w: GameWorld, pos: Vector3, dim: int) -> Location:
	for l in w.locations(dim):
		if w.discovered.has(l.id) or l.kind == Location.Kind.SHRINE:
			continue
		var to := Vector2(pos.x - l.center.x, pos.z - l.center.z)
		if to.length() < l.radius * 1.8 + 12.0 and (l.half_height <= 0.0 or absf(pos.y - l.center.y) < l.half_height * 2.0):
			return l
	return null


func _update_ambience(w: GameWorld, loc: Location) -> void:
	var dim := w.local_dimension
	var rain := w.weather.rain_amount() if dim == 0 and not underground else 0.0
	Audio.set_ambience({
		"wind": 0.0 if underground else (0.35 if dim == 0 else 0.15) + w.weather.wind_amount() * 0.5,
		"rain": rain,
		"cave": 1.0 if underground else 0.0,
		"lava": 1.0 if dim == 1 else (0.6 if underground and depth > 60.0 else 0.0),
		"fire": 0.4 if loc != null and loc.kind in [Location.Kind.VILLAGE, Location.Kind.SHRINE] else 0.0,
		"village": 0.7 if loc != null and loc.kind == Location.Kind.VILLAGE else 0.0,
	})
	if Audio.has_method("set_muffle"):
		Audio.call("set_muffle", 0.5 if underground else 0.0)
	if w.active_boss() == null:
		var music := "explore"
		if dim == 1:
			music = "hell"
		elif underground:
			music = "cave"
		elif w.sky.darkness() > 0.6:
			music = "night"
		Audio.set_music(music)
