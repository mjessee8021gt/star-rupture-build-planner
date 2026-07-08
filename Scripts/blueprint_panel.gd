extends Control

# Blueprint library overlay.
#
# A full-screen modal that lists the user's saved blueprints as cards (schematic
# thumbnail + name + counts), lets them save the current selection as a new
# blueprint, and per card: stamp it (arms the repeat-stamp tool and closes),
# rename, export to a file, or delete. Import brings an external .srbpb into the
# library.
#
# The panel is a thin view over main.gd, which owns the library, the selection,
# and the stamp tool; all mutation goes back through main so state lives in one
# place (mirrors save_versions_panel.gd).

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

var _main: Node = null
var _ui_scale := 1.0
var _built := false

var _renaming_id := ""
var _confirm_delete_id := ""

var _panel: PanelContainer = null
var _title_label: Label = null
var _name_edit: LineEdit = null
var _save_button: Button = null
var _import_button: Button = null
var _hint_label: Label = null
var _list: VBoxContainer = null
var _status_label: Label = null
var _styled_buttons: Array = []


func setup(main_ref: Node, ui_scale: float) -> void:
	_main = main_ref
	_ui_scale = maxf(ui_scale, 0.001)
	_ensure_built()


func _ready() -> void:
	visible = false
	_ensure_built()


func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	_ensure_built()
	_style()
	if visible:
		_refresh()


func open() -> void:
	_ensure_built()
	_confirm_delete_id = ""
	_renaming_id = ""
	_status_label.text = ""
	_name_edit.text = ""
	_refresh()
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func close() -> void:
	visible = false


# --- UI construction ---------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	name = "BlueprintLibraryOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	center.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", _scaled_int(8))
	_panel.add_child(root)

	# Header: title + close.
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Blueprints"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_button := _make_button("Close")
	close_button.pressed.connect(close)
	header.add_child(close_button)

	# Toolbar: save-from-selection + import.
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", _scaled_int(6))
	root.add_child(toolbar)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "New blueprint name…"
	_name_edit.custom_minimum_size = Vector2(_scaled(220.0), 0.0)
	_name_edit.text_submitted.connect(func(_t): _on_save_selection_pressed())
	toolbar.add_child(_name_edit)

	_save_button = _make_button("Save selection")
	_save_button.pressed.connect(_on_save_selection_pressed)
	toolbar.add_child(_save_button)

	_import_button = _make_button("Import…")
	_import_button.pressed.connect(_on_import_pressed)
	toolbar.add_child(_import_button)

	_hint_label = Label.new()
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_hint_label)

	# Scrollable list of blueprint cards.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(_scaled(560.0), _scaled(400.0))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", _scaled_int(6))
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_status_label = Label.new()
	root.add_child(_status_label)

	_style()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_styled_buttons.append(button)
	return button


# --- Data / interaction ------------------------------------------------------

func _entries() -> Array:
	if _main != null and _main.has_method("list_blueprints"):
		var e = _main.call("list_blueprints")
		if e is Array:
			return e
	return []


func _selection_available() -> bool:
	return _main != null and _main.has_method("blueprint_selection_available") and bool(_main.call("blueprint_selection_available"))


func _refresh() -> void:
	# Rebuild the whole list. queue_free is deferred, so freed card buttons still
	# report as children this frame; keep only still-valid buttons outside the
	# list (toolbar/header) so card buttons don't accumulate stale references.
	for child in _list.get_children():
		child.queue_free()
	_styled_buttons = _styled_buttons.filter(func(b): return is_instance_valid(b) and not _is_in_list(b))

	var can_save := _selection_available()
	_save_button.disabled = not can_save
	_hint_label.text = "Select buildings on the plan to save them as a blueprint." if not can_save else ""

	var entries := _entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No blueprints yet.\nSelect buildings and click \"Save selection\", or import a .srbpb file."
		_list.add_child(empty)
		_style()
		return

	for entry in entries:
		if entry is Dictionary:
			_list.add_child(_make_card(entry))
	_style()


func _is_in_list(node: Node) -> bool:
	return node != null and _list != null and _list.is_ancestor_of(node)


func _make_card(entry: Dictionary) -> Control:
	var id := String(entry.get("id", ""))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.BUTTON_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(8), _scaled_int(1)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _scaled_int(10))
	card.add_child(row)

	# Thumbnail.
	var thumb := TextureRect.new()
	var thumb_px := _scaled(96.0)
	thumb.custom_minimum_size = Vector2(thumb_px, thumb_px)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var texture := _thumbnail_for(id, bool(entry.get("has_thumbnail", false)))
	if texture != null:
		thumb.texture = texture
	row.add_child(thumb)

	# Middle: name/counts (or rename editor) + metadata.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mid)

	if _renaming_id == id:
		var rename_row := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.text = String(entry.get("name", ""))
		edit.custom_minimum_size = Vector2(_scaled(220.0), 0.0)
		edit.text_submitted.connect(func(t): _apply_rename(id, t))
		rename_row.add_child(edit)
		var ok := _make_button("Save")
		ok.pressed.connect(func(): _apply_rename(id, edit.text))
		rename_row.add_child(ok)
		var cancel := _make_button("Cancel")
		cancel.pressed.connect(func(): _renaming_id = ""; _refresh())
		rename_row.add_child(cancel)
		mid.add_child(rename_row)
		edit.call_deferred("grab_focus")
	else:
		var name_label := Label.new()
		name_label.text = String(entry.get("name", "(unnamed)"))
		_styled_labels_bold(name_label)
		mid.add_child(name_label)

	var counts := Label.new()
	counts.text = "%d buildings · %d rails · %d notes" % [
		int(entry.get("building_count", 0)),
		int(entry.get("rail_count", 0)),
		int(entry.get("annotation_count", 0)),
	]
	counts.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	mid.add_child(counts)

	var meta := Label.new()
	var bounds = entry.get("bounds", [0, 0])
	meta.text = "%s · %d×%d" % [_format_time(float(entry.get("updated_at_unix", 0.0))), int(bounds[0]), int(bounds[1])]
	meta.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	mid.add_child(meta)

	# Right: actions.
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", _scaled_int(4))
	row.add_child(actions)

	var stamp := _make_button("Stamp")
	stamp.pressed.connect(_on_stamp_pressed.bind(id))
	actions.add_child(stamp)

	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", _scaled_int(4))
	actions.add_child(secondary)

	var rename := _make_button("Rename")
	rename.pressed.connect(func(): _renaming_id = id; _confirm_delete_id = ""; _refresh())
	secondary.add_child(rename)

	var export := _make_button("Export")
	export.pressed.connect(_on_export_pressed.bind(id))
	secondary.add_child(export)

	var delete := _make_button("Delete" if _confirm_delete_id != id else "Confirm?")
	delete.pressed.connect(_on_delete_pressed.bind(id))
	secondary.add_child(delete)

	return card


func _thumbnail_for(id: String, has_thumbnail: bool) -> Texture2D:
	if not has_thumbnail or _main == null or not _main.has_method("load_blueprint"):
		return null
	var bp = _main.call("load_blueprint", id)
	if not (bp is Dictionary):
		return null
	var b64 := String(bp.get("thumbnail_png_b64", ""))
	if b64 == "":
		return null
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(b64)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _on_save_selection_pressed() -> void:
	if not _selection_available():
		_status_label.text = "Nothing selected to save."
		return
	var bp_name := _name_edit.text.strip_edges()
	if bp_name == "":
		bp_name = "Blueprint"
	var new_id := ""
	if _main != null and _main.has_method("create_blueprint_from_selection"):
		new_id = String(_main.call("create_blueprint_from_selection", bp_name, ""))
	if new_id == "":
		_status_label.text = "Could not save blueprint."
		return
	_name_edit.text = ""
	_status_label.text = "Saved \"%s\"." % bp_name
	_refresh()


func _on_stamp_pressed(id: String) -> void:
	if _main != null and _main.has_method("stamp_blueprint") and bool(_main.call("stamp_blueprint", id)):
		close()
	else:
		_status_label.text = "Could not start stamping."


func _apply_rename(id: String, new_name: String) -> void:
	var trimmed := new_name.strip_edges()
	if trimmed != "" and _main != null and _main.has_method("rename_blueprint"):
		_main.call("rename_blueprint", id, trimmed)
	_renaming_id = ""
	_refresh()


func _on_delete_pressed(id: String) -> void:
	if _confirm_delete_id != id:
		_confirm_delete_id = id
		_status_label.text = "Click Confirm to delete this blueprint."
		_refresh()
		return
	_confirm_delete_id = ""
	if _main != null and _main.has_method("delete_blueprint"):
		_main.call("delete_blueprint", id)
	_status_label.text = "Deleted."
	_refresh()


func _on_export_pressed(id: String) -> void:
	if _main != null and _main.has_method("export_blueprint"):
		_main.call("export_blueprint", id)
	_status_label.text = "Exporting…"


func _on_import_pressed() -> void:
	if _main != null and _main.has_method("import_blueprint"):
		_main.call("import_blueprint")


# Called by main after an async import (web) so the new entry shows up.
func notify_library_changed() -> void:
	if visible:
		_refresh()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


# --- Styling -----------------------------------------------------------------

func _styled_labels_bold(label: Label) -> void:
	label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	UiScale.apply_font_size(label, &"font_size", 15, _ui_scale, true)


func _style() -> void:
	if _panel != null:
		_panel.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(10), _scaled_int(1)))
	if _title_label != null:
		_title_label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		UiScale.apply_font_size(_title_label, &"font_size", 18, _ui_scale, true)
	for label in [_hint_label, _status_label]:
		if label != null:
			label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
			UiScale.apply_font_size(label, &"font_size", 12, _ui_scale, true)
	if _name_edit != null:
		UiScale.apply_font_size(_name_edit, &"font_size", 13, _ui_scale, true)
	for button in _styled_buttons:
		if button != null and is_instance_valid(button):
			_style_button(button)


func _style_button(button: BaseButton) -> void:
	UiScale.apply_font_size(button, &"font_size", 13, _ui_scale, true)
	button.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	button.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))


func _format_time(unix: float) -> String:
	if unix <= 0.0:
		return ""
	return Time.get_datetime_string_from_unix_time(int(unix), true).replace("T", "  ")


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)
