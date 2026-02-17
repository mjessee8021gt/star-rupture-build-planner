extends Node2D

@export var endpoints_group := "buildings" #group containing building Node2Ds

var _current_path: Path2D
var _current_curve: Curve2D
var _current_line: Line2D
var _from_building: Node2D
var _from_port: String
var _from_port_path := NodePath("Ports/Output 1")
const TARGET_INPUTS := [NodePath("Ports/Input 1"), NodePath("Ports/Input 2"),NodePath("Ports/Input 3"),NodePath("Ports/Input 4")]


func _ready() -> void:
	_update_building_list()

func _update_building_list():
	# Connect to all buildings in a group (guard against duplicate connections)
	for b in get_tree().get_nodes_in_group(endpoints_group):
		if not b.port_drag_started.is_connected(_on_port_start):
			b.port_drag_started.connect(_on_port_start)
		if not b.port_drag_updated.is_connected(_on_port_update):
			b.port_drag_updated.connect(_on_port_update)
		if not b.port_drag_ended.is_connected(_on_port_end):
			b.port_drag_ended.connect(_on_port_end)
		
func _on_port_start(building:Node2D, port_name: String, start_pos: Vector2) -> void:
	if _current_curve != null:
		_on_port_end(building, port_name, start_pos)
		return
	
	_from_building = building
	var from_pos = _get_port_center(_from_building, _from_port_path)
	if from_pos == null:
		push_warning("Origin building missing Ports/Output 1: %s" %_from_building.name)
		return
	
	_current_path = Path2D.new()
	_current_curve = Curve2D.new()
	
	add_child(_current_path)
	
	var a := _current_path.to_local(from_pos)
	var b := _current_path.to_local(get_global_mouse_position())
	
	_current_curve.add_point(a)
	_current_curve.add_point(b)
	_current_path.curve = _current_curve
	
	_current_line = Line2D.new()
	_current_line.width = 5.0
	_current_line.antialiased = true
	_current_line.default_color = Color(1,0,0,0.5)
	_current_path.add_child(_current_line)
	
	_refresh_preview_line()
	
func _refresh_preview_line() -> void:
	if _current_curve == null or _current_line == null:
		return
	var baked: PackedVector2Array = _current_curve.get_baked_points()
	_current_line.points = baked
	
func _on_port_update(building: Node2D, port_name: String, mouse_pos: Vector2) -> void:
	if _current_curve == null or _current_path == null:
		return
		
	_current_curve.set_point_position(1, _current_path.to_local(mouse_pos))
	_refresh_preview_line()
	
func _on_port_end(building: Node2D, port_name: String, mouse_pos: Vector2) -> void:
	if _from_building == null:
		return
	
	if _current_curve == null:
		return
		
	var target = _find_target_port(mouse_pos)
	if target.is_empty():
		_cleanup_preview()
		return
	
	var to_building:Node2D = target["building"]
	var to_input_path: NodePath = target["input_path"]
	var to_pos = _get_port_center(to_building, to_input_path)
	var from_pos = _get_port_center(_from_building, _from_port_path)
	
	if from_pos == null:
		_cleanup_preview()
		return
		
	_finalize_path(_from_building, _from_port_path, from_pos, to_building, to_input_path, to_pos)
	
func _finalize_path(from_b: Node2D, from_port: NodePath, from_pos: Vector2, to_b: Node2D, to_port: NodePath, to_pos: Vector2) -> void:
	#Establishing path containers
	var path := Path2D.new()
	add_child(path)
	
	#Get the metadata out of he way, this stuff is all for the program to reference in the future.
	path.set_meta("from_building", from_b)
	path.set_meta("to_building", to_b)
	path.set_meta("from_port", from_port)
	path.set_meta("to_port", to_port)
	
	#Create a curve in local space of the Path2D we've already established
	var curve := Curve2D.new()
	curve.bake_interval = 6.0 #a smaller number will make a smoother line
	
	var a := path.to_local(from_pos)
	var b := path.to_local(to_pos)
	
	var delta := b - a
	var bend_dir := Vector2(0, -1) #bend "up"
	var handle_len = clamp(delta.length() * 0.35, 40.0, 220.0)
	curve.add_point(a, Vector2.ZERO, bend_dir * handle_len)
	curve.add_point(b, -bend_dir * handle_len, Vector2.ZERO)
	
	path.curve = curve
	
	var line := Line2D.new()
	line.width = 5.0
	line.antialiased = true
	line.default_color = Color(0, 1, 0, 1)
	line.points = curve.get_baked_points()
	
	path.add_child(line)
	
	_cleanup_preview()
	
func _cleanup_preview() -> void:
	if _current_path:
		_current_path.queue_free() # also frees the preview Line2D (child)
	elif _current_line:
		_current_line.queue_free()
	_current_path = null
	_current_curve = null
	_current_line = null
	_from_building = null
	_from_port = ""
	
func _find_target_port(mouse_pos: Vector2) -> Dictionary:
	#Detect "hovered" port by distance-to-port-center
	for b in get_tree().get_nodes_in_group(endpoints_group):
		if not is_instance_valid(b):
			continue
		if b == _from_building:
			continue #this is mission critical. The program should never be targeting the origin building as the target building
		
		for input_path in TARGET_INPUTS:
			var btn := b.get_node_or_null(input_path)
			if btn == null:
				continue
				
			var pos: Vector2 = btn.global_position + btn.size * 0.5
			if mouse_pos.distance_to(pos) < 18:
				return {"building": b, "input_path": input_path, "pos": pos}
	return{}


func remove_paths_for_building(building: Node2D) -> void:
	# If the building is part of an in-progress drag, cancel/cleanup first.
	if _from_building == building:
		_cleanup_preview()

	for child in get_children():
		if child is Path2D:
			var from_b = child.get_meta("from_building") if child.has_meta("from_building") else null
			var to_b = child.get_meta("to_building") if child.has_meta("to_building") else null
			if from_b == building or to_b == building:
				child.queue_free()
				
func _get_port_center(building: Node, port_path : NodePath) -> Variant:
	var btn := building.get_node_or_null(port_path)
	if btn == null:
		return null
	#control node center
	
	if btn is Control:
		return(btn as Control).get_global_rect().get_center()
		
	return btn.global_position
