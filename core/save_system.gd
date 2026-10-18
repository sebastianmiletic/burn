class_name SaveSystem
extends RefCounted
## Runs (saved worlds) in user://saves. A save holds the world seed, every
## block edit, the player, quests, discoveries, defeated bosses and the clock.
##
## A run is addressed by an id. There is no limit on how many runs exist:
##   * new runs:   id "<hex>"   -> saves/run_<hex>.burn  (+ run_<hex>.meta)
##   * old saves:  id "slot_N"  -> saves/slot_N.burn     (+ slot_N.meta)
## Saves from the three-slot era keep their file names, so they load in this
## and older builds alike; nothing is moved or deleted. An int run (the old
## slot number, also used by tests and the party world) means "slot_N".
## The small .meta side file (title, dates, seed, summary) lets the runs list
## show every run without decompressing whole worlds; it is rebuilt from the
## save whenever it is missing or older than the save.

static var DIR := RuntimePaths.file("saves")
const SLOTS := 3            ## the old fixed slots, still listed if present
const VERSION := 1
const META_VERSION := 1
## Damage the player takes, per difficulty (see Game.damage_taken_scale()).
const DIFFICULTIES := ["Story", "Normal", "Hard"]
const DIFFICULTY_DAMAGE := [0.5, 1.0, 1.5]
const DIFFICULTY_NORMAL := 1
const PARTY_ID := "slot_9"  ## Game.PARTY_SLOT: the host's shared co-op world


## "slot_N" for an int (old slot number), the id itself for a String.
static func run_id(run: Variant) -> String:
	if run is int or run is float:
		return "slot_%d" % int(run)
	return String(run)


static func is_legacy(run: Variant) -> bool:
	return run_id(run).begins_with("slot_")


## Old slot number of a legacy run, -1 for new runs.
static func legacy_slot(run: Variant) -> int:
	var id := run_id(run)
	return int(id.trim_prefix("slot_")) if id.begins_with("slot_") and id.trim_prefix("slot_").is_valid_int() else -1


static func path(run: Variant) -> String:
	var id := run_id(run)
	if id.begins_with("slot_"):
		return "%s/%s.burn" % [DIR, id]
	return "%s/run_%s.burn" % [DIR, id]


static func meta_path(run: Variant) -> String:
	return path(run).get_basename() + ".meta"


## The explored-map side file. Old slots keep their old name (map_fog_<N>.burn).
static func fog_path(run: Variant) -> String:
	var slot := legacy_slot(run)
	if slot >= 0:
		return "%s/map_fog_%d.burn" % [DIR, slot]
	return "%s/map_fog_run_%s.burn" % [DIR, run_id(run)]


static func exists(run: Variant) -> bool:
	return FileAccess.file_exists(path(run))


## A fresh, unused id for a new run.
static func new_id() -> String:
	var t := int(Time.get_unix_time_from_system())
	for i in 64:
		var id := "%x%04x" % [t, randi() % 0x10000]
		if not exists(id) and not FileAccess.file_exists(meta_path(id)):
			return id
	return "%x%08x" % [t, randi()]


## Ids may come from the UI or old configs: only plain names are accepted.
static func valid_id(run: Variant) -> bool:
	var id := run_id(run)
	if id == "" or id.length() > 40:
		return false
	for c in id:
		if not (c.is_valid_identifier() or c.is_valid_int()):
			return false
	return true


static func write(run: Variant, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	data["version"] = VERSION
	data["saved_at"] = Time.get_unix_time_from_system()
	# The run's own description travels inside the save too (the .meta file
	# is only a cache); older builds ignore the extra key.
	var meta := read_meta(run)
	var info: Dictionary = data.get("run", {}) if data.get("run") is Dictionary else {}
	for k in ["title", "created_at", "difficulty"]:
		if meta.has(k) and not info.has(k):
			info[k] = meta[k]
	if meta.has("title"):
		info["title"] = meta["title"]   # a rename always wins
	if not info.has("created_at"):
		info["created_at"] = data["saved_at"]
	data["run"] = info
	var raw := var_to_bytes(data)
	var bytes := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var tmp := path(run) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(bytes.size())
	f.store_32(raw.size())
	f.store_buffer(bytes)
	f.close()
	# Atomic-ish replace so a crash mid-write never destroys the old save.
	var ok := DirAccess.rename_absolute(tmp, path(run)) == OK
	if ok:
		_write_meta(run, _summary_from_save(run, data))
	return ok


static func read(run: Variant) -> Dictionary:
	var f := FileAccess.open(path(run), FileAccess.READ)
	if f == null:
		return {}
	if f.get_length() < 8:
		return {}
	var size := f.get_32()
	var raw_size := f.get_32()
	if size <= 0 or size > f.get_length() - 8 or raw_size <= 0 or raw_size > 256 * 1024 * 1024:
		return {}
	var bytes := f.get_buffer(size)
	f.close()
	var raw := bytes.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	var v: Variant = bytes_to_var(raw)
	return v if v is Dictionary else {}


## Removes a run: its save, its summary and its explored map.
static func delete(run: Variant) -> void:
	for p in [path(run), meta_path(run), fog_path(run)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# --- Run metadata ----------------------------------------------------------------------

static func read_meta(run: Variant) -> Dictionary:
	var p := meta_path(run)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	var v: Variant = f.get_var() if f != null else null
	return v if v is Dictionary else {}


static func _write_meta(run: Variant, meta: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	meta["meta_version"] = META_VERSION
	meta["file_time"] = FileAccess.get_modified_time(path(run)) if exists(run) else 0
	var f := FileAccess.open(meta_path(run), FileAccess.WRITE)
	if f != null:
		f.store_var(meta)


## Records a new run's choices before its first save (title, seed, difficulty).
static func create_meta(run: Variant, title: String, seed_value: int, difficulty: int) -> void:
	_write_meta(run, {"title": title, "seed": seed_value, "difficulty": difficulty,
		"created_at": Time.get_unix_time_from_system()})


static func rename(run: Variant, title: String) -> void:
	var t := title.strip_edges()
	if t == "":
		return
	var meta := summary(run)
	meta["title"] = t.left(40)
	_write_meta(run, meta)


static func default_title(run: Variant) -> String:
	var id := run_id(run)
	if id == PARTY_ID:
		return "Warband world"
	var slot := legacy_slot(run)
	if slot >= 0:
		const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
		return "Hearth %s" % (ROMAN[slot] if slot < ROMAN.size() else str(slot + 1))
	return "Untitled run"


static func _summary_from_save(run: Variant, d: Dictionary) -> Dictionary:
	var p: Dictionary = d.get("player", {}) if d.get("player") is Dictionary else {}
	var info: Dictionary = d.get("run", {}) if d.get("run") is Dictionary else {}
	var meta := read_meta(run)
	return {
		"title": String(meta.get("title", info.get("title", default_title(run)))),
		"created_at": float(meta.get("created_at", info.get("created_at", 0.0))),
		"difficulty": int(meta.get("difficulty", info.get("difficulty", DIFFICULTY_NORMAL))),
		"seed": int(d.get("seed", meta.get("seed", 0))),
		"name": String(p.get("name", "Wanderer")),
		"rank": ItemDB.rank_for_xp(int(p.get("xp", 0))),
		"play_time": float(d.get("play_time", 0.0)),
		"location": String(d.get("location_name", "")),
		"saved_at": float(d.get("saved_at", 0.0)),
		"world_revision": int(d.get("world_revision", 1)),
	}


## Everything the runs list shows for one run (rebuilds a stale summary).
static func summary(run: Variant) -> Dictionary:
	var meta := read_meta(run)
	var fresh := exists(run) and (meta.is_empty() or int(meta.get("meta_version", 0)) != META_VERSION
			or int(meta.get("file_time", -1)) != FileAccess.get_modified_time(path(run)) or not meta.has("saved_at"))
	if fresh:
		var d := read(run)
		if not d.is_empty():
			meta = _summary_from_save(run, d)
			_write_meta(run, meta)
	var out := meta.duplicate()
	var id := run_id(run)
	out["id"] = id
	out["exists"] = exists(run)
	out["legacy"] = is_legacy(run)
	out["slot"] = legacy_slot(run)
	if not out.has("title") or String(out["title"]) == "":
		out["title"] = default_title(run)
	for k: String in ["name", "location"]:
		if not out.has(k):
			out[k] = ""
	for k: String in ["play_time", "saved_at", "created_at"]:
		out[k] = float(out.get(k, 0.0))
	out["rank"] = int(out.get("rank", 0))
	out["seed"] = int(out.get("seed", 0))
	out["difficulty"] = clampi(int(out.get("difficulty", DIFFICULTY_NORMAL)), 0, DIFFICULTIES.size() - 1)
	return out


## Every run on disk, most recently played first.
static func list_runs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".burn"):
			continue
		var id := ""
		if f.begins_with("run_"):
			id = f.trim_prefix("run_").trim_suffix(".burn")
		elif f.begins_with("slot_") and f.trim_prefix("slot_").trim_suffix(".burn").is_valid_int():
			id = f.trim_suffix(".burn")
		if id == "" or not valid_id(id):
			continue
		var s := summary(id)
		if s["exists"]:
			out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := maxf(float(a["saved_at"]), float(a["created_at"]))
		var tb := maxf(float(b["saved_at"]), float(b["created_at"]))
		return ta > tb if ta != tb else String(a["id"]) < String(b["id"]))
	return out


## Summaries of the three old slots (kept for older callers).
static func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in SLOTS:
		var info := {"slot": i, "exists": exists(i), "name": "Empty", "rank": 0, "play_time": 0.0, "location": ""}
		if info["exists"]:
			var s := summary(i)
			for k in ["name", "rank", "play_time", "location", "saved_at"]:
				info[k] = s[k]
		out.append(info)
	return out


## Id of the most recently played run ("" when there is none).
static func most_recent() -> String:
	var runs := list_runs()
	return String(runs[0]["id"]) if not runs.is_empty() else ""
