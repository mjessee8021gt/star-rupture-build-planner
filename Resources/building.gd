extends Node2D

class_name Building

const PlannerPalette = preload("res://Scripts/palette.gd")

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
var dragging := false
var _themed_port_buttons: Array[Button] = []

##------Vector2 Variables------##
var drag_offset := Vector2.ZERO


func _enter_tree() -> void:
	call_deferred("_apply_visual_theme")

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				drag_offset = global_position - get_global_mouse_position()
		elif event.button_index == KEY_CTRL:
			if has_node("PrimarySprite") and has_node("AlternateSprite"):
				$PrimarySprite.visible = not $PrimarySprite.visible
				$AlternateSprite.visible = not $AlternateSprite.visible

func _process(delta: float):
	if dragging:
		var mouse_pos = get_global_mouse_position() + drag_offset
		snap_to_grid(mouse_pos)
	if _dragging:
		emit_signal("port_drag_updated", self, _dragging_port, get_global_mouse_position())
	_normalize_port_palette()

func snap_to_grid(world_pos: Vector2):
	if tileMap == null:
		return
	var local_pos = tileMap.to_local(world_pos)
	var map_coords = tileMap.local_to_map(local_pos)
	var snapped_local = tileMap.map_to_local(map_coords)
	global_position = tileMap.to_global(snapped_local)

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


func _apply_building_backdrop() -> void:
	var bounds := _get_building_visual_bounds()
	if bounds.size == Vector2.ZERO:
		return

	_remove_theme_polygon("ThemeBackdrop")
	var outline_width := PlannerPalette.building_outline_width(id)
	var outline_rect := bounds.grow(-outline_width * 0.5)
	if outline_rect.size.x <= 0.0 or outline_rect.size.y <= 0.0:
		outline_rect = bounds
	var outline_color := PlannerPalette.building_outline_color(id)
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
				label.add_theme_color_override("font_color", PlannerPalette.TEXT_BADGE)
			elif label.name.to_lower().contains("title"):
				label.add_theme_color_override("font_color", PlannerPalette.TEXT_PRIMARY)
			else:
				label.add_theme_color_override("font_color", PlannerPalette.TEXT_MUTED)

		_theme_labels(child)


func _theme_badges(node: Node) -> void:
	for child in node.get_children():
		if child is ColorRect:
			var rect := child as ColorRect
			rect.color = PlannerPalette.badge_fill_for_name(rect.name)

		_theme_badges(child)


func _theme_option_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is OptionButton:
			var option := child as OptionButton
			option.add_theme_color_override("font_color", PlannerPalette.TEXT_PRIMARY)
			option.add_theme_color_override("font_disabled_color", PlannerPalette.TEXT_MUTED)
			option.add_theme_stylebox_override("normal", PlannerPalette.make_button_style(PlannerPalette.BUTTON_FILL, 6))
			option.add_theme_stylebox_override("hover", PlannerPalette.make_button_style(PlannerPalette.BUTTON_HOVER, 6))
			option.add_theme_stylebox_override("pressed", PlannerPalette.make_button_style(PlannerPalette.BUTTON_PRESSED, 6))
			option.add_theme_stylebox_override("focus", PlannerPalette.make_button_style(PlannerPalette.BUTTON_HOVER, 6))
			option.add_theme_stylebox_override("disabled", PlannerPalette.make_button_style(PlannerPalette.BUTTON_PRESSED, 6))

		_theme_option_buttons(child)


func _normalize_port_palette() -> void:
	for button in _themed_port_buttons:
		if not is_instance_valid(button):
			continue

		var port_color := PlannerPalette.port_color_for_name(button.name)
		button.modulate = PlannerPalette.with_alpha(port_color, button.modulate.a)
