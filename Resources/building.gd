extends Node2D

class_name Building

const Palette = preload("res://Scripts/palette.gd")

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

func _enter_tree() -> void:
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
