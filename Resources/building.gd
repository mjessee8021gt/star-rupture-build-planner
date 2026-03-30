extends Node2D

class_name Building

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

##------Vector2 Variables------##
var drag_offset := Vector2.ZERO

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
