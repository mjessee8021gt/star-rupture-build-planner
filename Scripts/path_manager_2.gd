extends Node2D

## Manhattan-style button-based path manager.
## HTML5-safe: no threads/native calls.

@export var port_stub_len := 40.0
@export var min_stub_len := 100.0
@export var corner_radius := 10.0
@export var arc_segments := 5
@export var node_button_size := Vector2(72.0, 40.0)
@export var lane_vertical_offset := 0.0 # Fine-tune stacked port alignment.
@export var segment_spacing := 28.0

var _buildings_root: Node = null
var _active_drag := false
var _drag_from_building: Node2D = null
var _drag_from_port := NodePath("")
var _drag_from_normal := Vector2.ZERO
var _active_preview: Node2D = null

func _ready() -> void:
	_buildings_root = get_node_or_null("../buildings")
	if _buildings_root != null:
		_buildings_root.child_entered_tree.connect(_on_building_entered)
		_buildings_root.child_exiting_tree.connect(_on_building_exiting)
		for child in _buildings_root.get_children():
			_on_building_entered(child)

func _on_building_entered(node: Node) -> void:
	if node == null:
		return
	if node.has_signal("port_drag_started"):
		node.port_drag_started.connect(_on_port_drag_started)
	if node.has_signal("port_drag_updated"):
		node.port_drag_updated.connect(_on_port_drag_updated)
	if node.has_signal("port_drag_ended"):
		node.port_drag_ended.connect(_on_port_drag_ended)

func _on_building_exiting(node: Node) -> void:
	if node == _drag_from_building:
		cancel_active_path_drag()
	remove_paths_for_building(node)

func _on_port_drag_started(building: Node2D, port_name: String, _port_global_pos: Vector2) -> void:
	if not _is_start_port(port_name):
		cancel_active_path_drag()
		return

	_drag_from_building = building
	_drag_from_port = NodePath("Ports/%s" % port_name)
	_drag_from_normal = _get_port_normal(building, _drag_from_port)
	_active_drag = true

	if is_instance_valid(_drag_from_building):
		_drag_from_building.tree_exited.connect(_on_drag_source_tree_exited, CONNECT_ONE_SHOT)

func _on_port_drag_updated(_building: Node2D, _port_name: String, port_global_pos: Vector2) -> void:
	if not _active_drag or not is_instance_valid(_drag_from_building):
		return
	var from_pos = _get_port_center(_drag_from_building, _drag_from_port)
	if from_pos == null:
		return
	_draw_preview(from_pos, port_global_pos, _drag_from_normal, Vector2.ZERO)

func _on_port_drag_ended(_building: Node2D, _port_name: String, _port_global_pos: Vector2) -> void:
	if not _active_drag or not is_instance_valid(_drag_from_building):
		cancel_active_path_drag()
		return

	var target_info := _resolve_target_port_under_mouse()
	if target_info.is_empty():
		cancel_active_path_drag()
		return

	var to_building := target_info["building"] as Node2D
	var to_port := target_info["port"] as NodePath
	var to_port_name := String(target_info["port_name"])
	if not _is_end_port(to_port_name):
		cancel_active_path_drag()
		return

	var from_pos = _get_port_center(_drag_from_building, _drag_from_port)
	var to_pos = _get_port_center(to_building, to_port)
	if from_pos == null or to_pos == null:
		cancel_active_path_drag()
		return

	_finalize_path(_drag_from_building, _drag_from_port, from_pos, to_building, to_port, to_pos)
	_clear_preview()
	_active_drag = false
	_drag_from_building = null
	_drag_from_port = NodePath("")
	_drag_from_normal = Vector2.ZERO

func _on_drag_source_tree_exited() -> void:
	cancel_active_path_drag()

func cancel_active_path_drag() -> void:
	_active_drag = false
	_drag_from_building = null
	_drag_from_port = NodePath("")
	_drag_from_normal = Vector2.ZERO
	_clear_preview()

func _is_start_port(port_name: String) -> bool:
	return port_name.begins_with("Output") or port_name.begins_with("Universal")

func _is_end_port(port_name: String) -> bool:
	return port_name.begins_with("Input") or port_name.begins_with("Universal")

func _resolve_target_port_under_mouse() -> Dictionary:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or not (hovered is Button):
		return {}

	var port_button := hovered as Button
	var name := port_button.name
	var building := _find_building_ancestor(port_button)
	if building == null:
		return {}

	return {
		"building": building,
		"port": NodePath("Ports/%s" % name),
		"port_name": name,
	}

func _find_building_ancestor(node: Node) -> Node2D:
	var cur := node
	while cur != null:
		if cur is Node2D and cur.has_signal("port_drag_started"):
			return cur as Node2D
		cur = cur.get_parent()
	return null

func _get_port_normal(building: Node2D, port_path: NodePath) -> Vector2:
	if building == null:
		return Vector2.UP
	var port := building.get_node_or_null(port_path)
	if port == null:
		return Vector2.UP
	var n = port.get_meta("normal", Vector2.UP)
	if n is Vector2 and n.length() > 0.01:
		return (n as Vector2).normalized()
	return Vector2.UP

func _get_stub_len(a: Vector2, b: Vector2) -> float:
	var manhattan := absf(a.x - b.x) + absf(a.y - b.y)
	return minf(maxf(port_stub_len, manhattan * 0.25), min_stub_len)

func _draw_preview(from_pos: Vector2, to_pos: Vector2, from_n: Vector2, to_n: Vector2) -> void:
	_clear_preview()
	_active_preview = _make_path_node(from_pos, to_pos, from_n, to_n)
	if _active_preview != null:
		_active_preview.modulate = Color(0.0, 1.0, 0.0, 0.5)
		add_child(_active_preview)

func _clear_preview() -> void:
	if _active_preview != null and is_instance_valid(_active_preview):
		_active_preview.queue_free()
	_active_preview = null

func _finalize_path(from_building: Node2D, from_port: NodePath, from_pos: Vector2, to_building: Node2D, to_port: NodePath, to_pos: Vector2) -> void:
	if from_building == null or to_building == null:
		return

	var from_n := _get_port_normal(from_building, from_port)
	var to_n := _get_port_normal(to_building, to_port)
	var path_node := _make_path_node(from_pos, to_pos, from_n, to_n)
	if path_node == null:
		return

	path_node.set_meta("from_building", from_building)
	path_node.set_meta("to_building", to_building)
	path_node.set_meta("from_port", str(from_port))
	path_node.set_meta("to_port", str(to_port))
	add_child(path_node)

func _make_path_node(from_pos: Vector2, to_pos: Vector2, from_n: Vector2, to_n: Vector2) -> Node2D:
	var p0 := from_pos + Vector2(0.0, lane_vertical_offset)
	var p3 := to_pos + Vector2(0.0, lane_vertical_offset)
	var stub := _get_stub_len(p0, p3)
	var p1 := p0 + from_n * stub
	var p2 := p3 + to_n * stub

	var mid_x := (p1.x + p2.x) * 0.5
	var via_a := Vector2(mid_x, p1.y)
	var via_b := Vector2(mid_x, p2.y)

	var pts: Array[Vector2] = [p0, p1, via_a, via_b, p2, p3]
	pts = _collapse_near_points(pts, 0.001)
	if pts.size() < 2:
		return null

	var container := Node2D.new()
	container.name = "Path"
	var poly := _rounded_polyline(pts)
	_add_button_chain(container, poly)
	return container

func _collapse_near_points(points: Array[Vector2], eps: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in points:
		if out.is_empty() or out.back().distance_to(p) > eps:
			out.append(p)
	return out

func _rounded_polyline(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() <= 2:
		return points
	var out: Array[Vector2] = [points[0]]
	for i in range(1, points.size() - 1):
		var a := points[i - 1]
		var b := points[i]
		var c := points[i + 1]
		var ab := (b - a)
		var bc := (c - b)
		if ab.length() < 0.001 or bc.length() < 0.001:
			continue
		var u := ab.normalized()
		var v := bc.normalized()
		if absf(u.dot(v)) > 0.999:
			out.append(b)
			continue

		var r := minf(corner_radius, minf(ab.length() * 0.5, bc.length() * 0.5))
		var p_in := b - u * r
		var p_out := b + v * r
		out.append(p_in)

		var turn := signf(u.cross(v))
		var n1 := Vector2(-u.y, u.x) * turn
		var n2 := Vector2(-v.y, v.x) * turn
		var center = _line_intersection(p_in, n1, p_out, n2)
		if center == null:
			out.append(b)
			continue

		var a0 = (p_in - center).angle()
		var a1 = (p_out - center).angle()
		var da := wrapf(a1 - a0, -PI, PI)
		for s in range(1, max(1, arc_segments)):
			var t := float(s) / float(max(1, arc_segments))
			out.append(center + Vector2.from_angle(a0 + da * t) * r)
		out.append(p_out)
	out.append(points.back())
	return out

func _line_intersection(p: Vector2, r: Vector2, q: Vector2, s: Vector2) -> Variant:
	var rxs := r.cross(s)
	if absf(rxs) < 0.00001:
		return null
	var t := (q - p).cross(s) / rxs
	return p + r * t

func _add_button_chain(container: Node2D, poly: Array[Vector2]) -> void:
	for i in range(poly.size() - 1):
		_add_segment_buttons(container, poly[i], poly[i + 1])

	for i in range(1, poly.size() - 1):
		var prev := poly[i - 1]
		var cur := poly[i]
		var next := poly[i + 1]
		if (cur - prev).length() < 0.001 or (next - cur).length() < 0.001:
			continue
		if absf((cur - prev).normalized().dot((next - cur).normalized())) > 0.99:
			continue
		var cbtn := Button.new()
		cbtn.name = "Corner_%d" % i
		cbtn.size = node_button_size
		cbtn.position = cur - node_button_size * 0.5
		var turn_sign := signf((cur - prev).cross(next - cur))
		cbtn.rotation_degrees = 45.0 if turn_sign >= 0.0 else 135.0
		cbtn.disabled = true
		container.add_child(cbtn)

func _add_segment_buttons(container: Node2D, a: Vector2, b: Vector2) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var dir := d / len
	var step := maxf(8.0, segment_spacing)
	var count = max(1, int(ceil(len / step)))
	for i in range(count + 1):
		var t := float(i) / float(count)
		var p := a.lerp(b, t)
		var btn := Button.new()
		btn.name = "Node_%d" % i
		btn.size = node_button_size
		btn.position = p - node_button_size * 0.5
		btn.rotation_degrees = 90.0 if absf(dir.y) > absf(dir.x) else 0.0
		btn.disabled = true
		container.add_child(btn)

func _get_port_center(building: Node2D, port_path: NodePath) -> Variant:
	if building == null:
		return null
	var port := building.get_node_or_null(port_path)
	if port == null:
		return null
	if port is Control:
		return (port as Control).global_position + (port as Control).size * 0.5
	if port is Node2D:
		return (port as Node2D).global_position
	return null

func remove_paths_for_building(building: Node) -> void:
	if building == null:
		return
	for child in get_children():
		if child == _active_preview:
			continue
		if not (child is Node):
			continue
		if child.get_meta("from_building", null) == building or child.get_meta("to_building", null) == building:
			child.queue_free()

func update_paths_for_building(building: Node2D) -> void:
	if building == null:
		return
	for child in get_children():
		if child == _active_preview:
			continue
		var from_b = child.get_meta("from_building", null)
		var to_b = child.get_meta("to_building", null)
		if from_b != building and to_b != building:
			continue
		if not (from_b is Node2D) or not (to_b is Node2D):
			child.queue_free()
			continue
		var from_port := NodePath(String(child.get_meta("from_port", "")))
		var to_port := NodePath(String(child.get_meta("to_port", "")))
		var fp = _get_port_center(from_b, from_port)
		var tp = _get_port_center(to_b, to_port)
		if fp == null or tp == null:
			child.queue_free()
			continue
		var fresh := _make_path_node(fp, tp, _get_port_normal(from_b, from_port), _get_port_normal(to_b, to_port))
		if fresh == null:
			child.queue_free()
			continue
		fresh.set_meta("from_building", from_b)
		fresh.set_meta("to_building", to_b)
		fresh.set_meta("from_port", str(from_port))
		fresh.set_meta("to_port", str(to_port))
		add_child(fresh)
		child.queue_free()

func update_path_for_building(building: Node2D) -> void:
	update_paths_for_building(building)
