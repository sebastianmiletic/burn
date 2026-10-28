class_name PetNameDialog
extends UiModal
## A small "Name your pet" box: a text field and Name / Cancel. Opened by
## Pet commands; installed beside the shop screen (ShopScreen._build).

var _edit: LineEdit
var _done := Callable()


static func ensure(sibling: Node) -> void:
	var tree := sibling.get_tree()
	if tree == null or tree.get_first_node_in_group(&"pet_name_dialog") != null:
		return
	var parent := sibling.get_parent()
	if parent == null:
		return
	parent.add_child(PetNameDialog.new())


## Asks for a name; `done` gets the text when the player confirms.
static func ask(current: String, done: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var d := tree.get_first_node_in_group(&"pet_name_dialog") as PetNameDialog if tree != null else null
	if d == null:
		return
	d._done = done
	d.open()
	d._edit.text = current
	d._edit.select_all()
	d._edit.grab_focus.call_deferred()


func _init() -> void:
	panel_size = Vector2(460, 220)
	panel_title = ""
	add_to_group(&"pet_name_dialog")


func _build() -> void:
	ItemStyle.dress(self, "NAME YOUR COMPANION")
	content.add_theme_constant_override("separation", 14)
	content.add_child(UiTheme.label("What will you call it?", UiTheme.SIZE_BODY, ItemStyle.TEXT_DIM))
	_edit = LineEdit.new()
	_edit.max_length = 20
	_edit.custom_minimum_size = Vector2(0, 38)
	_edit.add_theme_font_size_override("font_size", 18)
	_edit.text_submitted.connect(func(_t: String) -> void: _confirm())
	content.add_child(_edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	row.add_child(ItemStyle.button("Cancel", close))
	row.add_child(ItemStyle.button("Name", _confirm, true))
	content.add_child(row)


func _confirm() -> void:
	var t := _edit.text.strip_edges()
	var cb := _done
	_done = Callable()
	close()
	if cb.is_valid() and t != "":
		cb.call(t)
