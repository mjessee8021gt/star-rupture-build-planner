extends Node2D

@export var tileMap : TileMap
@export var is_alternate := false
var footprint := Vector2i(3,3)
@export var footprint_primary := Vector2i(3,3)
@export var footprint_alt := Vector2i(4,4)
@export var anchor := Vector2i.ZERO
@onready var placement_area: Area2D = $PlacementArea

@onready var recipe_dropdown: OptionButton = $Recipe
@onready var output_text : Label = $outputBox/outputText
@onready var input_1_text : Label = $Input1Box/input1Text
@onready var input_2_text : Label = $Input2Box/input2Text
@onready var output_box : ColorRect = $outputBox
@onready var input_1_box : ColorRect = $Input1Box
@onready var input_2_box : ColorRect = $Input2Box

@export var heat := 5
@export var power := -10

@export var available_recipes: Array[Recipe] = []

var input1_is_connected := false
var input1_is_pressed := false
var input2_is_pressed := false
var input2_is_connected := false
var output1_is_connected := false
var output1_is_pressed := false
var other_button_pressed := false

signal port_drag_started(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_updated(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_ended(building: Node2D, port_name: String, port_global_pos: Vector2)

@onready var output_port := $"Ports/Output 1"
@onready var input_port := $"Ports/Input 1"
@onready var input_2_port := $"Ports/Input 2"

var _dragging_port := ""
var _dragging := false

var dragging := false
var drag_offset := Vector2.ZERO

func _ready() -> void:
	$"Ports/Output 1".modulate = Color(1,0,0,0.5)
	$"Ports/Input 1".modulate = Color(0,1,0,0.5)
	$"Ports/Input 2".modulate = Color(0,1,0,0.5)
	output_port.pressed.connect(func(): _start_port_drag("output"))
	input_port.pressed.connect(func(): _start_port_drag("input1"))
	input_2_port.pressed.connect(func(): _start_port_drag("input2"))
	add_to_group("buildings")
	populate_recipe_dropdown()

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
		$TitleLabel.position = Vector2(23, 46)
		$"Ports/Output 1".position = Vector2(46,1)
		$"Ports/Input 1".position = Vector2(91,107)
		$"Ports/Input 2".position = Vector2(1, 107)
		$Recipe.position = Vector2(17,66)
		$outputBox.position = Vector2(46,23)
		$outputBox/outputText.position = Vector2(-1, -2)
		$Input1Box.position = Vector2(92, 89)
		$Input1Box/input1Text.position = Vector2(-1, -2)
		$Input2Box.position = Vector2(1, 89)
		$Input2Box/input2Text.position = Vector2(-1, -2)
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$TitleLabel.position = Vector2(5, 21)
		$"Ports/Output 1".position = Vector2(37, 1)
		$"Ports/Input 1".position = Vector2(58, 75)
		$"Ports/Input 2".position = Vector2(1, 75)
		$Recipe.position = Vector2(1, 39)
		$outputBox.position = Vector2(2,2)
		$outputBox/outputText.position = Vector2(-1, -2)
		$Input1Box.position = Vector2(59,60)
		$Input1Box/input1Text.position = Vector2(-1, -2)
		$Input2Box.position = Vector2(1,60)
		$Input2Box/input2Text.position = Vector2(-1, -2)
		footprint = footprint_primary
		is_alternate = false
		
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
		"input1":
			return input_port.global_position + input_port.size * 0.5
		"input2":
			return input_2_port.global_position + input_port.size * 0.5
		_:
			return global_position

func _unhandled_input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		emit_signal("port_drag_ended", self, _dragging_port, get_global_mouse_position())
		_dragging_port = ""
		
func populate_recipe_dropdown() -> void:
	recipe_dropdown.clear()
	
	for i in available_recipes.size():
		var recipe := available_recipes[i]
		recipe_dropdown.add_item(recipe.display_name)
		#we need to store which recipe we're referring to above
		recipe_dropdown.set_item_metadata(i, recipe)
		
	#now we're selecting the first recipe by defualt and populating the purity list
	if available_recipes.size() > 0:
		recipe_dropdown.select(0)

func _on_recipe_item_selected(index: int) -> void:
	output_text.text = ""
	input_1_text.text = ""
	input_2_text.text = ""
	output_box.tooltip_text = ""
	input_1_box.tooltip_text = "Unused"
	input_2_box.tooltip_text = "Unused"
	
	var recipe := recipe_dropdown.get_item_metadata(index) as Recipe
	if recipe:
		output_text.text = str(recipe.outputs[0].qty)
		output_box.tooltip_text = str(recipe.outputs[0].item.display_name)
		input_1_text.text = str(recipe.inputs[0].qty)
		input_1_box.tooltip_text = str(recipe.inputs[0].item.display_name)
		if recipe.inputs.size() == 1:
			return
		else:
			input_2_text.text = str(recipe.inputs[1].qty)
			input_2_box.tooltip_text = str(recipe.inputs[1].item.display_name)


func _on_input_2_pressed() -> void:
	if not input2_is_pressed:
		if not other_button_pressed:
			$"Ports/Input 2".modulate = Color(0,1,0,1.0)
			input2_is_pressed = true
			other_button_pressed = true


func _on_input_2_mouse_entered() -> void:
	if not input2_is_pressed:
		$"Ports/Input 2".modulate = Color(0,1,0,0.75)


func _on_input_2_mouse_exited() -> void:
	if not input2_is_pressed:
		$"Ports/Input 2".modulate = Color(0,1,0,0.5)
