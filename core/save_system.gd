class_name SaveSystem
extends RefCounted
## Save slots in user://saves. A save holds the world seed, every block edit,
## the player, quests, discoveries, defeated bosses and the clock.

const DIR := "user://saves"
const SLOTS := 3
const VERSION := 1


static func path(slot: int) -> String:
	return "%s/slot_%d.burn" % [DIR, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


static func write(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	data["version"] = VERSION
	data["saved_at"] = Time.get_unix_time_from_system()
	var bytes := var_to_bytes(data).compress(FileAccess.COMPRESSION_ZSTD)
	var tmp := path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(bytes.size())
	f.store_32(var_to_bytes(data).size())
	f.store_buffer(bytes)
	f.close()
	# Atomic-ish replace so a crash mid-write never destroys the old save.
	DirAccess.rename_absolute(tmp, path(slot))
	return true


static func read(slot: int) -> Dictionary:
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var size := f.get_32()
	var raw_size := f.get_32()
	var bytes := f.get_buffer(size)
	f.close()
	var raw := bytes.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	var v: Variant = bytes_to_var(raw)
	return v if v is Dictionary else {}


static func delete(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(path(slot))


## Summaries for the menu.
static func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in SLOTS:
		var info := {"slot": i, "exists": exists(i), "name": "Empty", "rank": 0, "play_time": 0.0, "location": ""}
		if info["exists"]:
			var d := read(i)
			var p: Dictionary = d.get("player", {})
			info["name"] = p.get("name", "Wanderer")
			info["rank"] = ItemDB.rank_for_xp(int(p.get("xp", 0)))
			info["play_time"] = float(d.get("play_time", 0.0))
			info["location"] = String(d.get("location_name", ""))
			info["saved_at"] = d.get("saved_at", 0)
		out.append(info)
	return out


static func most_recent() -> int:
	var best := -1
	var best_t := -1.0
	for s in slots():
		if s["exists"] and float(s.get("saved_at", 0)) > best_t:
			best_t = float(s.get("saved_at", 0))
			best = s["slot"]
	return best
