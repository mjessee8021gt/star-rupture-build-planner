extends Node2D

@export var endpoints_group := "buildings" #group containing building Node2Ds

var _current_path: Path2D
var _current_curve: Curve2D
var _current_line: Line2D
var _from_building: Node2D
var _from_port: String

func _ready() -> void:
	_update_building_list()

func _update_building_list():
	#Connect to all buildings in a group
	for b in get_tree().get_nodes_in_group(endpoints_group):
		b.port_drag_started.connect(_on_port_start)
		b.port_drag_updated.connect(_on_port_update)
		b.port_drag_ended.connect(_on_port_end)
		
func _on_port_start(building:Node2D, port_name: String, start_pos: Vector2) -> void:
	if _current_curve != null:
		_on_port_end(building, port_name, start_pos)
		return
	
	_from_building = building
	_from_port = port_name
	
	_current_path = Path2D.new()
	_current_curve = Curve2D.new()
	_current_curve.add_point(start_pos)
	_current_curve.add_point(get_global_mouse_position())
	_current_path.curve = _current_curve
	add_child(_current_path)
	
	_current_line = Line2D.new()
	_current_line.width = 5.0
	_current_line.antialiased = true
	_current_line.default_color = Color(1,0,0,0.5)
	add_child(_current_line)
	
	_refresh_preview_line()
	
func _refresh_preview_line() -> void:
	if _current_curve == null or _current_line == null:
		return
	var baked: PackedVector2Array = _current_curve.get_baked_points()
	_current_line.points = baked
	
func _on_port_update(building: Node2D, port_name: String, mouse_pos: Vector2) -> void:
	if _current_curve == null:
		return
		
	_current_curve.set_point_position(1, mouse_pos)
	_refresh_preview_line()
	
func _on_port_end(building: Node2D, port_name: String, mouse_pos: Vector2) -> void:
	if _current_curve == null:
		return
		
	var target = _find_target_port(mouse_pos)
	if target.is_empty():
		_cleanup_preview()
		return
	
	var to_building:Node2D = target["building"]
	var to_port: String = target["port"]
	var to_pos: Vector2 = target["pos"]
	
	#simple rule example: output can connect to input only (customize as needed)
	if not (_from_port == "output"and to_port == "input"):
		_cleanup_preview()
		return
	if is_instance_valid(_from_building):
		_from_building.cancel_port_drag()
	_current_curve.set_point_position(1, to_pos)
	_refresh_preview_line()
	_current_line.default_color = Color(0,1,0,1)
	
	#Metadata Storage
	_current_path.set_meta("from_building", _from_building)
	_current_path.set_meta("from_port", _from_port)
	_current_path.set_meta("to_building", to_building)
	_current_path.set_meta("to_port", to_port)
	
	_current_path = null
	_current_curve = null
	_from_building = null
	_from_port = ""
	
func _cleanup_preview() -> void:
	if _current_path:
		_current_path.queue_free()
	_current_path = null
	_current_curve = null
	_current_line = null
	_from_building = null
	_from_port = ""
	
func _find_target_port(mouse_pos: Vector2) -> Dictionary:
	#Detect "hovered" port by distance-to-port-center
	for b in get_tree().get_nodes_in_group(endpoints_group):
		var out_btn: Button = b.get_node("Ports/Output 1")
		var in_btn: Button = b.get_node("Ports/Input 1")
		var out_pos = out_btn.global_position + out_btn.size * 0.5
		var in_pos = in_btn.global_position + in_btn.size * 0.5
		
		if mouse_pos.distance_to(in_pos) < 10:
			return{"building": b, "port": "input", "pos": in_pos}
		if mouse_pos.distance_to(out_pos) < 18:
			return{"building": b, "port": "output", "pos": out_pos}

	return{}
