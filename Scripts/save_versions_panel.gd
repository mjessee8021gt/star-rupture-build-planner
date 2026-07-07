extends Control

# Save Engine V2 - Version History overlay.
#
# A full-screen modal that lists the current document's saved versions, shows a
# color-coded diff between the selected version and the current plan, and lets
# the user restore any version. Diff colors reuse the building trim palette:
# extraction (added), crafting (removed), processing (modified) - matching how
# buildings are outlined elsewhere so the language is consistent.
#
# The panel is view-only over the version store: it reads history + current
# state from Main and asks Main to perform restores, keeping all mutation in one
# place.

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")
const SaveVersionStore = preload("res://Scripts/save_version_store.gd")

const COLOR_ADDED := Palette.BUILDING_OUTLINE_EXTRACTION
const COLOR_REMOVED := Palette.BUILDING_OUTLINE_CRAFTING
const COLOR_MODIFIED := Palette.BUILDING_OUTLINE_PROCESSING

const KIND_LABELS := {
	"base": "baseline",
	"manual": "saved",
	"auto": "autosave",
	"pre_destructive": "pre-delete",
	"restore": "restored",
}

const SCALAR_LABELS := {
	"heat": "Heat",
	"power": "Power",
	"cost_bbm": "BBM cost",
	"cost_ibm": "IBM cost",
	"cost_meteor_cores": "Meteor cores",
}

var _main: Node = null
var _ui_scale := 1.0
var _built := false

var _selected_version_id := -1
var _confirm_pending := false

var _panel: PanelContainer = null
var _title_label: Label = null
var _version_list: VBoxContainer = null
var _diff_label: RichTextLabel = null
var _compare_label: Label = null
var _restore_button: Button = null
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


func open() -> void:
	_ensure_built()
	_confirm_pending = false
	_status_label.text = ""
	_refresh_versions()
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func close() -> void:
	visible = false


# --- UI construction ---------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	name = "VersionHistoryOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	# A CenterContainer filling the overlay keeps the panel centered regardless
	# of its content-driven size (PRESET_CENTER would anchor its top-left to the
	# screen center and let it grow off-screen).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	center.add_child(_panel)

	var root := VBoxContainer.new()
	_panel.add_child(root)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Version History"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_button := _make_button("Close")
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Left: scrollable version list.
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size = Vector2(_scaled(260.0), _scaled(360.0))
	body.add_child(list_scroll)

	_version_list = VBoxContainer.new()
	_version_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_version_list)

	# Right: comparison header + diff view.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	_compare_label = Label.new()
	_compare_label.text = "Select a version to compare with the current plan."
	right.add_child(_compare_label)

	var diff_scroll := ScrollContainer.new()
	diff_scroll.custom_minimum_size = Vector2(_scaled(420.0), _scaled(330.0))
	diff_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(diff_scroll)

	_diff_label = RichTextLabel.new()
	_diff_label.bbcode_enabled = true
	_diff_label.fit_content = true
	_diff_label.scroll_active = false
	_diff_label.selection_enabled = true
	_diff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diff_scroll.add_child(_diff_label)

	# Footer: restore + status.
	var footer := HBoxContainer.new()
	root.add_child(footer)

	_restore_button = _make_button("Restore selected version")
	_restore_button.pressed.connect(_on_restore_pressed)
	_restore_button.disabled = true
	footer.add_child(_restore_button)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status_label)

	_style()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_styled_buttons.append(button)
	return button


# --- Data / interaction ------------------------------------------------------

func _history() -> Dictionary:
	if _main != null and _main.has_method("get_save_history"):
		var h = _main.call("get_save_history")
		if h is Dictionary:
			return h
	return {}


func _refresh_versions() -> void:
	for child in _version_list.get_children():
		child.queue_free()
	_styled_buttons = _styled_buttons.filter(func(b): return is_instance_valid(b) and b.get_parent() != _version_list)

	var history := _history()
	if history.is_empty():
		var empty := Label.new()
		empty.text = "No saved versions yet.\nVersions are captured on save, on a\ntimer, and before deletions."
		_version_list.add_child(empty)
		_restore_button.disabled = true
		_diff_label.text = ""
		return

	var versions := SaveVersionStore.list_versions(history)
	versions.reverse()  # newest first
	for v in versions:
		_version_list.add_child(_make_version_row(v))

	# Keep the current selection if it still exists, else default to newest.
	if not SaveVersionStore.has_version(history, _selected_version_id):
		_selected_version_id = int(versions[0]["version_id"]) if not versions.is_empty() else -1
	if _selected_version_id >= 0:
		_select_version(_selected_version_id)


func _make_version_row(v: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vid := int(v.get("version_id", 0))
	var kind := String(v.get("kind", "auto"))
	var kind_label := String(KIND_LABELS.get(kind, kind))
	var label := String(v.get("label", ""))
	var head_marker := "  ● current" if bool(v.get("is_head", false)) else ""
	button.text = "v%d · %s [%s]%s\n%s" % [vid, label, kind_label, head_marker, _format_time(float(v.get("created_unix", 0.0)))]
	button.button_pressed = vid == _selected_version_id
	button.pressed.connect(_select_version.bind(vid))
	_styled_buttons.append(button)
	return button


func _select_version(version_id: int) -> void:
	_selected_version_id = version_id
	_confirm_pending = false
	_restore_button.text = "Restore selected version"
	_restore_button.disabled = false

	# Reflect the selection in the toggle buttons.
	for child in _version_list.get_children():
		if child is Button and child.toggle_mode:
			child.set_pressed_no_signal(child.text.begins_with("v%d ·" % version_id))

	var history := _history()
	var from_state := SaveVersionStore.state_at(history, version_id)
	var current_state: Dictionary = {}
	if _main != null and _main.has_method("get_current_plan_state"):
		current_state = _main.call("get_current_plan_state")

	var is_head := int(history.get("head_version_id", -1)) == version_id
	_compare_label.text = "Comparing v%d → current plan" % version_id
	var diff := SaveVersionStore.diff_states(from_state, current_state)
	_render_diff(diff, is_head)


func _on_restore_pressed() -> void:
	if _selected_version_id < 0:
		return
	if not _confirm_pending:
		_confirm_pending = true
		_restore_button.text = "Click again to confirm restore"
		_status_label.text = "This replaces the current plan (kept as a new version, so it's reversible)."
		return

	_confirm_pending = false
	_restore_button.text = "Restore selected version"
	var ok := false
	if _main != null and _main.has_method("restore_save_version"):
		ok = bool(_main.call("restore_save_version", _selected_version_id))
	if ok:
		_status_label.text = "Restored v%d." % _selected_version_id
		_refresh_versions()
	else:
		_status_label.text = "Restore failed."


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


# --- Diff rendering ----------------------------------------------------------

func _render_diff(diff: Dictionary, is_head: bool) -> void:
	if is_head:
		_diff_label.text = "[i]This is the current plan — nothing to compare.[/i]"
		return
	if SaveVersionStore.diff_is_empty(diff):
		_diff_label.text = "[i]No differences from the current plan.[/i]"
		return

	var lines: Array[String] = []
	var buildings = diff.get("buildings", {})
	var annotations = diff.get("annotations", {})
	var paths = diff.get("paths", {})
	var scalars = diff.get("scalars", {})

	# Added (in current, missing from selected version).
	var added_lines: Array[String] = []
	for uid in buildings.get("added", {}):
		added_lines.append("  • " + _building_label(buildings["added"][uid]))
	for id in annotations.get("added", {}):
		added_lines.append("  • Note: " + _annotation_label(annotations["added"][id]))
	for p in paths.get("added", []):
		added_lines.append("  • " + _path_label(p))
	if not added_lines.is_empty():
		lines.append(_heading("Added", COLOR_ADDED, added_lines.size()))
		lines.append_array(added_lines)

	# Removed (in selected version, gone from current).
	var removed_lines: Array[String] = []
	for uid in buildings.get("removed", {}):
		removed_lines.append("  • " + _building_label(buildings["removed"][uid]))
	for id in annotations.get("removed", {}):
		removed_lines.append("  • Note: " + _annotation_label(annotations["removed"][id]))
	for p in paths.get("removed", []):
		removed_lines.append("  • " + _path_label(p))
	if not removed_lines.is_empty():
		lines.append(_heading("Removed", COLOR_REMOVED, removed_lines.size()))
		lines.append_array(removed_lines)

	# Modified.
	var modified_lines: Array[String] = []
	for uid in buildings.get("modified", {}):
		var entry = buildings["modified"][uid]
		modified_lines.append("  • %s — %s" % [_building_label(entry.get("after", {})), _field_summary(entry.get("fields", {}))])
	for p in paths.get("modified", []):
		modified_lines.append("  • " + _path_label(p.get("after", p)))
	for key in scalars:
		modified_lines.append("  • %s: %s → %s" % [SCALAR_LABELS.get(key, key), str(scalars[key][0]), str(scalars[key][1])])
	if not modified_lines.is_empty():
		lines.append(_heading("Modified", COLOR_MODIFIED, modified_lines.size()))
		lines.append_array(modified_lines)

	_diff_label.text = "\n".join(lines)


func _heading(title: String, color: Color, count: int) -> String:
	return "\n[b][color=#%s]%s (%d)[/color][/b]" % [color.to_html(false), title, count]


func _building_label(building: Dictionary) -> String:
	var cell = building.get("anchor_cell", [0, 0])
	var cx := 0
	var cy := 0
	if cell is Array and cell.size() >= 2:
		cx = int(cell[0])
		cy = int(cell[1])
	return "%s @ (%d, %d)" % [_pretty_id(String(building.get("id", "building"))), cx, cy]


func _annotation_label(annotation: Dictionary) -> String:
	var text := String(annotation.get("text", "")).strip_edges()
	if text == "":
		return "(empty note)"
	if text.length() > 40:
		text = text.substr(0, 37) + "…"
	return "\"%s\"" % text


func _path_label(path: Dictionary) -> String:
	var rail := int(path.get("rail_version", -1))
	var rail_text := " (V%d rail)" % rail if rail >= 1 else ""
	return "Rail: %s → %s%s" % [String(path.get("from_port", "?")), String(path.get("to_port", "?")), rail_text]


func _field_summary(fields: Dictionary) -> String:
	var names: Array[String] = []
	for key in fields:
		match key:
			"position", "anchor_cell":
				names.append("moved")
			"rotation_degrees", "rotated_tick":
				names.append("rotated")
			"is_alternate":
				names.append("mirrored")
			"recipe":
				names.append("recipe")
			"purity":
				names.append("purity")
			"core_level":
				names.append("core level")
			"footprint":
				names.append("footprint")
			_:
				names.append(str(key))
	# De-duplicate while preserving order (position+anchor_cell both map to moved).
	var seen: Dictionary = {}
	var out: Array[String] = []
	for n in names:
		if not seen.has(n):
			seen[n] = true
			out.append(n)
	return ", ".join(out)


func _pretty_id(id: String) -> String:
	return id.replace("_", " ").capitalize()


func _format_time(unix: float) -> String:
	if unix <= 0.0:
		return ""
	return Time.get_datetime_string_from_unix_time(int(unix), true).replace("T", "  ")


# --- Styling -----------------------------------------------------------------

func _style() -> void:
	if _panel != null:
		_panel.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(10), _scaled_int(1)))
	if _title_label != null:
		_title_label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		UiScale.apply_font_size(_title_label, &"font_size", 18, _ui_scale, true)
	if _compare_label != null:
		_compare_label.add_theme_color_override("font_color", Palette.TEXT_BADGE)
		UiScale.apply_font_size(_compare_label, &"font_size", 13, _ui_scale, true)
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		UiScale.apply_font_size(_status_label, &"font_size", 12, _ui_scale, true)
	if _diff_label != null:
		_diff_label.add_theme_color_override("default_color", Palette.TEXT_PRIMARY)
		UiScale.apply_font_size(_diff_label, &"normal_font_size", 13, _ui_scale, true)
		UiScale.apply_font_size(_diff_label, &"bold_font_size", 13, _ui_scale, true)
	for button in _styled_buttons:
		if button != null and is_instance_valid(button):
			_style_button(button)


func _style_button(button: BaseButton) -> void:
	UiScale.apply_font_size(button, &"font_size", 13, _ui_scale, true)
	button.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", Palette.TEXT_PRIMARY)
	button.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)
