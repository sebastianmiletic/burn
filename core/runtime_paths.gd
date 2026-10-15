class_name RuntimePaths
extends RefCounted
## Automated runs can keep every save/cache inside a selected sandbox instead
## of touching a real player's settings. Normal installs use the OS user folder.
static func file(relative: String) -> String:
	var root := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-dir="):
			root = arg.trim_prefix("--data-dir=")
			break
	return root.path_join(relative)
