extends SceneTree
## Measures the Audio autoload's startup: main-thread cost of _ready, and when
## the priority sounds / every sound / every ambience bed became playable.
## Run twice: the first run renders and fills user://audio_cache, the second
## loads from it.
##
##   godot --headless --path . -s res://tests/audio/measure_startup.gd [-- clear]
##
## `clear` deletes the cache first (cold start).

var _t0 := 0
var _priority_ms := -1.0
var _cleared := false


func _init() -> void:
	if "clear" in OS.get_cmdline_user_args():
		_clear("user://audio_cache")
		_cleared = true


func _clear(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for d in da.get_directories():
		_clear(dir.path_join(d))
	for f in da.get_files():
		da.remove(f)
	DirAccess.remove_absolute(dir)


func _process(_delta: float) -> bool:
	if _t0 == 0:
		_t0 = Time.get_ticks_usec()
	var audio := root.get_node_or_null("Audio")
	if audio == null:
		print("no Audio autoload")
		quit(1)
		return false
	var s: Dictionary = audio.call("stats")
	if _priority_ms < 0.0:
		var all := true
		for sound: String in SfxLibrary.PRIORITY:
			if not audio.call("is_ready", sound):
				all = false
				break
		if all:
			_priority_ms = (Time.get_ticks_usec() - _t0) / 1000.0 + float(s.get("ready_ms", 0.0))
	if s.has("done_ms"):
		print("cache %s (%s)" % ["cleared" if _cleared else "as found", s["cache_dir"]])
		print("Audio._ready on the main thread: %.1f ms (menu sounds %.1f ms)" % [s["ready_ms"], s["ui_ms"]])
		print("priority sounds playable after ~%.0f ms" % _priority_ms)
		print("all %d sound variants after %.0f ms" % [s["sfx_variants_done"], s.get("sfx_ms", -1.0)])
		print("all %d ambience beds after %.0f ms" % [s["ambience_ready"], s.get("ambience_ms", -1.0)])
		print("everything after %.0f ms, %d cache hits" % [s["done_ms"], s["cache_hits"]])
		quit()
	elif (Time.get_ticks_usec() - _t0) > 900 * 1000000:
		print("timeout: ", s)
		quit(1)
	return false
