extends Building

var footprint := Vector2i(4, 4)
@export var footprint_primary := Vector2i(4, 4)
@export var footprint_alt := Vector2i(5, 4)

@onready var recipe_dropdown: OptionButton = $Recipe

@export var heat := 60
@export var power := -40

@export var available_recipes: Array[Recipe] = []

var output2_is_connected := false
var output2_is_pressed := false
var output1_is_connected := false
var output1_is_pressed := false
var other_button_pressed := false

@onready var output1_port := $"Ports/Output 1"
@onready var output2_port := $"Ports/Output 2"

func _ready() -> void:
	$"Ports/Output 1".modulate = Color(1,0,0,0.5)
	$"Ports/Output 2".modulate = Color(1,0,0,0.5)
	
	output1_port.pressed.connect(func(): _start_port_drag("Output 1"))
	output2_port.pressed.connect(func(): _start_port_drag("Output 2"))
	add_to_group("buildings")
	populate_recipe_dropdown()

func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$TitleLabel.position = Vector2(48, 6)
		$"Ports/Output 1".position = Vector2(1, 61)
		$"Ports/Output 2".position = Vector2(123, 61)
		$Recipe.position = Vector2(13, 28)
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$TitleLabel.position = Vector2(31, 6)
		$"Ports/Output 1".position = Vector2(1, 61)
		$"Ports/Output 2".position = Vector2(91, 61)
		$Recipe.position = Vector2(0, 28)
		footprint = footprint_primary
		is_alternate = false

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
		"Output 1":
			return output1_port.global_position + output1_port.size * 0.5
		"Output 2":
			return output2_port.global_position + output2_port.size * 0.5
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
		
func _on_output_2_pressed() -> void:
	if not output2_is_pressed:
		if not other_button_pressed:
			$"Ports/Output 2".modulate = Color(1,0,0,1.0)
			output1_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Output 2".modulate = Color(1,0,0,0.5)
		output2_is_pressed = false
		other_button_pressed = false
		
func _on_output_2_mouse_entered() -> void:
	if not output2_is_pressed:
		$"Ports/Output 2".modulate = Color(1,0,0,0.75)

func _on_output_2_mouse_exited() -> void:
	if not output2_is_pressed:
		$"Ports/Output 2".modulate = Color(1,0,0,0.5)
