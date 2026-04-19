extends Building

@export var footprint_primary := Vector2i(3, 3)
@export var footprint_alt := Vector2i(4, 4)
@export var heat := 30
@export var power := -50

@onready var u_port1 := $"Ports/Universal 1"
@onready var u_port2 := $"Ports/Universal 2"
@onready var u_port3 := $"Ports/Universal 3"
@onready var u_port4 := $"Ports/Universal 4"

var universal1_is_connected := false
var universal1_is_pressed := false
var other_button_pressed := false
var footprint := Vector2i(3, 3)

func _ready() -> void:
	$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 0.5)
	
	u_port1.pressed.connect(func(): _start_port_drag("Universal 1"))
	add_to_group("buildings")
	
func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$Ports.position = Vector2(-128, -128)
		$"Ports/Universal 1".position = Vector2(111, 235)
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$Ports.position = Vector2(-96, -96)
		$"Ports/Universal 1".position = Vector2(78, 171)
		footprint = footprint_primary
		is_alternate = false
		
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
		"Universal 1":
			return u_port1.global_position + u_port1.size * 0.5
		_:
			return global_position

func _unhandled_input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		emit_signal("port_drag_ended", self, _dragging_port, get_global_mouse_position())
		_dragging_port = ""

func _on_universal_1_mouse_entered() -> void:
	if not universal1_is_pressed:
		$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 0.75)

func _on_universal_1_mouse_exited() -> void:
	if not universal1_is_pressed:
		$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 0.5)

func _on_universal_1_pressed() -> void:
	if not universal1_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 1)
			universal1_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal1_is_pressed = false
		other_button_pressed = false
