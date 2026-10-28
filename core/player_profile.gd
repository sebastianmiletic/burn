class_name PlayerProfile
extends RefCounted
## The person at this computer, across every run and character: the role and
## skin last chosen in the lobby, unlocked skins, achievements and a few
## lifetime counters. One small file next to the settings (honours --data-dir).
##   {role, skin, skins: {id: true}, achievements: {id: unix seconds}, stats: {name: int}}

const FILE := "profile/profile.burn"

static var _data := {}
static var _loaded := false


static func path() -> String:
	return RuntimePaths.file(FILE)


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(path()):
			var f := FileAccess.open(path(), FileAccess.READ)
			var v: Variant = f.get_var() if f != null else null
			if v is Dictionary:
				_data = v
		for key: String in ["skins", "achievements", "stats"]:
			if not _data.get(key) is Dictionary:
				_data[key] = {}
	return _data


static func save() -> void:
	var d := data()
	DirAccess.make_dir_recursive_absolute(path().get_base_dir())
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f != null:
		f.store_var(d)


## Tests: forget the cached file (and optionally wipe it).
static func reset(wipe := false) -> void:
	_loaded = false
	_data = {}
	if wipe and FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())


static func role() -> String:
	var r := String(data().get("role", Roles.DEFAULT))
	return r if Roles.ROLES.has(r) else Roles.DEFAULT


static func set_role(r: String) -> void:
	if Roles.ROLES.has(r):
		data()["role"] = r
		save()


static func skin() -> String:
	var s := String(data().get("skin", Skins.DEFAULT))
	return s if Skins.SKINS.has(s) and has_skin(s) else Skins.DEFAULT


static func set_skin(s: String) -> void:
	if Skins.SKINS.has(s) and has_skin(s):
		data()["skin"] = s
		save()


static func has_skin(s: String) -> bool:
	return bool(Skins.SKINS.get(s, {}).get("free", false)) or (data()["skins"] as Dictionary).has(s)


## Returns true when newly unlocked.
static func unlock_skin(s: String) -> bool:
	if not Skins.SKINS.has(s) or has_skin(s):
		return false
	(data()["skins"] as Dictionary)[s] = true
	save()
	return true


static func has_achievement(id: String) -> bool:
	return (data()["achievements"] as Dictionary).has(id)


static func achievements() -> Dictionary:
	return data()["achievements"]


static func mark_achievement(id: String) -> bool:
	var a: Dictionary = data()["achievements"]
	if a.has(id):
		return false
	a[id] = int(Time.get_unix_time_from_system())
	save()
	return true


static func stat(name: String) -> int:
	return int((data()["stats"] as Dictionary).get(name, 0))


static func add_stat(name: String, amount := 1) -> int:
	var s: Dictionary = data()["stats"]
	s[name] = int(s.get(name, 0)) + amount
	save()
	return int(s[name])
