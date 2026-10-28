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
## Seconds in a new biome before its music takes over.
const MUSIC_HOLD := 6.0
var _music_candidate := ""
var _music_since := 0.0


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
	var above: Location = null
	if loc != null and underground and loc.half_height <= 0.0 and depth > 8.0:
		# Down in a cave under a village or ruin: you're not *in* that place.
		above = loc
		loc = null
	if loc != null:
		if not w.discovered.has(loc.id):
			w.discover(loc)
			first = true
		title = loc.name
		subtitle = loc.kind_label() if loc.kind != Location.Kind.VILLAGE else "Village · safe haven"
	else:
		var near := _nearest_unknown_structure(w, pos, dim) if not underground else null
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
			if g.revision >= 2 and pos.y < -8:
				title = CaveBiomes.NAMES[CaveBiomes.kind_at(pos, g.world_seed, g.revision)]
			subtitle = "%d m below the surface" % int(depth)
			if above != null:
				subtitle = "%d m beneath %s" % [int(depth), above.name]
		else:
			var biome := g.biome_at(int(pos.x), int(pos.z))
			if biome == WorldGen.Biome.OCEAN and g.sea_at(pos.x, pos.z) != WorldGen.Sea.NONE:
				biome = 100 + g.sea_at(pos.x, pos.z)  # each ocean biome is learnt on its own
			if biome != _last_biome:
				_last_biome = biome
				_biome_time = 0.0
			if _known_biomes.has(biome) or _biome_time > UNKNOWN_BIOME_SECONDS:
				if not _known_biomes.has(biome):
					_known_biomes[biome] = true
					first = true
				title = g.region_name(pos.x, pos.z)
				subtitle = "Underworld" if dim == 1 else "Wilds"
			else:
				title = "Unknown Biome"
				subtitle = "Explore to learn its name"
	if dim == Ogygia.DIM:
		title = "Ogygia"
		subtitle = "Calypso's grotto" if underground else "Island of Calypso"
	if title != current_title or subtitle != current_subtitle:
		current_title = title
		current_subtitle = subtitle
		Events.location_changed.emit(title, subtitle, first)
	_update_ambience(w, loc)


## Calm music for where the player is. A new biome's track only takes over
## after the player has stayed in it for MUSIC_HOLD seconds (no flip-flopping
## along a border); dimension, cave and day/night changes switch at once.
func _update_music(w: GameWorld, biome: int, is_underground: bool, force := false) -> void:
	var music := music_for(w, biome, is_underground)
	if music != _music_candidate:
		_music_candidate = music
		_music_since = Time.get_ticks_msec() / 1000.0
	var now_playing := Audio.current_music()
	var biome_switch := _is_land_or_sea(music) and _is_land_or_sea(now_playing)
	if force or not biome_switch or Time.get_ticks_msec() / 1000.0 - _music_since >= MUSIC_HOLD:
		Audio.set_music(music)


static func _is_land_or_sea(state: String) -> bool:
	return state == "explore" or (state.begins_with("biome") and not state in ["biome_ogygia", "biome_ryft"])


## The calm track for a biome (WorldGen.Biome), cave, dimension or night.
static func music_for(w: GameWorld, biome: int, is_underground: bool) -> String:
	var dim := w.local_dimension
	if dim == 1:
		match biome:
			WorldGen.Biome.ASPHODEL:
				return "biome_asphodel"
			WorldGen.Biome.TARTARUS:
				return "biome_tartarus"
		return "hell"
	if dim == 2:
		return "cave" if is_underground else "biome_ryft"
	if dim == Ogygia.DIM:
		return "biome_ogygia"
	if is_underground:
		return "cave"
	if w.sky != null and w.sky.darkness() > 0.6:
		return "night"
	match biome:
		WorldGen.Biome.OCEAN:
			var pos := w.local_player.global_position if w.local_player != null else Vector3.ZERO
			var g := w.gen_for(dim)
			var sea := g.sea_at(pos.x, pos.z) if g != null else WorldGen.Sea.NONE
			if sea in [WorldGen.Sea.ABYSS, WorldGen.Sea.VENTS, WorldGen.Sea.MAELSTROM]:
				return "biome_deep"
			if sea == WorldGen.Sea.FROZEN:
				return "biome_tundra"
			return "biome_sea"
		WorldGen.Biome.FOREST, WorldGen.Biome.REDWOOD:
			return "biome_forest"
		WorldGen.Biome.PEAKS, WorldGen.Biome.ALPINE:
			return "biome_peaks"
		WorldGen.Biome.TUNDRA:
			return "biome_tundra"
		WorldGen.Biome.MARSH:
			return "biome_marsh"
		WorldGen.Biome.WASTES, WorldGen.Biome.CANYON, WorldGen.Biome.VOLCANIC:
			return "biome_wastes"
		WorldGen.Biome.FJORD:
			return "biome_fjord"
		WorldGen.Biome.RYFT:
			return "biome_ryft"
	return "explore"


## Re-pick the calm music now (after a boss fight ends).
func refresh_music() -> void:
	var w := gw()
	if w == null or w.local_player == null:
		return
	var p := w.local_player
	var g := w.gen_for(p.dimension)
	var biome := g.biome_at(int(p.global_position.x), int(p.global_position.z)) if g != null else -1
	_update_music(w, biome, underground, true)


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
	var outdoors := dim == 0 and not underground
	var night := w.sky.darkness()
	var pos := w.local_player.global_position if w.local_player != null else Vector3.ZERO
	var biome := w.gen_for(dim).biome_at(int(pos.x), int(pos.z)) if w.gen_for(dim) != null else -1
	var wooded := biome == WorldGen.Biome.FOREST or biome == WorldGen.Biome.MARSH or biome == WorldGen.Biome.PEAKS
	var coast := 0.0
	if outdoors:
		var c := w.gen_for(0).center()
		coast = clampf(1.0 - absf(Vector2(pos.x, pos.z).distance_to(c) - 920.0) / 140.0, 0.0, 1.0)
		if biome == WorldGen.Biome.OCEAN:
			coast = maxf(coast, 0.8)
	var head := pos + Vector3(0, 1.6, 0)
	var head_block := w.world_for(dim).get_block(Vector3i(head.floor())) if w.world_for(dim) != null else 0
	var lake := 0.0
	if outdoors and biome == WorldGen.Biome.MARSH:
		lake = 0.35
	Audio.set_ambience({
		"birds": (1.0 - night) * (1.0 - rain) * (0.8 if wooded else 0.45) if outdoors else 0.0,
		"insects": (1.0 - night) * (1.0 - rain) * (0.6 if biome in [WorldGen.Biome.PLAINS, WorldGen.Biome.MARSH, WorldGen.Biome.FOREST] else 0.15) if outdoors else 0.0,
		"crickets": night * (1.0 - rain) * 0.8 if outdoors and biome != WorldGen.Biome.PEAKS else 0.0,
		"leaves": (0.6 if wooded else 0.2) * (0.5 + w.weather.wind_amount()) if outdoors else 0.0,
		"ocean": coast,
		"stream": lake,
		"underwater": 1.0 if head_block == Blocks.WATER else 0.0,
		"wind": 0.0 if underground else (0.35 if dim == 0 else 0.15) + w.weather.wind_amount() * 0.5,
		"rain": rain,
		"cave": 1.0 if underground else 0.0,
		"lava": 1.0 if dim == 1 else (0.6 if underground and depth > 60.0 else 0.0),
		"fire": 0.4 if loc != null and loc.kind in [Location.Kind.VILLAGE, Location.Kind.SHRINE] else 0.0,
		"village": 0.7 if loc != null and loc.kind == Location.Kind.VILLAGE else 0.0,
	})
	if Audio.has_method("set_muffle"):
		var lp := w.local_player
		Audio.call("set_muffle", maxf(0.5 if underground else 0.0, lp.audio_muffle if lp != null else 0.0))
	if loc != null and Audio.has_method("prefetch_music"):
		for s in loc.spawns_of("boss"):
			Audio.call("prefetch_music", "boss_" + String(s.get("kind", "")))
	if w.active_boss() == null:
		_update_music(w, biome, underground)
