extends Node
## Autoload "Updater" (loaded first): keeps exported builds up to date from
## GitHub Releases without reinstalling.
##
## Every release (built by .github/workflows/release.yml) carries, next to the
## full downloads, a data pack per platform: burn-<platform>-godot<engine>.pck.
## On launch the game asks GitHub for the latest release; when it is newer than
## the running version and built with the same engine, the pack is downloaded
## to user://updates/ and the game restarts into it (`--main-pack`). Later
## launches start the newest downloaded pack directly. A pack that fails to boot
## is discarded automatically. If the engine itself changed, the menu points
## the player to the full download instead.

signal status_changed(text: String, progress: float)

const REPO := "sebastianmiletic/burn"
const LATEST_URL := "https://api.github.com/repos/%s/releases/latest"
const DIR := "user://updates"
const BOOT_FLAG := "user://updates/booting.txt"

var status_text := ""
var current_version := ""
var latest_version := ""
var download_url := ""

var _http: HTTPRequest
var _progress := -1.0
var _downloading := ""
var _expected_digest := ""


func _ready() -> void:
	current_version = String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if not _enabled():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	if _running_pack():
		# We booted from a downloaded pack: once the game is up, mark it healthy.
		get_tree().create_timer(8.0).timeout.connect(func() -> void: DirAccess.remove_absolute(BOOT_FLAG))
	else:
		_discard_failed_pack()
		var pack := _best_pack()
		if pack != "":
			_relaunch_with(pack)
			return
	_check.call_deferred()


func _enabled() -> bool:
	if not OS.has_feature("template") or DisplayServer.get_name() == "headless":
		return false
	for a in OS.get_cmdline_user_args():
		if a == "--no-update" or a.begins_with("--capture") or a.begins_with("--mp-test") or a == "--playtest":
			return false
	return bool(Settings.get_value("gameplay", "auto_update"))


func _running_pack() -> bool:
	return "--main-pack" in OS.get_cmdline_args()


func _platform() -> String:
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("macos"):
		return "macos"
	return "linux"


func _pack_suffix() -> String:
	var v := Engine.get_version_info()
	return "%s-godot%d.%d.%d.pck" % [_platform(), v["major"], v["minor"], v["patch"]]


static func compare(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## Newest downloaded pack that is newer than this build, or "".
func _best_pack() -> String:
	var best := ""
	var best_v := current_version
	var d := DirAccess.open(DIR)
	if d == null:
		return ""
	for f in d.get_files():
		if not f.ends_with(_pack_suffix()):
			continue
		var v := f.get_slice("-", 1)  # burn-<version>-<platform>-godotX.Y.Z.pck
		if compare(v, best_v) > 0:
			best_v = v
			best = DIR.path_join(f)
	return best


func _relaunch_with(pack: String) -> void:
	var f := FileAccess.open(BOOT_FLAG, FileAccess.WRITE)
	if f != null:
		f.store_string(pack)
		f.close()
	var args := PackedStringArray(["--main-pack", ProjectSettings.globalize_path(pack)])
	var skip := false
	for a in OS.get_cmdline_args():
		if skip:
			skip = false
			continue
		if a == "--main-pack":
			skip = true
			continue
		args.append(a)
	var pid := OS.create_instance(args)
	if pid > 0:
		get_tree().quit()
	else:
		DirAccess.remove_absolute(BOOT_FLAG)
		_set_status("Update ready. Close and reopen Burn to apply it.")


## A pack that never reported a healthy boot is broken: delete it.
func _discard_failed_pack() -> void:
	if not FileAccess.file_exists(BOOT_FLAG):
		return
	var pack := FileAccess.get_file_as_string(BOOT_FLAG).strip_edges()
	DirAccess.remove_absolute(BOOT_FLAG)
	if pack.begins_with(DIR + "/burn-") and not ".." in pack and FileAccess.file_exists(pack):
		DirAccess.remove_absolute(pack)
		push_warning("Discarded update pack that failed to start: " + pack)


func _set_status(text: String, progress := -1.0) -> void:
	status_text = text
	_progress = progress
	status_changed.emit(text, progress)


func _check() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	_http.body_size_limit = 4 * 1024 * 1024
	add_child(_http)
	_http.request_completed.connect(_on_release, CONNECT_ONE_SHOT)
	var err := _http.request(LATEST_URL % REPO, ["User-Agent: Burn-Updater", "Accept: application/vnd.github+json"])
	if err != OK:
		_http.queue_free()


func _on_release(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_http.queue_free()
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		_http.queue_free()
		return
	if bool(data.get("draft", false)) or bool(data.get("prerelease", false)):
		_http.queue_free()
		return
	latest_version = String(data.get("tag_name", "")).trim_prefix("v")
	var version_pattern := RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	if version_pattern.search(latest_version) == null:
		_http.queue_free()
		return
	if latest_version == "" or compare(latest_version, current_version) <= 0:
		_http.queue_free()
		return
	var wanted := "burn-%s-%s" % [latest_version, _pack_suffix()]
	for asset: Dictionary in data.get("assets", []):
		if String(asset.get("name", "")) == wanted:
			download_url = String(asset.get("browser_download_url", ""))
			_expected_digest = String(asset.get("digest", "") if asset.get("digest") != null else "").trim_prefix("sha256:")
			if not download_url.begins_with("https://github.com/%s/releases/download/" % REPO) or RegEx.create_from_string("^[a-f0-9]{64}$").search(_expected_digest) == null:
				download_url = ""
	if download_url == "":
		# Different engine version: needs the full download.
		_set_status("Burn %s is available — download it from github.com/%s" % [latest_version, REPO])
		_http.queue_free()
		return
	_downloading = DIR.path_join(wanted)
	_http.download_file = _downloading + ".part"
	_http.timeout = 180.0
	_http.body_size_limit = 1024 * 1024 * 1024
	_http.request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	_set_status("Downloading update %s…" % latest_version, 0.0)
	if _http.request(download_url, ["User-Agent: Burn-Updater"]) != OK:
		_set_status("")
		_http.queue_free()


func _process(_delta: float) -> void:
	if _downloading != "" and _http != null and is_instance_valid(_http):
		var total := _http.get_body_size()
		if total > 0:
			var p := float(_http.get_downloaded_bytes()) / total
			if absf(p - _progress) > 0.01:
				_set_status("Downloading update %s… %d%%" % [latest_version, int(p * 100.0)], p)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var part := _downloading + ".part"
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.file_exists(part)
	_http.queue_free()
	_http = null
	if not ok:
		DirAccess.remove_absolute(part)
		_downloading = ""
		_set_status("")
		return
	if FileAccess.get_sha256(part) != _expected_digest:
		DirAccess.remove_absolute(part)
		_downloading = ""
		_set_status("Update verification failed. Your installed game is unchanged.")
		return
	if DirAccess.rename_absolute(part, _downloading) != OK:
		_downloading = ""
		_set_status("Cannot install update. Check available disk space and permissions.")
		return
	var pack := _downloading
	_downloading = ""
	# Keep the previous healthy pack for rollback if the new pack fails to boot.
	var game := get_node_or_null("/root/Game")
	var in_menu := game != null and int(game.get("state")) <= 2  # boot, intro, menu
	if in_menu:
		_set_status("Updating to %s…" % latest_version, 1.0)
		await get_tree().create_timer(0.8).timeout
		# Starting a game while the download finishes must never interrupt play.
		if int(game.get("state")) <= 2:
			_relaunch_with(pack)
		else:
			_set_status("Update ready. It will apply the next time Burn starts.")
	else:
		_set_status("Update %s ready — it applies next time you start Burn." % latest_version)
