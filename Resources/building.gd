extends Node2D

class_name Building

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

enum BuildCostType {
	BBM,
	IBM,
	METEOR_CORE
}

##------OnReady variables------##
@onready var placement_area: Area2D = $PlacementArea

##------Exported Variables-----##
@export var tileMap: TileMap
@export var is_alternate := false
@export var rotatedTick := 0
@export var id: StringName
@export var anchor := Vector2i.ZERO
@export_enum("BBM", "IBM", "Meteor Core") var build_cost_type : int = BuildCostType.BBM
@export var build_cost_amount := 0

##-----------Signals-----------##
signal port_drag_started(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_updated(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_ended(building: Node2D, port_name: String, port_global_pos: Vector2)

##-------String Variables------##
var _dragging_port := ""

##------Boolean Variables------##
var _dragging := false
var _themed_port_buttons: Array[Button] = []
var _port_palette_refresh_queued := false
var _ui_scale := 1.0
var _base_control_rects: Dictionary = {}
var _last_scaled_control_rects: Dictionary = {}
var _base_font_sizes: Dictionary = {}

func _enter_tree() -> void:
	call_deferred("_inherit_ui_scale_from_scene")
	call_deferred("_apply_visual_theme")

func _process(_delta: float):
	if _dragging:
		_emit_port_drag_updated(_dragging_port, get_global_mouse_position())


func _emit_port_drag_started(port_name: String, port_global_pos: Vector2) -> void:
	port_drag_started.emit(self, port_name, port_global_pos)


func _emit_port_drag_updated(port_name: String, port_global_pos: Vector2) -> void:
	port_drag_updated.emit(self, port_name, port_global_pos)


func _emit_port_drag_ended(port_name: String, port_global_pos: Vector2) -> void:
	port_drag_ended.emit(self, port_name, port_global_pos)

func get_footprint_cells(anchor_cell: Vector2i, footprint_size: Vector2i, footprint_anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var top_left := anchor_cell - footprint_anchor

	for y in footprint_size.y:
		for x in footprint_size.x:
			cells.append(top_left + Vector2i(x, y))

	return cells


func _apply_visual_theme() -> void:
	_cache_port_buttons()
	_apply_building_backdrop()
	_reorder_theme_layers()
	_theme_labels(self)
	_theme_badges(self)
	_theme_option_buttons(self)
	_normalize_port_palette()
	_apply_accessibility_scale(self)


func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	if is_inside_tree():
		_apply_accessibility_scale(self)


func _inherit_ui_scale_from_scene() -> void:
	var node := get_parent()
	while node != null:
		if node.has_method("get_ui_scale"):
			set_ui_scale(float(node.call("get_ui_scale")))
			return
		node = node.get_parent()


func _cache_port_buttons() -> void:
	_themed_port_buttons.clear()
	var ports := get_node_or_null("Ports")
	if ports == null:
		return

	for child in ports.get_children():
		if child is Button:
			_themed_port_buttons.append(child)
			_bind_port_palette_updates(child as Button)


func _bind_port_palette_updates(button: Button) -> void:
	if button == null:
		return

	if not button.button_down.is_connected(_queue_port_palette_normalize):
		button.button_down.connect(_queue_port_palette_normalize)
	if not button.button_up.is_connected(_queue_port_palette_normalize):
		button.button_up.connect(_queue_port_palette_normalize)
	if not button.mouse_entered.is_connected(_queue_port_palette_normalize):
		button.mouse_entered.connect(_queue_port_palette_normalize)
	if not button.mouse_exited.is_connected(_queue_port_palette_normalize):
		button.mouse_exited.connect(_queue_port_palette_normalize)
	if not button.focus_entered.is_connected(_queue_port_palette_normalize):
		button.focus_entered.connect(_queue_port_palette_normalize)
	if not button.focus_exited.is_connected(_queue_port_palette_normalize):
		button.focus_exited.connect(_queue_port_palette_normalize)
	if not button.toggled.is_connected(_queue_port_palette_normalize):
		button.toggled.connect(_queue_port_palette_normalize)


func _apply_building_backdrop() -> void:
	var bounds := _get_building_visual_bounds()
	if bounds.size == Vector2.ZERO:
		return

	_remove_theme_polygon("ThemeBackdrop")
	var outline_width := Palette.building_outline_width(id)
	var outline_rect := bounds.grow(-outline_width * 0.5)
	if outline_rect.size.x <= 0.0 or outline_rect.size.y <= 0.0:
		outline_rect = bounds
	var outline_color := Palette.building_outline_color(id)
	_set_theme_outline("ThemeOutline", outline_rect, outline_color, outline_width)


func _get_building_visual_bounds() -> Rect2:
	var has_bounds := false
	var bounds := Rect2()

	for sprite_name in ["PrimarySprite", "AlternateSprite"]:
		var sprite := get_node_or_null(sprite_name) as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		if not sprite.visible:
			continue

		var size := sprite.texture.get_size() * sprite.scale.abs()
		var top_left := sprite.position
		if sprite.centered:
			top_left -= size * 0.5

		var sprite_rect := Rect2(top_left, size)
		if not has_bounds:
			bounds = sprite_rect
			has_bounds = true
		else:
			bounds = bounds.merge(sprite_rect)

	return bounds


func _set_theme_outline(node_name: String, rect: Rect2, color: Color, width: float) -> void:
	var existing := get_node_or_null(node_name)
	if existing != null and not (existing is Line2D):
		existing.queue_free()
		existing = null

	var outline := existing as Line2D
	if outline == null:
		outline = Line2D.new()
		outline.name = node_name
		add_child(outline)

	outline.width = width
	outline.default_color = color
	outline.closed = true
	outline.antialiased = true
	outline.joint_mode = Line2D.LINE_JOINT_SHARP
	outline.begin_cap_mode = Line2D.LINE_CAP_NONE
	outline.end_cap_mode = Line2D.LINE_CAP_NONE
	outline.z_index = 0
	outline.points = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


func _reorder_theme_layers() -> void:
	var outline := get_node_or_null("ThemeOutline")
	if outline == null:
		return

	var target_index := 0
	for i in range(get_child_count()):
		var child := get_child(i)
		if child == outline:
			continue
		if child is Sprite2D:
			target_index = i + 1

	move_child(outline, target_index)


func _remove_theme_polygon(node_name: String) -> void:
	var polygon := get_node_or_null(node_name)
	if polygon != null:
		polygon.queue_free()


func _theme_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			var label := child as Label
			if label.get_parent() is ColorRect:
				label.add_theme_color_override("font_color", Palette.TEXT_BADGE)
			elif label.name.to_lower().contains("title"):
				label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
			else:
				label.add_theme_color_override("font_color", Palette.TEXT_MUTED)

		_theme_labels(child)


func _theme_badges(node: Node) -> void:
	for child in node.get_children():
		if child is ColorRect:
			var rect := child as ColorRect
			rect.color = Palette.badge_fill_for_name(rect.name)

		_theme_badges(child)


func _theme_option_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is OptionButton:
			var option := child as OptionButton
			option.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
			option.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
			option.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, 6))
			option.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, 6))
			option.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, 6))
			option.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, 6))
			option.add_theme_stylebox_override("disabled", Palette.make_button_style(Palette.BUTTON_PRESSED, 6))

		_theme_option_buttons(child)


func _apply_accessibility_scale(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			if _is_scalable_building_control(control):
				_scale_building_control(control)
				if child is Label:
					_scale_control_font(child as Control, &"font_size")
				elif child is OptionButton:
					_scale_option_button(child as OptionButton)

		_apply_accessibility_scale(child)


func _is_scalable_building_control(control: Control) -> bool:
	if control == null:
		return false
	if control.is_in_group("port_button"):
		return false
	if _is_descendant_of_port_root(control):
		return false
	return control is Label or control is ColorRect or control is OptionButton


func _is_descendant_of_port_root(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent.name == "Ports":
			return true
		parent = parent.get_parent()
	return false


func _scale_building_control(control: Control) -> void:
	var base_rect := _get_base_control_rect(control)
	var scaled_size := UiScale.scaled_vec2(base_rect.size, _ui_scale)
	var scaled_position := base_rect.position + ((base_rect.size - scaled_size) * 0.5)
	control.scale = Vector2.ONE
	control.position = scaled_position
	control.size = scaled_size
	control.custom_minimum_size = scaled_size
	_last_scaled_control_rects[control.get_instance_id()] = Rect2(scaled_position, scaled_size)


func _get_base_control_rect(control: Control) -> Rect2:
	var key := control.get_instance_id()
	var current_rect := Rect2(control.position, control.size)
	if _base_control_rects.has(key):
		var last_rect: Rect2 = _last_scaled_control_rects.get(key, Rect2())
		if not _rects_are_close(current_rect, last_rect):
			var divisor = maxf(_ui_scale, 0.001)
			_base_control_rects[key] = Rect2(current_rect.position, current_rect.size / divisor)
		return _base_control_rects[key]

	_base_control_rects[key] = current_rect
	return current_rect


func _rects_are_close(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) <= 0.01 and a.size.distance_to(b.size) <= 0.01


func _scale_control_font(control: Control, theme_name: StringName) -> void:
	if control == null:
		return
	var key := "%d:%s" % [control.get_instance_id(), String(theme_name)]
	if not _base_font_sizes.has(key):
		_base_font_sizes[key] = max(control.get_theme_font_size(theme_name), 1)
	UiScale.apply_font_size(control, theme_name, int(_base_font_sizes[key]), _ui_scale)


func _scale_option_button(option: OptionButton) -> void:
	_scale_control_font(option, &"font_size")
	option.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(6), _scaled_int(1)))
	option.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))
	option.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(6), _scaled_int(1)))
	option.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))
	option.add_theme_stylebox_override("disabled", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(6), _scaled_int(1)))
	var popup := option.get_popup()
	if popup == null:
		return
	UiScale.apply_font_size(popup, &"font_size", int(_base_font_sizes.get("%d:%s" % [option.get_instance_id(), "font_size"], 16)), _ui_scale)
	popup.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(6), _scaled_int(1)))
	popup.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(4), _scaled_int(1)))
	popup.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	popup.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	popup.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	popup.add_theme_constant_override("v_separation", _scaled_int(4))
	popup.add_theme_constant_override("item_start_padding", _scaled_int(12))
	popup.add_theme_constant_override("item_end_padding", _scaled_int(16))


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)


func _normalize_port_palette() -> void:
	for button in _themed_port_buttons:
		if not is_instance_valid(button):
			continue

		var port_color := Palette.port_color_for_name(button.name)
		button.modulate = Palette.with_alpha(port_color, button.modulate.a)


func _queue_port_palette_normalize(_unused = null) -> void:
	if _port_palette_refresh_queued:
		return
	_port_palette_refresh_queued = true
	call_deferred("_flush_port_palette_normalize")


func _flush_port_palette_normalize() -> void:
	_port_palette_refresh_queued = false
	_normalize_port_palette()
