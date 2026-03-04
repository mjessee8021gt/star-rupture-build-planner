extends Building

@export var footprint_primary := Vector2i(3,4)
@export var footprint_alt := Vector2i(4,4)
@export var heat := 3
@export var power := -5
@export var available_recipes: Array[Recipe] = []

@onready var recipe_dropdown: OptionButton = $Recipe
@onready var output_text : Label = $outputBox/outputText
@onready var input_text : Label = $InputBox/inputText
@onready var output_box : ColorRect = $outputBox
@onready var input_box : ColorRect = $InputBox
@onready var output_port := $"Ports/Output 1"
@onready var input_port := $"Ports/Input 1"

var footprint := Vector2i(3,4)

var input1_is_connected := false
var input1_is_pressed := false
var input2_is_connected := false
var input2_is_pressed := false
var output1_is_connected := false
var output1_is_pressed := false
var other_button_pressed := false

func _ready() -> void:
	$"Ports/Output 1".modulate = Color(1,0,0,0.5)
	$"Ports/Input 1".modulate = Color(0,1,0,0.5)
	output_port.pressed.connect(func(): _start_port_drag("Output 1"))
	input_port.pressed.connect(func(): _start_port_drag("Input 1"))
	add_to_group("buildings")
	populate_recipe_dropdown()
	
func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$TitleLabel.position = Vector2(74, 45)
		$"Ports/Output 1".position = Vector2(110, 1)
		$"Ports/Input 1".position = Vector2(109, 235)
		$Recipe.position = Vector2(64, 79)
		$outputBox.position = Vector2(110, 21)
		$InputBox.position = Vector2(109, 211)
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$TitleLabel.position = Vector2(42,45)
		$"Ports/Output 1".position = Vector2(78, 1)
		$"Ports/Input 1".position = Vector2(78, 235)
		$Recipe.position = Vector2(32, 79)
		$outputBox.position = Vector2(78, 21)
		$InputBox.position = Vector2(78, 211)
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
		"Output":
			return output_port.global_position + output_port.size * 0.5
		"Input":
			return input_port.global_position + input_port.size * 0.5
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
	var recipe := recipe_dropdown.get_item_metadata(index) as Recipe
	if recipe:
		output_text.text = str(recipe.outputs[0].qty)
		output_box.tooltip_text = str(recipe.outputs[0].item.display_name)
		input_text.text = str(recipe.inputs[0].qty)
		input_box.tooltip_text = str(recipe.inputs[0].item.display_name)
		ProdLedger.add_source(get_instance_id(), self,get_production_deltas(recipe))
		
func get_production_deltas(recipe: Recipe) -> Dictionary:
	return recipe.get_deltas()
