extends Node2D

@export var tileMap : TileMap
var footprint := Vector2i(3,4)
@export var footprint_primary := Vector2i(3,4)
@export var footprint_alt := Vector2i(4,4)
@export var anchor := Vector2i.ZERO
@onready var placement_area: Area2D = $PlacementArea

@export var heat := 3
@export var power := -5
var input1_is_connected := false
var input1_is_pressed := false
var output1_is_connected := false
var output1_is_pressed := false
var other_button_pressed := false

signal port_drag_started(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_updated(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_ended(building: Node2D, port_name: String, port_global_pos: Vector2)

@onready var output_port := $"Ports/Output 1"
@onready var input_port := $"Ports/Input 1"

var _dragging_port := ""
var _dragging := false

var dragging := false
var drag_offset := Vector2.ZERO

func _ready() -> void:
	$"Ports/Output 1".modulate = Color(1,0,0,0.5)
	$"Ports/Input 1".modulate = Color(0,1,0,0.5)
	output_port.pressed.connect(func(): _start_port_drag("output"))
	input_port.pressed.connect(func(): _start_port_drag("input"))
	add_to_group("buildings")

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if(dragging):
				drag_offset = global_position - get_global_mouse_position()
		elif event.button_index == KEY_CTRL:
			if $PrimarySprite.visible == true:
				$PrimarySprite.visible = false
				$AlternateSprite.visible = true
			else:
				$PrimarySprite.visible = true
				$AlternateSprite.visible = false

func _process(delta: float):
	if dragging:
		var mouse_pos = get_global_mouse_position() + drag_offset
		snap_to_grid(mouse_pos)
	if _dragging:
		emit_signal("port_drag_updated", self, _dragging_port, get_global_mouse_position())
		
func snap_to_grid(world_pos: Vector2):
	var local_pos = tileMap.to_local(world_pos)
	var map_coords = tileMap.local_to_map(local_pos)
	var snapped_local = tileMap.map_to_local(map_coords)
	global_position = tileMap.to_global(snapped_local)

func get_footprint_cells(anchor_cell: Vector2i, footprint_size: Vector2i, anchor: Vector2i) -> Array[Vector2i]:
	var cells : Array[Vector2i]= []
	
	var top_left := anchor_cell - anchor
	
	for y in footprint_size.y:
		for x in footprint_size.x:
			cells.append(top_left + Vector2i(x, y))
			
	return cells
	
func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$TitleLabel.position.x = 27.5
		footprint = footprint_alt
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$TitleLabel.position.x = 14
		footprint = footprint_primary
		
func _on_input_1_mouse_entered() -> void:
	if not input1_is_pressed:
		$"Ports/Input 1".modulate = Color(0,1,0,0.75)

func _on_input_1_mouse_exited() -> void:
	if not input1_is_pressed:
		$"Ports/Input 1".modulate = Color(0,1,0,0.5)


func _on_input_1_pressed() -> void:
	if not input1_is_pressed:
		if not other_button_pressed:
			$"Ports/Input 1".modulate = Color(0,1,0,1.0)
			input1_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Input 1".modulate = Color(0,1,0,0.5)
		input1_is_pressed = false
		other_button_pressed = false

func _on_output_1_mouse_entered() -> void:
	if not output1_is_pressed:
		$"Ports/Output 1".modulate = Color(1,0,0,0.75)

func _on_output_1_mouse_exited() -> void:
	if not output1_is_pressed:
		$"Ports/Output 1".modulate = Color(1,0,0,0.5)

func _on_output_1_pressed() -> void:
	if not output1_is_pressed:
		if not other_button_pressed:
			$"Ports/Output 1".modulate = Color(1,0,0,1.0)
			output1_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Output 1".modulate = Color(1,0,0,0.5)
		output1_is_pressed = false
		other_button_pressed = false
		
func _start_port_drag(port_name: String) -> void:	
	_dragging = true
	_dragging_port = port_name
	
	var p = _get_port_global_pos(port_name)
	emit_signal("port_drag_started", self, port_name, p)

func cancel_port_drag() -> void:
	_dragging = false
	_dragging_port = ""
	
func _get_port_global_pos(port_name: String) -> Vector2:
	match port_name:
		"output":
			return output_port.global_position + output_port.size * 0.5
		"input":
			return input_port.global_position + input_port.size * 0.5
		_:
			return global_position

func _unhandled_input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		emit_signal("port_drag_ended", self, _dragging_port, get_global_mouse_position())
		_dragging_port = ""
