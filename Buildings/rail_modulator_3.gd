extends Building

var footprint := Vector2i(1, 1)
@export var footprint_primary := Vector2i(1, 1)
@export var footprint_alt := Vector2i(2, 2)

@export var heat := 0
@export var power := 0

var universal2_is_connected := false
var universal2_is_pressed := false
var universal1_is_connected := false
var universal1_is_pressed := false
var universal3_is_connected := false
var universal3_is_pressed := false
var universal4_is_connecterd := false
var universal4_is_pressed := false
var other_button_pressed := false

@onready var u_port1 := $"Ports/Universal 1"
@onready var u_port2 := $"Ports/Universal 2"
@onready var u_port3 := $"Ports/Universal 3"
@onready var u_port4 := $"Ports/Universal 4"

func _ready() -> void:
	$"Ports/Universal 1".modulate = Color(.5,.5,.5,0.5)
	$"Ports/Universal 2".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 3".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 4".modulate = Color(0.5, 0.5, 0.5, 0.5)
	u_port1.pressed.connect(func(): _start_port_drag("Universal 1"))
	u_port2.pressed.connect(func(): _start_port_drag("Universal 2"))
	u_port3.pressed.connect(func(): _start_port_drag("Universal 3"))
	u_port4.pressed.connect(func(): _start_port_drag("Universal 4"))
	add_to_group("buildings")

func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$"Ports/Universal 1".position = Vector2(23, 1)
		$"Ports/Universal 1".rotation = 0
		$"Ports/Universal 2".position = Vector2(44, 1)
		$"Ports/Universal 2".rotation = 0
		$"Ports/Universal 3".position = Vector2(41, 63)
		$"Ports/Universal 3".rotation = 180
		$"Ports/Universal 4".position = Vector2(1, 1)
		$"Ports/Universal 4".rotation = 0
		is_alternate = true
		footprint = footprint_alt
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$"Ports/Universal 1".position = Vector2(11, 17)
		$"Ports/Universal 1".rotation = 270
		$"Ports/Universal 2".position = Vector2(32, -2)
		$"Ports/Universal 2".rotation = 90
		$"Ports/Universal 3".position = Vector2(26, 32)
		$"Ports/Universal 3".rotation = 180
		$"Ports/Universal 4".position = Vector2(0, 17)
		$"Ports/Universal 4".rotation = 270
		is_alternate = false
		footprint = footprint_primary
		
func _on_universal_2_mouse_entered() -> void:
	if not universal2_is_pressed:
		$"Ports/Universal 2".modulate = Color(0.5, 0.5, 0.5, 0.75)

func _on_universal_2_mouse_exited() -> void:
	if not universal2_is_pressed:
		$"Ports/Universal 2".modulate = Color(0.5, 0.5, 0.5, 0.5)

func _on_universal_2_pressed() -> void:
	if not universal2_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 2".modulate = Color(0.5, 0.5, 0.5, 1)
			universal2_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 2".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal2_is_pressed = false
		other_button_pressed = false

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
		"universal 1":
			return u_port1.global_position + u_port1.size * 0.5
		"universal 2":
			return u_port2.global_position + u_port2.size * 0.5
		"universal 3":
			return u_port3.global_position + u_port3.size * 0.5
		"universal 4":
			return u_port4.global_position + u_port4.size * 0.5
		_:
			return global_position

func _unhandled_input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		emit_signal("port_drag_ended", self, _dragging_port, get_global_mouse_position())
		_dragging_port = ""

func _on_universal_3_pressed() -> void:
	if not universal3_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 1)
			universal3_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal3_is_pressed = false
		other_button_pressed = false

func _on_universal_3_mouse_entered() -> void:
	if not universal3_is_pressed:
		$"Ports/Universal 3".modulate = Color(0.5, 0.5, 0.5, 0.75)

func _on_universal_3_mouse_exited() -> void:
	if not universal3_is_pressed:
		$"Ports/Universal 3".modulate = Color(0.5, 0.5, 0.5, 0.5)

func _on_universal_4_pressed() -> void:
	if not universal4_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 1)
			universal4_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 1".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal4_is_pressed = false
		other_button_pressed = false

func _on_universal_4_mouse_entered() -> void:
	if not universal4_is_pressed:
		$"Ports/Universal 4".modulate = Color(0.5, 0.5, 0.5, 0.75)

func _on_universal_4_mouse_exited() -> void:
	if not universal4_is_pressed:
		$"Ports/Universal 4".modulate = Color(0.5, 0.5, 0.5, 0.5)
