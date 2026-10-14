extends Node
## Main scene: hands control to the Game state machine.


func _ready() -> void:
	Game.boot.call_deferred()
	if "--print-window" in OS.get_cmdline_user_args():
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			var s := DisplayServer.window_get_current_screen()
			print("WINDOW pos %s size %s | screen pos %s size %s usable %s | borderless %s" % [
				DisplayServer.window_get_position(), DisplayServer.window_get_size(),
				DisplayServer.screen_get_position(s), DisplayServer.screen_get_size(s), DisplayServer.screen_get_usable_rect(s),
				DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)])
			get_tree().quit())
