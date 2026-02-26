extends Node2D

@export var tileMap : TileMap
@export var is_alternate := false
@export var rotatedTick := 0
@export var id : StringName
var footprint := Vector2i(3,6)
@export var footprint_primary := Vector2i(3,6)
@export var footprint_alt := Vector2i(6,6)
@export var anchor := Vector2i.ZERO
@onready var placement_area: Area2D = $PlacementArea

@onready var recipe_dropdown: OptionButton = $Recipe
@onready var output_text : Label = $outputBox/outputText
@onready var input_1_text : Label = $Input1Box/input1Text
@onready var input_2_text : Label = $Input2Box/input2Text
@onready var input_3_text : Label = $Input3Box/input3Text
@onready var input_4_text : Label = $Input4Box/input4Text
@onready var output_box : ColorRect = $outputBox
@onready var input_1_box : ColorRect = $Input1Box
@onready var input_2_box : ColorRect = $Input2Box
@onready var input_3_box : ColorRect = $Input3Box
@onready var input_4_box : ColorRect = $Input4Box

@export var heat := 15
@export var power := -30

@export var available_recipes: Array[Recipe] = []

var input1_is_connected := false
var input1_is_pressed := false
var input2_is_pressed := false
var input2_is_connected := false
var input3_is_pressed := false
var input3_is_connected := false
var input4_is_connected := false
var input4_is_pressed := false
var output1_is_connected := false
var output1_is_pressed := false
var other_button_pressed := false

signal port_drag_started(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_updated(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_ended(building: Node2D, port_name: String, port_global_pos: Vector2)

@onready var output_port := $"Ports/Output 1"
@onready var input_port := $"Ports/Input 1"
@onready var input_2_port := $"Ports/Input 2"
@onready var input_3_port := $"Ports/Input 3"
@onready var input_4_port := $"Ports/Input 4"

var _dragging_port := ""
var _dragging := false

var dragging := false
var drag_offset := Vector2.ZERO

func _ready() -> void:
	$"Ports/Output 1".modulate = Color(1,0,0,0.5)
	$"Ports/Input 1".modulate = Color(0,1,0,0.5)
	$"Ports/Input 2".modulate = Color(0,1,0,0.5)
	$"Ports/Input 3".modulate = Color(0,1,0,0.5)
	$"Ports/Input 4".modulate = Color(0,1,0,0.5)
	output_port.pressed.connect(func(): _start_port_drag("Output 1"))
	input_port.pressed.connect(func(): _start_port_drag("Input 1"))
	input_2_port.pressed.connect(func(): _start_port_drag("Input 2"))
	input_3_port.pressed.connect(func(): _start_port_drag("Input 3"))
	input_4_port.pressed.connect(func(): _start_port_drag("Input 4"))
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
		$TitleLabel.position = Vector2(53, 62)
		$"Ports/Output 1".position = Vector2(81, 1)
		$"Ports/Input 1".position = Vector2(1, 174)
		$"Ports/Input 1".scale = Vector2(0.42, 0.42)
		$"Ports/Input 2".position = Vector2(54, 174)
		$"Ports/Input 2".scale = Vector2(0.42, 0.42)
		$"Ports/Input 3".position = Vector2(108, 174)
		$"Ports/Input 3".scale = Vector2(0.42, 0.42)
		$"Ports/Input 4".position = Vector2(161, 174)
		$"Ports/Input 4".scale = Vector2(0.42, 0.42)
		$Recipe.position = Vector2(49, 92)
		$outputBox.position = Vector2(81, 19)
		$outputBox/outputText.position = Vector2(-3, -3)
		$Input1Box.position = Vector2(1, 156)
		$Input1Box.size = Vector2(30, 17)
		$Input1Box/input1Text.position = Vector2(-4, -2)
		$Input2Box.position = Vector2(54, 156)
		$Input2Box.size = Vector2(30, 17)
		$Input2Box/input2Text.position = Vector2(-4, -2)
		$Input3Box.position = Vector2(108, 156)
		$Input3Box.size = Vector2(30, 17)
		$Input3Box/input3Text.position = Vector2(-4, -2)
		$Input4Box.position = Vector2(161, 156)
		$Input4Box.size = Vector2(30, 17)
		$Input4Box/input4Text.position = Vector2(-4, -2)
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$TitleLabel.position = Vector2(5, 62)
		$"Ports/Output 1".position = Vector2(33, 1)
		$"Ports/Input 1".position = Vector2(1, 178)
		$"Ports/Input 1".scale = Vector2(0.32, 0.32)
		$"Ports/Input 2".position = Vector2(24, 178)
		$"Ports/Input 2".scale = Vector2(0.32, 0.32)
		$"Ports/Input 3".position = Vector2(49, 178)
		$"Ports/Input 3".scale = Vector2(0.32, 0.32)
		$"Ports/Input 4".position = Vector2(72, 178)
		$"Ports/Input 4".scale = Vector2(0.32, 0.32)
		$Recipe.position = Vector2(1, 92)
		$outputBox.position = Vector2(33, 19)
		$outputBox/outputText.position = Vector2(-3, -3)
		$Input1Box.position = Vector2(1, 162)
		$Input1Box.size = Vector2(28, 16)
		$Input1Box/input1Text.position = Vector2(-5, -4)
		$Input2Box.position = Vector2(34,162)
		$Input2Box.size = Vector2(28, 16)
		$Input2Box/input2Text.position = Vector2(-5, -4)
		$Input3Box.position = Vector2(67, 162)
		$Input3Box.size = Vector2(28, 16)
		$Input3Box/input3Text.position = Vector2(-5, -4)
		$Input4Box.position = Vector2(34, 142)
		$Input4Box.size = Vector2(28, 16)
		$Input4Box/input4Text.position = Vector2(-5, -4)
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
			return input_2_port.global_position + input_2_port.size * 0.5
		"input3":
			return input_3_port.global_position + input_3_port.size * 0.5
		"input4":
			return input_4_port.global_position + input_4_port.size & 0.5
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
	input_3_text.text = ""
	input_4_text.text = ""
	output_box.tooltip_text = ""
	input_1_box.tooltip_text = "Unused"
	input_2_box.tooltip_text = "Unused"
	input_3_box.tooltip_text = "Unused"
	input_4_box.tooltip_text = "Unused"
	var recipe := recipe_dropdown.get_item_metadata(index) as Recipe
	if recipe:
		ProdLedger.add_source(get_instance_id(), self,get_production_deltas(recipe))
		output_text.text = str(recipe.outputs[0].qty)
		output_box.tooltip_text = str(recipe.outputs[0].item.display_name)
		input_1_text.text = str(recipe.inputs[0].qty)
		input_1_box.tooltip_text = str(recipe.inputs[0].item.display_name)
		if recipe.inputs.size() == 1:
			return
		elif recipe.inputs.size() == 2:
			input_2_text.text = str(recipe.inputs[1].qty)
			input_2_box.tooltip_text = str(recipe.inputs[1].item.display_name)
			return
		elif recipe.inputs.size() == 3:
			input_2_text.text = str(recipe.inputs[1].qty)
			input_2_box.tooltip_text = str(recipe.inputs[1].item.display_name)
			input_3_text.text = str(recipe.inputs[2].qty)
			input_3_box.tooltip_text = str(recipe.inputs[2].item.display_name)
			return
		elif recipe.inputs.size() == 4:
			input_2_text.text = str(recipe.inputs[1].qty)
			input_2_box.tooltip_text = str(recipe.inputs[1].item.display_name)
			input_3_text.text = str(recipe.inputs[2].qty)
			input_3_box.tooltip_text = str(recipe.inputs[2].item.display_name)
			input_4_text.text = str(recipe.inputs[3].qty)
			input_4_box.tooltip_text = str(recipe.inputs[3].item.display_name)


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


func _on_input_3_pressed() -> void:
	if not input3_is_pressed:
		if not other_button_pressed:
			$"Ports/Input 3".modulate = Color(0,1,0,1.0)
			input3_is_pressed = true
			other_button_pressed = true


func _on_input_3_mouse_entered() -> void:
	if not input3_is_pressed:
		$"Ports/Input 3".modulate = Color(0, 1, 0, 0.75)


func _on_input_3_mouse_exited() -> void:
	if not input3_is_pressed:
		$"Ports/Input 3".modulate = Color(0, 1, 0, 0.5)


func _on_input_4_pressed() -> void:
	if not input4_is_pressed:
		if not other_button_pressed:
			$"Ports/Input 4".modulate = Color(0,1,0,1.0)
			input4_is_pressed = true
			other_button_pressed = true


func _on_input_4_mouse_entered() -> void:
	if not input4_is_pressed:
		$"Ports/Input 4".modulate = Color(0, 1, 0, 0.75)


func _on_input_4_mouse_exited() -> void:
	if not input4_is_pressed:
		$"Ports/Input 4".modulate = Color(0, 1, 0, 0.5)
		
func get_production_deltas(recipe: Recipe) -> Dictionary:
	return recipe.get_deltas()
