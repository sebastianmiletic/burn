class_name VictoryScreen
extends Control
## Shown on Events.campaign_won: the title burns in a last time, then the
## credits roll. Afterwards the player may keep exploring or leave.

const ROLL_SPEED := 38.0

var is_open := false
var _t := 0.0
var _title: BurningTitle
var _roll: VBoxContainer
var _clip: Control
var _buttons: HBoxContainer


const REPO_URL := "https://github.com/sebastianmiletic/burn"
const PROFILE_URL := "https://github.com/sebastianmiletic"
## Other public projects by the author: [name, url, one line].
const PROJECTS := [
	["Termatica", "https://github.com/sebastianmiletic/termatica",
		"A native macOS terminal under 2 MB: PTYs, SSH, splits, AppKit + Metal rendering. Ranked #1 for measured aggregate throughput and memory in a reproducible six-terminal comparison."],
	["Open Cloud", "https://github.com/sebastianmiletic/opencloud",
		"A cross-platform streaming tracker built with Tauri, with Supabase sync, for macOS, Windows and Linux."],
	["Sparkdeck", "https://github.com/sebastianmiletic/sparkdeck",
		"A pocket-sized open-source Arch Linux cyberdeck for coding, emulation, radio decoding and security work."],
	["Hyprland dotfiles", "https://github.com/sebastianmiletic/hyprland-dotfiles",
		"A Hyprland + Quickshell desktop."],
	["Ryft", "https://github.com/sebastianmiletic/ryft",
		"A Hyprland-style tiling look for macOS."],
	["HumanGPT", "https://github.com/sebastianmiletic/humangpt",
		"An offline-first writing editor with adaptive edit levels."],
	["Macrosoft Access", "https://github.com/sebastianmiletic/macrosoftaccess",
		"A local-first database workspace for macOS."],
	["battlecode-cli", "https://github.com/sebastianmiletic/battlecode-cli",
		"A terminal dashboard for UNSW Battlecode."],
]


## The credits (title screen and end of the campaign). Links are [url] tags:
## connect the label's meta_clicked to open_link().
static func credits_bbcode() -> String:
	var a := UiTheme.ACCENT.to_html(false)
	var hot := UiTheme.ACCENT_HOT.to_html(false)
	var dim := UiTheme.TEXT_DIM.to_html(false)
	var head := func(t: String) -> String: return "[font_size=17][color=#%s]%s[/color][/font_size]" % [a, t]
	var link := func(url: String, label := "") -> String:
		return "[url=%s][color=#%s]%s[/color][/url]" % [url, hot, label if label != "" else url.trim_prefix("https://")]
	var lines := [
		"[font_size=26][color=#%s]BURN[/color][/font_size]" % a,
		"[i]A tale told in ash.[/i]",
		"",
		head.call("CREATED BY"),
		"[font_size=20]Sebastian Miletic[/font_size]",
		"Software builder focused on native apps, terminals and Linux.",
		"[color=#%s]Languages[/color]  Objective-C · C · Rust · JavaScript · TypeScript · QML" % dim,
		"[color=#%s]Desktop[/color]  AppKit · Metal · Tauri · Hyprland" % dim,
		"[color=#%s]Platforms[/color]  macOS · Windows · Linux" % dim,
		"[color=#%s]Values[/color]  native · compact · measurable" % dim,
		"",
		"Design, code, world generation, models, shaders, sound and music were made for this project.",
		"Everything you see is generated at runtime; the music is fully synthesised.",
		"",
		head.call("SOURCE"),
		"BURN on GitHub  " + link.call(REPO_URL),
		"Profile  " + link.call(PROFILE_URL),
		"",
		head.call("MORE FROM THE AUTHOR"),
	]
	for p: Array in PROJECTS:
		lines.append("[b]%s[/b]" % link.call(p[1], p[0]))
		lines.append("[color=#%s]%s[/color]" % [dim, p[2]])
		lines.append("")
	lines.append_array([
		head.call("ENGINE"),
		"Godot Engine 4.7  MIT licence, © Juan Linietsky, Ariel Manzur and Godot Engine contributors.  " + link.call("https://godotengine.org", "godotengine.org"),
		"",
		head.call("FONTS"),
		"JetBrains Mono  SIL Open Font License 1.1, © The JetBrains Mono Project Authors.",
		"Cinzel  SIL Open Font License 1.1, © The Cinzel Project Authors.",
		"",
		head.call("SOUND"),
		"Impact Sounds and RPG Audio by Kenney  CC0 1.0  " + link.call("https://kenney.nl", "kenney.nl"),
		"Park Ambiences (river) by thimras, Crickets Ambient Noise by wolfgang  CC0 1.0  " + link.call("https://opengameart.org", "opengameart.org"),
		"Everything else is synthesised in the game.",
		"",
		head.call("TEXTURES"),
		"Architecture, bark, rock and terrain textures from Poly Haven  CC0 1.0  " + link.call("https://polyhaven.com", "polyhaven.com"),
		"The leaf atlas is painted procedurally.",
		"",
		head.call("TECHNIQUES"),
		"ASCII edge-glyph approach after AcerolaFX ASCII  MIT licence, © Garrett Gunnell.",
		"",
		head.call("THANKS"),
		"To everyone who carried a torch into the dark.",
	])
	return "\n".join(lines)


## Opens a credits link in the system browser (only the web links above).
static func open_link(meta: Variant) -> void:
	var url := str(meta)
	if url.begins_with("https://"):
		OS.shell_open(url)


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0, 0.9)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	add_child(EmberBackground.new())
	_title = BurningTitle.new()
	_title.text = "VICTORY"
	_title.anchor_left = 0.5
	_title.anchor_right = 0.5
	_title.offset_left = -420
	_title.offset_right = 420
	_title.offset_top = 40
	_title.offset_bottom = 230
	_title.progress = 0.0
	add_child(_title)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.anchor_left = 0.5
	_clip.anchor_right = 0.5
	_clip.anchor_top = 0.0
	_clip.anchor_bottom = 1.0
	_clip.offset_left = -360
	_clip.offset_right = 360
	_clip.offset_top = 250
	_clip.offset_bottom = -90
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_roll = VBoxContainer.new()
	_roll.add_theme_constant_override("separation", 6)
	_roll.custom_minimum_size.x = 720
	_clip.add_child(_roll)
	var intro := UiTheme.title("The Crown of Hades is yours. The underworld bows.", 20, UiTheme.ACCENT_HOT, 600)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.custom_minimum_size.x = 720
	_roll.add_child(intro)
	_roll.add_child(UiTheme.spacer(30))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size.x = 720
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_color_override("default_color", UiTheme.TEXT)
	text.text = "[center]%s[/center]" % credits_bbcode()
	text.meta_underlined = true
	text.meta_clicked.connect(VictoryScreen.open_link)
	_roll.add_child(text)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_buttons.offset_left = -300
	_buttons.offset_right = 300
	_buttons.offset_top = -70
	_buttons.offset_bottom = -30
	_buttons.add_child(UiTheme.button("Keep exploring", close, 16))
	_buttons.add_child(UiTheme.button("Return to title", func() -> void: UiContext.game_call("quit_to_menu"), 16))
	add_child(_buttons)
	UiContext.on("campaign_won", open)


func open() -> void:
	is_open = true
	visible = true
	_t = 0.0
	_roll.position = Vector2(0, _clip.size.y)
	UiContext.set_ui_open(true)
	UiContext.call_on(get_node_or_null("/root/Audio"), "set_music", ["victory"])


func close() -> void:
	is_open = false
	visible = false
	UiContext.set_ui_open(false)


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	_title.progress = smoothstep(0.2, 2.8, _t)
	if _t > 2.5:
		_roll.position.y -= ROLL_SPEED * delta
		if _roll.position.y < -_roll.size.y:
			_roll.position.y = _clip.size.y
	_buttons.modulate.a = clampf((_t - 3.0) / 1.0, 0.0, 1.0)
