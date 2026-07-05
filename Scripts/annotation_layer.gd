extends Node2D

const Palette = preload("res://Scripts/palette.gd")
const TICK_TEXTURE := preload("res://Assets/SRBP_ANNOTATION_TICK.png")

const ANNOTATION_ACTION := &"Annotation"
const FORMAT_BBCODE := "bbcode"
const TARGET_CELL := "cell"
const TARGET_BUILDING := "building"
const BUILDING_UID_META := &"srbp_building_uid"
const TICK_CLICK_TARGET_SIZE := Vector2(32.0, 32.0)
const TICK_CLICK_TARGET_CENTER := Vector2(48.0, 16.0)
const EDITOR_SIZE := Vector2(340.0, 220.0)
const EDITOR_OFFSET := Vector2(18.0, 8.0)
const SCREEN_MARGIN := 12.0

@export var build_manager_path := NodePath("../BuildManager")
@export var editor_canvas_path := NodePath("../Camera2D/CanvasLayer")

var annotations: Array[Dictionary] = []
var annotation_mode_active := false

var _build_manager: Node = null
var _editor_canvas: Node = null
var _tick_nodes: Dictionary = {}
var _tick_material: ShaderMaterial
var _editor_panel: PanelContainer
var _text_edit: TextEdit
var _active_annotation_id := ""
var _edit_history_before: Dictionary = {}
var _refresh_queued := false
var _loading_editor_text := false
var _scene_input_guard_frames := 0


func _ready() -> void:
	z_index = 200
	_build_manager = get_node_or_null(build_manager_path)
	_editor_canvas = get_node_or_null(editor_canvas_path)
	_tick_material = _build_tick_material()
	_build_editor()
	_refresh_annotation_ticks()


func _process(_delta: float) -> void:
	_sync_editor_position()
	if _scene_input_guard_frames > 0:
		_scene_input_guard_frames -= 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ANNOTATION_ACTION, false, true):
		if _editor_has_focus():
			return
		toggle_annotation_mode()
		get_viewport().set_input_as_handled()
		return

	if not annotation_mode_active:
		return

	if event.is_action_pressed("Build Cancel", true) or _is_escape_key(event):
		set_annotation_mode(false)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("Build Confirm"):
		if _mouse_is_over_any_control():
			return
		_place_annotation_at_mouse()
		get_viewport().set_input_as_handled()


func is_interaction_active() -> bool:
	return annotation_mode_active or is_editor_open() or _scene_input_guard_frames > 0


func is_editor_open() -> bool:
	return _editor_panel != null and _editor_panel.visible


func toggle_annotation_mode() -> void:
	set_annotation_mode(not annotation_mode_active)


func set_annotation_mode(enabled: bool) -> void:
	annotation_mode_active = enabled
	if enabled:
		_cancel_conflicting_plan_tools()


func cancel_annotation_interaction(commit_editor := true) -> void:
	annotation_mode_active = false
	_close_editor(commit_editor)


func clear_annotations() -> void:
	_close_editor(false)
	annotation_mode_active = false
	annotations.clear()
	for tick in _tick_nodes.values():
		if tick is Node:
			(tick as Node).queue_free()
	_tick_nodes.clear()


func serialize_annotations() -> Array[Dictionary]:
	_flush_editor_text()
	var out: Array[Dictionary] = []
	for annotation in annotations:
		out.append(_serialize_annotation(annotation))
	return out


func load_annotations(saved_annotations: Variant) -> void:
	clear_annotations()
	if not (saved_annotations is Array):
		return

	for entry in saved_annotations:
		if not (entry is Dictionary):
			continue
		var annotation := _normalize_annotation(entry)
		if annotation.is_empty():
			continue
		annotations.append(annotation)

	_queue_refresh_annotation_ticks()


func refresh_annotations() -> void:
	_queue_refresh_annotation_ticks()


func _place_annotation_at_mouse() -> void:
	var anchor_cell := _world_to_cell(get_global_mouse_position())
	var existing_id := _find_annotation_id_for_cell(anchor_cell)
	if existing_id != "":
		_open_editor(existing_id)
		return

	var history_before := _capture_history_state()
	var annotation := _make_annotation(anchor_cell)
	annotations.append(annotation)
	_queue_refresh_annotation_ticks()
	_open_editor(String(annotation["id"]))
	_commit_history_action("Annotation created", history_before)


func _make_annotation(anchor_cell: Vector2i) -> Dictionary:
	var occupant := _get_building_at_cell(anchor_cell)
	var target_type := TARGET_CELL
	var target_building_uid := ""
	if occupant != null:
		target_type = TARGET_BUILDING
		target_building_uid = _ensure_building_uid(occupant)

	var now := Time.get_unix_time_from_system()
	return {
		"id": _generate_annotation_id(),
		"target_type": target_type,
		"anchor_cell": [anchor_cell.x, anchor_cell.y],
		"target_building_uid": target_building_uid,
		"text": "",
		"format": FORMAT_BBCODE,
		"created_at_unix": now,
		"updated_at_unix": now
	}


func _normalize_annotation(entry: Dictionary) -> Dictionary:
	var anchor_cell := _cell_from_variant(entry.get("anchor_cell", entry.get("anchor", [0, 0])))
	var id := String(entry.get("id", ""))
	if id == "":
		id = _generate_annotation_id()

	var target_type := String(entry.get("target_type", TARGET_CELL))
	if target_type != TARGET_BUILDING:
		target_type = TARGET_CELL

	return {
		"id": id,
		"target_type": target_type,
		"anchor_cell": [anchor_cell.x, anchor_cell.y],
		"target_building_uid": String(entry.get("target_building_uid", "")),
		"text": String(entry.get("text", "")),
		"format": String(entry.get("format", FORMAT_BBCODE)),
		"created_at_unix": float(entry.get("created_at_unix", 0.0)),
		"updated_at_unix": float(entry.get("updated_at_unix", 0.0))
	}


func _serialize_annotation(annotation: Dictionary) -> Dictionary:
	var anchor_cell := _get_annotation_anchor_cell(annotation)
	return {
		"id": String(annotation.get("id", "")),
		"target_type": String(annotation.get("target_type", TARGET_CELL)),
		"anchor_cell": [anchor_cell.x, anchor_cell.y],
		"target_building_uid": String(annotation.get("target_building_uid", "")),
		"text": String(annotation.get("text", "")),
		"format": String(annotation.get("format", FORMAT_BBCODE)),
		"created_at_unix": float(annotation.get("created_at_unix", 0.0)),
		"updated_at_unix": float(annotation.get("updated_at_unix", 0.0))
	}


func _queue_refresh_annotation_ticks() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_annotation_ticks")


func _refresh_annotation_ticks() -> void:
	_refresh_queued = false
	var live_ids := {}
	for annotation in annotations:
		var id := String(annotation.get("id", ""))
		if id == "":
			continue
		live_ids[id] = true
		var tick := _get_or_create_tick(id)
		tick.position = _cell_to_world(_get_annotation_display_cell(annotation))
		tick.visible = true

	for id in _tick_nodes.keys().duplicate():
		if live_ids.has(id):
			continue
		var tick_node = _tick_nodes[id]
		if tick_node is Node:
			(tick_node as Node).queue_free()
		_tick_nodes.erase(id)


func _get_or_create_tick(annotation_id: String) -> Node2D:
	if _tick_nodes.has(annotation_id):
		var existing := _tick_nodes[annotation_id] as Node2D
		if existing != null and is_instance_valid(existing):
			return existing

	var tick := Node2D.new()
	tick.name = "AnnotationTick_%s" % annotation_id
	tick.z_index = 0

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = TICK_TEXTURE
	sprite.centered = false
	sprite.material = _tick_material
	tick.add_child(sprite)

	var area := Area2D.new()
	area.name = "HitArea"
	area.input_pickable = true
	area.position = TICK_CLICK_TARGET_CENTER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = TICK_CLICK_TARGET_SIZE
	shape.shape = rect
	area.add_child(shape)
	area.input_event.connect(_on_tick_input_event.bind(annotation_id))
	tick.add_child(area)

	add_child(tick)
	_tick_nodes[annotation_id] = tick
	return tick


func _on_tick_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, annotation_id: String) -> void:
	if event.is_action_pressed("Build Confirm"):
		_open_editor(annotation_id)
		get_viewport().set_input_as_handled()


func _build_tick_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 annotation_color : source_color;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(annotation_color.rgb, annotation_color.a * tex.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("annotation_color", Palette.ACCESSIBLE_ANNOTATIONS)
	return material


func _build_editor() -> void:
	if _editor_canvas == null:
		return

	_editor_panel = PanelContainer.new()
	_editor_panel.name = "AnnotationEditor"
	_editor_panel.visible = false
	_editor_panel.custom_minimum_size = EDITOR_SIZE
	_editor_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_editor_panel.z_index = 4096
	_editor_panel.add_theme_stylebox_override(
		"panel",
		Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.ACCESSIBLE_ANNOTATIONS, 8, 2)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_editor_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	stack.add_child(toolbar)

	for button_data in [
		{"label": "B", "prefix": "[b]", "suffix": "[/b]", "tooltip": "Bold"},
		{"label": "I", "prefix": "[i]", "suffix": "[/i]", "tooltip": "Italic"},
		{"label": "U", "prefix": "[u]", "suffix": "[/u]", "tooltip": "Underline"}
	]:
		var format_button := Button.new()
		format_button.text = String(button_data["label"])
		format_button.tooltip_text = String(button_data["tooltip"])
		format_button.custom_minimum_size = Vector2(34, 30)
		format_button.pressed.connect(_insert_text_markup.bind(String(button_data["prefix"]), String(button_data["suffix"])))
		toolbar.add_child(format_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.tooltip_text = "Delete annotation"
	delete_button.pressed.connect(_delete_active_annotation)
	toolbar.add_child(delete_button)

	var done_button := Button.new()
	done_button.text = "Done"
	done_button.tooltip_text = "Close annotation"
	done_button.pressed.connect(_on_editor_done_pressed)
	toolbar.add_child(done_button)

	_text_edit = TextEdit.new()
	_text_edit.custom_minimum_size = Vector2(320, 150)
	_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.text_changed.connect(_on_editor_text_changed)
	stack.add_child(_text_edit)

	_editor_canvas.add_child(_editor_panel)


func _open_editor(annotation_id: String) -> void:
	_cancel_build_manager_pointer_interaction()
	_finalize_editor_edits()
	var annotation_index := _get_annotation_index_by_id(annotation_id)
	if annotation_index < 0:
		return

	var annotation := annotations[annotation_index]
	annotation_mode_active = false
	_active_annotation_id = annotation_id
	_edit_history_before = _capture_history_state()
	_loading_editor_text = true
	_text_edit.text = String(annotation.get("text", ""))
	_loading_editor_text = false
	_editor_panel.visible = true
	_sync_editor_position()
	_text_edit.grab_focus()
	_text_edit.set_caret_line(_text_edit.get_line_count() - 1)
	_text_edit.set_caret_column(_text_edit.get_line(_text_edit.get_line_count() - 1).length())


func _close_editor(commit_history := true) -> void:
	if not is_editor_open():
		_active_annotation_id = ""
		_edit_history_before = {}
		return

	_flush_editor_text()
	_editor_panel.visible = false
	_scene_input_guard_frames = 2
	_cancel_build_manager_pointer_interaction()
	if commit_history:
		_finalize_editor_edits()
	else:
		_active_annotation_id = ""
		_edit_history_before = {}


func _finalize_editor_edits() -> void:
	if _active_annotation_id == "":
		return
	_flush_editor_text()
	if not _edit_history_before.is_empty():
		_commit_history_action("Annotation edited", _edit_history_before)
	_active_annotation_id = ""
	_edit_history_before = {}


func _flush_editor_text() -> void:
	if _active_annotation_id == "" or _text_edit == null:
		return
	var annotation_index := _get_annotation_index_by_id(_active_annotation_id)
	if annotation_index < 0:
		return
	var annotation := annotations[annotation_index].duplicate(true)
	var next_text := _text_edit.text
	if String(annotation.get("text", "")) == next_text:
		return
	annotation["text"] = next_text
	annotation["updated_at_unix"] = Time.get_unix_time_from_system()
	annotations[annotation_index] = annotation


func _on_editor_text_changed() -> void:
	if _loading_editor_text:
		return
	_flush_editor_text()


func _on_editor_done_pressed() -> void:
	_close_editor(true)


func _delete_active_annotation() -> void:
	if _active_annotation_id == "":
		return

	var history_before := _capture_history_state()
	for i in range(annotations.size() - 1, -1, -1):
		if String(annotations[i].get("id", "")) == _active_annotation_id:
			annotations.remove_at(i)
			break

	var tick = _tick_nodes.get(_active_annotation_id)
	if tick is Node:
		(tick as Node).queue_free()
	_tick_nodes.erase(_active_annotation_id)
	_active_annotation_id = ""
	_edit_history_before = {}
	if _editor_panel != null:
		_editor_panel.visible = false
	_scene_input_guard_frames = 2
	_cancel_build_manager_pointer_interaction()
	_commit_history_action("Annotation deleted", history_before)


func _insert_text_markup(prefix: String, suffix: String) -> void:
	if _text_edit == null:
		return
	var selected_text := _text_edit.get_selected_text()
	if selected_text == "":
		_text_edit.insert_text_at_caret(prefix + suffix)
		_text_edit.set_caret_column(maxi(0, _text_edit.get_caret_column() - suffix.length()))
	else:
		_text_edit.insert_text_at_caret(prefix + selected_text + suffix)
	_flush_editor_text()
	_text_edit.grab_focus()


func _sync_editor_position() -> void:
	if not is_editor_open() or _active_annotation_id == "":
		return

	var annotation := _get_annotation_by_id(_active_annotation_id)
	if annotation.is_empty():
		return

	var world_pos := _cell_to_world(_get_annotation_display_cell(annotation))
	var screen_pos := get_viewport().get_canvas_transform() * world_pos
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	var next_position := screen_pos + EDITOR_OFFSET
	next_position.x = clampf(next_position.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, viewport_size.x - EDITOR_SIZE.x - SCREEN_MARGIN))
	next_position.y = clampf(next_position.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, viewport_size.y - EDITOR_SIZE.y - SCREEN_MARGIN))
	_editor_panel.position = next_position


func _find_annotation_id_for_cell(anchor_cell: Vector2i) -> String:
	var display_cell := _get_display_cell_for_anchor(anchor_cell)
	for annotation in annotations:
		if _get_annotation_display_cell(annotation) == display_cell:
			return String(annotation.get("id", ""))
	return ""


func _get_annotation_by_id(annotation_id: String) -> Dictionary:
	var annotation_index := _get_annotation_index_by_id(annotation_id)
	if annotation_index >= 0:
		return annotations[annotation_index]
	return {}


func _get_annotation_index_by_id(annotation_id: String) -> int:
	for i in range(annotations.size()):
		var annotation := annotations[i]
		if String(annotation.get("id", "")) == annotation_id:
			return i
	return -1


func _get_annotation_display_cell(annotation: Dictionary) -> Vector2i:
	if String(annotation.get("target_type", TARGET_CELL)) == TARGET_BUILDING:
		var building := _get_building_by_uid(String(annotation.get("target_building_uid", "")))
		if building != null:
			return _get_top_right_cell_for_building(building)
	return _get_display_cell_for_anchor(_get_annotation_anchor_cell(annotation))


func _get_display_cell_for_anchor(anchor_cell: Vector2i) -> Vector2i:
	var occupant := _get_building_at_cell(anchor_cell)
	if occupant != null:
		return _get_top_right_cell_for_building(occupant)
	return anchor_cell


func _get_annotation_anchor_cell(annotation: Dictionary) -> Vector2i:
	return _cell_from_variant(annotation.get("anchor_cell", [0, 0]))


func _get_top_right_cell_for_building(building: Node2D) -> Vector2i:
	if _build_manager == null:
		return _world_to_cell(building.global_position)

	var anchor_cell := _world_to_cell(building.global_position)
	if _build_manager.has_method("_anchor_cell_from_building_position"):
		anchor_cell = _build_manager.call("_anchor_cell_from_building_position", building, building.global_position)

	var cells: Array = []
	if _build_manager.has_method("get_building_cells"):
		var raw_cells = _build_manager.call("get_building_cells", building, anchor_cell)
		if raw_cells is Array:
			cells = raw_cells
	if cells.is_empty():
		return anchor_cell

	var best_cell: Vector2i = cells[0]
	for cell in cells:
		if not (cell is Vector2i):
			continue
		if cell.x > best_cell.x or (cell.x == best_cell.x and cell.y < best_cell.y):
			best_cell = cell
	return best_cell


func _get_building_at_cell(cell: Vector2i) -> Node2D:
	if _build_manager == null or not _build_manager.has_method("get_building_at_cells"):
		return null
	var building = _build_manager.call("get_building_at_cells", cell)
	return building as Node2D


func _get_building_by_uid(uid: String) -> Node2D:
	if uid == "" or _build_manager == null:
		return null
	var occupied = _build_manager.get("occupied_cells")
	if not (occupied is Dictionary):
		return null

	var seen := {}
	var occupied_cells := occupied as Dictionary
	for building in occupied_cells.values():
		if not (building is Node2D):
			continue
		if seen.has(building):
			continue
		seen[building] = true
		if (building as Node2D).has_meta(BUILDING_UID_META) and String((building as Node2D).get_meta(BUILDING_UID_META)) == uid:
			return building as Node2D
	return null


func _world_to_cell(pos: Vector2) -> Vector2i:
	if _build_manager != null and _build_manager.has_method("world_to_cell"):
		return _build_manager.call("world_to_cell", pos)
	return Vector2i(floor(pos.x / 64.0), floor(pos.y / 64.0))


func _cell_to_world(cell: Vector2i) -> Vector2:
	if _build_manager != null and _build_manager.has_method("cell_to_world"):
		return _build_manager.call("cell_to_world", cell)
	return Vector2(cell * 64)


func _cell_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _ensure_building_uid(building: Node) -> String:
	if building == null:
		return ""
	if building.has_meta(BUILDING_UID_META):
		var existing := String(building.get_meta(BUILDING_UID_META))
		if existing != "":
			return existing
	var uid := "bldg_%d_%d" % [Time.get_ticks_usec(), randi()]
	building.set_meta(BUILDING_UID_META, uid)
	return uid


func _generate_annotation_id() -> String:
	return "ann_%d_%d" % [Time.get_ticks_usec(), randi()]


func _capture_history_state() -> Dictionary:
	var main_scene := get_parent()
	if main_scene == null or not main_scene.has_method("_capture_history_state"):
		return {}
	var captured = main_scene.call("_capture_history_state")
	return captured if captured is Dictionary else {}


func _commit_history_action(label: String, before_state: Dictionary) -> void:
	var main_scene := get_parent()
	if main_scene == null or not main_scene.has_method("_commit_history_action"):
		return
	main_scene.call("_commit_history_action", label, before_state)


func _cancel_conflicting_plan_tools() -> void:
	var main_scene := get_parent()
	if main_scene == null:
		return
	var build_manager := main_scene.get_node_or_null("BuildManager")
	if build_manager != null and build_manager.has_method("cancel_build"):
		build_manager.call("cancel_build")
	_cancel_build_manager_pointer_interaction()
	var path_manager := main_scene.get_node_or_null("PathManager")
	if path_manager != null and path_manager.has_method("cancel_active_path_drag"):
		path_manager.call("cancel_active_path_drag")


func _cancel_build_manager_pointer_interaction() -> void:
	var main_scene := get_parent()
	if main_scene == null:
		return
	var build_manager := main_scene.get_node_or_null("BuildManager")
	if build_manager != null and build_manager.has_method("cancel_pointer_interaction"):
		build_manager.call("cancel_pointer_interaction")


func _mouse_is_over_any_control() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _editor_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return _editor_panel != null and focus_owner != null and _editor_panel.is_ancestor_of(focus_owner)


func _is_escape_key(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE)
