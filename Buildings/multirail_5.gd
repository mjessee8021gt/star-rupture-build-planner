extends Building

@export var footprint_primary := Vector2i(1, 1)
@export var footprint_alt := Vector2i(2, 2)
@export var heat := 0
@export var power := 0

@onready var u_port1 := $"Ports/Universal 1"
@onready var u_port2 := $"Ports/Universal 2"
@onready var u_port3 := $"Ports/Universal 3"
@onready var u_port4 := $"Ports/Universal 4"
@onready var u_port5 := $"Ports/Universal 5"
@onready var u_port6 := $"Ports/Universal 6"
@onready var u_port7 := $"Ports/Universal 7"
@onready var u_port8 := $"Ports/Universal 8"
@onready var u_port9 := $"Ports/Universal 9"
@onready var u_port10 := $"Ports/Universal 10"

var universal2_is_connected := false
var universal2_is_pressed := false
var universal1_is_connected := false
var universal1_is_pressed := false
var universal3_is_connected := false
var universal3_is_pressed := false
var universal4_is_connecterd := false
var universal4_is_pressed := false
var universal5_is_connecterd := false
var universal5_is_pressed := false
var universal6_is_connecterd := false
var universal6_is_pressed := false
var universal7_is_connecterd := false
var universal7_is_pressed := false
var universal8_is_connecterd := false
var universal8_is_pressed := false
var universal9_is_connecterd := false
var universal9_is_pressed := false
var universal10_is_connecterd := false
var universal10_is_pressed := false
var other_button_pressed := false
var footprint := Vector2i(1, 1)

func _ready() -> void:
	$"Ports/Universal 1".modulate = Color(.5,.5,.5,0.5)
	$"Ports/Universal 2".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 3".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 4".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 5".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 6".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 7".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 8".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 9".modulate = Color(0.5, 0.5, 0.5, 0.5)
	$"Ports/Universal 10".modulate = Color(0.5, 0.5, 0.5, 0.5)
	u_port1.pressed.connect(func(): _start_port_drag("Universal 1"))
	u_port2.pressed.connect(func(): _start_port_drag("Universal 2"))
	u_port3.pressed.connect(func(): _start_port_drag("Universal 3"))
	u_port4.pressed.connect(func(): _start_port_drag("Universal 4"))
	u_port5.pressed.connect(func(): _start_port_drag("Universal 5"))
	u_port6.pressed.connect(func(): _start_port_drag("Universal 6"))
	u_port7.pressed.connect(func(): _start_port_drag("Universal 7"))
	u_port8.pressed.connect(func(): _start_port_drag("Universal 8"))
	u_port9.pressed.connect(func(): _start_port_drag("Universal 9"))
	u_port10.pressed.connect(func(): _start_port_drag("Universal 10"))
	
	add_to_group("buildings")

func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$Ports.position = Vector2(-64, -64)
		$"Ports/Universal 1".position = Vector2(13, 1)
		$"Ports/Universal 2".position = Vector2(38, 1)
		$"Ports/Universal 3".position = Vector2(65, 1)
		$"Ports/Universal 4".position = Vector2(95, 1)
		$"Ports/Universal 5".position = Vector2(127, 1)
		$"Ports/Universal 6".position = Vector2(13, 104)
		$"Ports/Universal 7".position = Vector2(38, 104)
		$"Ports/Universal 8".position = Vector2(65, 104)
		$"Ports/Universal 9".position = Vector2(95, 104)
		$"Ports/Universal 10".position = Vector2(127, 104)
		is_alternate = true
		footprint = footprint_alt
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$Ports.position = Vector2(-32, -32)
		$"Ports/Universal 1".position = Vector2(13, 1)
		$"Ports/Universal 2".position = Vector2(26, 1)
		$"Ports/Universal 3".position = Vector2(39, 1)
		$"Ports/Universal 4".position = Vector2(52, 1)
		$"Ports/Universal 5".position = Vector2(65, 1)
		$"Ports/Universal 6".position = Vector2(13, 40)
		$"Ports/Universal 7".position = Vector2(26, 40)
		$"Ports/Universal 8".position = Vector2(39, 40)
		$"Ports/Universal 9".position = Vector2(52, 40)
		$"Ports/Universal 10".position = Vector2(65, 40)
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
		"universal 5":
			return u_port5.global_position + u_port5.size * 0.5
		"universal 6":
			return u_port6.global_position + u_port6.size * 0.5
		"universal 7":
			return u_port7.global_position + u_port7.size * 0.5
		"universal 8":
			return u_port8.global_position + u_port8.size * 0.5
		"universal 9":
			return u_port9.global_position + u_port9.size * 0.5
		"universal 10":
			return u_port10.global_position + u_port10.size * 0.5
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
			$"Ports/Universal 3".modulate = Color(0.5, 0.5, 0.5, 1)
			universal3_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 3".modulate = Color(0.5, 0.5, 0.5, 0.5)
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
			$"Ports/Universal41".modulate = Color(0.5, 0.5, 0.5, 1)
			universal4_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 4".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal4_is_pressed = false
		other_button_pressed = false

func _on_universal_4_mouse_entered() -> void:
	if not universal4_is_pressed:
		$"Ports/Universal 4".modulate = Color(0.5, 0.5, 0.5, 0.75)

func _on_universal_4_mouse_exited() -> void:
	if not universal4_is_pressed:
		$"Ports/Universal 4".modulate = Color(0.5, 0.5, 0.5, 0.5)


func _on_universal_5_pressed() -> void:
	if not universal5_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 5".modulate = Color(0.5, 0.5, 0.5, 1)
			universal5_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 5".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal5_is_pressed = false
		other_button_pressed = false


func _on_universal_5_mouse_entered() -> void:
	if not universal5_is_pressed:
		$"Ports/Universal 5".modulate = Color(0.5, 0.5, 0.5, 0.75)


func _on_universal_5_mouse_exited() -> void:
	if not universal5_is_pressed:
		$"Ports/Universal 5".modulate = Color(0.5, 0.5, 0.5, 0.5)


func _on_universal_6_pressed() -> void:
	if not universal6_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 6".modulate = Color(0.5, 0.5, 0.5, 1)
			universal6_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 6".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal6_is_pressed = false
		other_button_pressed = false


func _on_universal_6_mouse_entered() -> void:
	if not universal6_is_pressed:
		$"Ports/Universal 6".modulate = Color(0.5, 0.5, 0.5, 0.75)


func _on_universal_6_mouse_exited() -> void:
	if not universal6_is_pressed:
		$"Ports/Universal 6".modulate = Color(0.5, 0.5, 0.5, 0.5)


func _on_universal_7_pressed() -> void:
	if not universal7_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 7".modulate = Color(0.5, 0.5, 0.5, 1)
			universal7_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 7".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal7_is_pressed = false
		other_button_pressed = false


func _on_universal_7_mouse_entered() -> void:
	if not universal7_is_pressed:
		$"Ports/Universal 7".modulate = Color(0.5, 0.5, 0.5, 0.75)


func _on_universal_7_mouse_exited() -> void:
	if not universal7_is_pressed:
		$"Ports/Universal 7".modulate = Color(0.5, 0.5, 0.5, 0.5)


func _on_universal_8_pressed() -> void:
	if not universal8_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 8".modulate = Color(0.5, 0.5, 0.5, 1)
			universal8_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 8".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal8_is_pressed = false
		other_button_pressed = false


func _on_universal_8_mouse_entered() -> void:
	if not universal8_is_pressed:
		$"Ports/Universal 8".modulate = Color(0.5, 0.5, 0.5, 0.75)


func _on_universal_8_mouse_exited() -> void:
	if not universal8_is_pressed:
		$"Ports/Universal 8".modulate = Color(0.5, 0.5, 0.5, 0.5)


func _on_universal_9_pressed() -> void:
	if not universal9_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 9".modulate = Color(0.5, 0.5, 0.5, 1)
			universal9_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 9".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal9_is_pressed = false
		other_button_pressed = false


func _on_universal_9_mouse_entered() -> void:
	if not universal9_is_pressed:
		$"Ports/Universal 9".modulate = Color(0.5, 0.5, 0.5, 0.75)


func _on_universal_9_mouse_exited() -> void:
	if not universal9_is_pressed:
		$"Ports/Universal 9".modulate = Color(0.5, 0.5, 0.5, 0.5)


func _on_universal_10_pressed() -> void:
	if not universal10_is_pressed:
		if not other_button_pressed:
			$"Ports/Universal 10".modulate = Color(0.5, 0.5, 0.5, 1)
			universal10_is_pressed = true
			other_button_pressed = true
	else:
		$"Ports/Universal 10".modulate = Color(0.5, 0.5, 0.5, 0.5)
		universal10_is_pressed = false
		other_button_pressed = false


func _on_universal_10_mouse_entered() -> void:
	if not universal10_is_pressed:
		$"Ports/Universal 10".modulate = Color(0.5, 0.5, 0.5, 0.75)


func _on_universal_10_mouse_exited() -> void:
	if not universal10_is_pressed:
		$"Ports/Universal 10".modulate = Color(0.5, 0.5, 0.5, 0.5)
