extends Building

@export var footprint_primary := Vector2i(1, 1)
@export var footprint_alt := Vector2i(1, 1)
@export var heat := 0
@export var power := 0

var footprint := Vector2i(1, 1)

func _ready() -> void:
	add_to_group("buildings")

func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		is_alternate = true
		footprint = footprint_alt
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		is_alternate = false
		footprint = footprint_primary
		
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
		_:
			return global_position

func _unhandled_input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		
		#we need to use the center of the button here for ther final endpoint
		var p := _get_port_global_pos(_dragging_port)
		emit_signal("port_drag_ended", self, _dragging_port, p)
		
		_dragging_port = ""
