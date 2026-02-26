extends Node2D

@export var tileMap : TileMap
@export var is_alternate := false
@export var rotatedTick := 0
var footprint := Vector2i(3,4)
@export var footprint_primary := Vector2i(3,4)
@export var footprint_alt := Vector2i(3,4)
var _selected_variant : RecipeVariant = null
@export var anchor := Vector2i.ZERO
@onready var placement_area: Area2D = $PlacementArea
@onready var recipe_dropdown: OptionButton = $Recipe
@onready var purity_dropdown: OptionButton = $Purity
@onready var output_text : Label = $outputBox/outputText

@export var heat := 3
@export var power := -5

@export var available_recipes: Array[Recipe] = []
@export var available_alternative_recipes: Array[RecipeVariant] = []

var output1_is_connected := false
var output1_is_pressed := false
var other_button_pressed := false

signal port_drag_started(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_updated(building: Node2D, port_name: String, port_global_pos: Vector2)
signal port_drag_ended(building: Node2D, port_name: String, port_global_pos: Vector2)

@onready var output_port := $"Ports/Output 1"

var _dragging_port := ""
var _dragging := false

var dragging := false
var drag_offset := Vector2.ZERO

func _ready() -> void:
	$"Ports/Output 1".modulate = Color(1,0,0,0.5)
	add_to_group("buildings")
	_connect_port_buttons()
	populate_recipe_dropdown()

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if(dragging):
				drag_offset = global_position - get_global_mouse_position()

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
	var btn := get_node_or_null("Ports/%s" % port_name)
	if btn != null and btn is Control:
		return (btn as Control).get_global_rect().get_center()
	return global_position
	
func _connect_port_buttons() -> void:
	var ports := get_node_or_null("Ports")
	if  ports == null:
		return
	
	for child in ports.get_children():
		if child is Button:
			var btn := child as Button
			var port_name := btn.name
			
			btn.pressed.connect(func(): _on_port_pressed(port_name))
			
func _on_port_pressed(port_name):
	if not _dragging:
		_start_port_drag(port_name)
		return
	
	_dragging = false
	emit_signal("port_drag_ended", self, port_name, _get_port_global_pos(port_name))
	_dragging_port = ""
			
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
		_populate_purity_for_recipe(available_recipes[0])
		
func _populate_purity_for_recipe(recipe: Recipe) -> void:
	purity_dropdown.clear()
	
	for i in recipe.variants.size():
		var variant := recipe.variants[i]
		purity_dropdown.add_item(variant.display_name)
		purity_dropdown.set_item_metadata(i, variant)
		
	if recipe.variants.size() > 0:
		purity_dropdown.select(0)
		_update_output_text_from_variant(recipe.variants[0])
		
func _on_recipe_item_selected(index: int) -> void:
	var recipe := recipe_dropdown.get_item_metadata(index) as Recipe
	if recipe:
		_populate_purity_for_recipe(recipe)

func _on_purity_item_selected(index: int) -> void:
	var variant := purity_dropdown.get_item_metadata(index)as RecipeVariant
	
	if not variant:
		return
		
	if variant == _selected_variant:
		return
	
	_selected_variant = variant
	_update_output_text_from_variant(variant)
	ProdLedger.add_source(get_instance_id(),self ,get_production_deltas(variant))
		
func _update_output_text_from_variant(variant: RecipeVariant) -> void:
	output_text.text = str(variant.output_qty)
	
func get_production_deltas(variant: RecipeVariant) -> Dictionary:
	return variant.get_deltas()
	
func _exit_tree() -> void:
	ProdLedger.remove_source(get_instance_id())
