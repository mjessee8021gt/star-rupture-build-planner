extends Building

@export var footprint_primary := Vector2i(1, 1)
@export var footprint_alt := Vector2i(2, 2)
@export var heat := 0
@export var power := 0

@onready var u_port1 := $"Ports/Universal 1"
@onready var u_port2 := $"Ports/Universal 2"

var universal2_is_connected := false
var universal2_is_pressed := false
var universal1_is_connected := false
var universal1_is_pressed := false
var other_button_pressed := false
var footprint := Vector2i(1, 1)

func _ready() -> void:
	$"Ports/Universal 1".modulate = Color(.5,.5,.5,0.5)
	$"Ports/Universal 2".modulate = Color(0.5, 0.5, 0.5, 0.5)
	u_port1.pressed.connect(func(): _start_port_drag("Universal 1"))
	u_port2.pressed.connect(func(): _start_port_drag("Universal 2"))
	add_to_group("buildings")

func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$"Ports/Universal 1".position = Vector2(20, 1)
		$"Ports/Universal 2".position = Vector2(43, 63)
		is_alternate = true
		footprint = footprint_alt
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$"Ports/Universal 1".position = Vector2(5, 1)
		$"Ports/Universal 2".position = Vector2(28, 31)
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
		"Universal 1":
			return u_port1.get_global_rect().get_center()
		"Universal 2":
			return u_port2.get_global_rect().get_center()
		_:
			return global_position

func _unhandled_input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		
		#we need to use the center of the button here for ther final endpoint
		print("UNHANDLED INPUT FROM BUILDING: " + str(_dragging_port))
		var p := _get_port_global_pos(_dragging_port)
		emit_signal("port_drag_ended", self, _dragging_port, p)
		
		_dragging_port = ""
