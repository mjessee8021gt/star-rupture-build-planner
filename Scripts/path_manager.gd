extends Node2D

# Styling
@export var preview_color := Color(1, 0, 0, 0.5)
@export var final_color := Color(0, 1, 0, 1)
@export var line_width := 5.0

# Manhattan appearance
@export var port_stub_len := 36.0      # pixels the path extends straight out of a port
@export var corner_radius := 16.0      # pixels
@export var arc_segments := 6          # per rounded corner (higher = smoother)
@export var min_stub_len := 8.0

# BuildManager path gating
@export var build_manager_path: NodePath = NodePath("../BuildManager")
@export var endpoints_group := "buildings"

# Default origin port node path
const DEFAULT_FROM_PORT_PATH := NodePath("Ports/Output 1")
const INPUT_PORTS := ["Input 1", "Input 2", "Input 3", "Input 4"]

# Drag state
var _preview_container: Path2D = null
var _preview_line: Line2D = null
var _from_building: Node2D = null
var _from_port_path: NodePath = DEFAULT_FROM_PORT_PATH

# Cached nodes
var _build_manager: Node = null


func _ready() -> void:
	_build_manager = get_node_or_null(build_manager_path)

	# Connect to existing buildings
	_connect_to_buildings()

	# Auto-connect to newly added buildings
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


# -------------------------------------------------------------------
# Building discovery / signal wiring
# -------------------------------------------------------------------

func _on_node_added(n: Node) -> void:
	# Prefer group membership, but also allow "duck typing" by signals (group might be assigned in _ready()).
	if n == null:
		return
	if n.is_in_group(endpoints_group) or n.has_signal("port_drag_started"):
		_connect_to_building(n)


func _connect_to_buildings() -> void:
	for b in get_tree().get_nodes_in_group(endpoints_group):
		_connect_to_building(b)


func _connect_to_building(b: Node) -> void:
	if b == null:
		return
	if not b.has_signal("port_drag_started"):
		return

	# Avoid duplicate connects
	if not b.port_drag_started.is_connected(_on_port_start):
		b.port_drag_started.connect(_on_port_start)
	if not b.port_drag_updated.is_connected(_on_port_update):
		b.port_drag_updated.connect(_on_port_update)
	if not b.port_drag_ended.is_connected(_on_port_end):
		b.port_drag_ended.connect(_on_port_end)

# Guard rails
func _can_start_paths() -> bool:
	# If BuildManager exists and exposes a build-mode predicate, block while building/ghosting.
	if _build_manager == null:
		return true

	# Support a few method names to be resilient to refactors.
	if _build_manager.has_method("is_build_mode_active"):
		return not _build_manager.is_build_mode_active()
	if _build_manager.has_method("is_in_build_mode"):
		return not _build_manager.is_in_build_mode()
	if _build_manager.has_method("is_in_build_mode_active"):
		return not _build_manager.is_in_build_mode_active()

	return true

# Port helpers
func _is_universal_port_name(port_name: String) -> bool:
	return port_name.begins_with("Universal")

func _is_valid_start_port_name(port_name: String) -> bool:
	return port_name.begins_with("Output")

func _is_valid_input_port_name(port_name: String) -> bool:
	return port_name in INPUT_PORTS


func _is_valid_destination_port_name(port_name: String) -> bool:
	return _is_valid_input_port_name(port_name) or _is_universal_port_name(port_name)


func _resolve_origin_port_path(start_port_name: String) -> NodePath:
	# If the user starts dragging from a Universal* port, use that exact port as the origin.
	
	if _is_universal_port_name(start_port_name):
		return NodePath("Ports/%s" % start_port_name)
	if _is_valid_destination_port_name(start_port_name):
		return NodePath("Ports/%s" % start_port_name)
	return DEFAULT_FROM_PORT_PATH


func _get_port_center(building: Node, port_path: NodePath) -> Variant:
	var target_button := building.get_node_or_null(port_path)
	if target_button == null:
		return null

	if target_button is Control:
		var button_control := target_button as Control
		var center := button_control.get_global_rect().get_center()

		# Push the endpoint outward to the rim of the button
		var normal := _get_port_normal(building, port_path)
		var left_normal_offset := Vector2(-5.0, -7.0)
		var right_normal_offset := Vector2(-30.0, -13.0)
		var minimum_radius = min(button_control.size.x, button_control.size.y) * 0.5
		if normal.is_equal_approx(Vector2.LEFT):
			var left_aligned_normals = center + normal * minimum_radius
			print("PORT %s NORMALS: %s... CALCULATED AS %s + %s * %s" %[target_button, left_aligned_normals, center, normal, minimum_radius])
			return center +(0.5 * normal) * minimum_radius + left_normal_offset
		var right_aligned_normals = center - (normal) * minimum_radius
		print("PORT %s NORMALS: %s... CALCULATED AS %s - (0.5 * %s) * %s" %[target_button,right_aligned_normals, center, normal, minimum_radius])
		return center - (normal) * minimum_radius + right_normal_offset

	if target_button is Node2D:
		return (target_button as Node2D).global_position

	if "global_position" in target_button:
		return target_button.global_position

	return null


func _get_port_normal(building: Node2D, port_path: NodePath) -> Vector2:
	# Preferred: explicit metadata on the port Control:
	#   normal = Vector2.LEFT / RIGHT / UP / DOWN
	var target_button := building.get_node_or_null(port_path)
	if target_button != null and target_button.has_meta("normal"):
		var normal_standard = target_button.get_meta("normal")
		if normal_standard is Vector2:
			var normal_rotated: Vector2 = normal_standard
			var normal_rotated_display = normal_rotated.rotated(building.global_rotation).normalized()
			if normal_rotated.length() > 0.001:
				print("PORT %s ROTATION: %s" %[target_button, normal_rotated_display])
				return normal_rotated.rotated(building.global_rotation).normalized()

	# Fallback: infer from port position relative to building center (global_position).
	var building_center := building.global_position
	var port_center = _get_port_center(building, port_path)
	if port_center == null:
		return Vector2.RIGHT

	var port_delta: Vector2 = (port_center as Vector2) - building_center
	if abs(port_delta.x) >= abs(port_delta.y):
		return Vector2.RIGHT if port_delta.x > 0.0 else Vector2.LEFT
	else:
		return Vector2.DOWN if port_delta.y > 0.0 else Vector2.UP

# Manhattan routing with stubs + rounded corners
func _choose_corner(a: Vector2, b: Vector2) -> Vector2:
	# Two L-shape options
	var corner_option_one := Vector2(b.x, a.y) #Long-Short
	var corner_option_two := Vector2(a.x, b.y) #Short-Long

	# Choose the option that keeps both legs "reasonably long" (avoids tiny first/last leg artifacts)
	var segment_length_one = min(a.distance_to(corner_option_one), corner_option_one.distance_to(b))
	var segment_length_two = min(a.distance_to(corner_option_two), corner_option_two.distance_to(b))
	return corner_option_one if segment_length_one >= segment_length_two else corner_option_two


func _build_manhattan_polyline(a: Vector2, b: Vector2) -> Array[Vector2]:
	# If already axis-aligned, no corner needed.
	if is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y):
		return [a, b]
	var c := _choose_corner(a, b)
	return [a, c, b]

func _adaptive_stub_length(from_pos: Vector2, to_pos: Vector2) -> float:
	# Keep the stubs visually strong for long routes, but shrink them when buildings are close.
	var dist := from_pos.distance_to(to_pos)
	return clamp(dist * 0.22, min_stub_len, port_stub_len)


func _sanitize_polyline(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() <= 2:
		return points

	var out: Array[Vector2] = []
	for point in points:
		if out.is_empty() or out[out.size() - 1].distance_to(point) > 0.5:
			out.append(point)

	if out.size() <= 2:
		return out

	var simplified: Array[Vector2] = [out[0]]
	for i in range(1, out.size() - 1):
		var previous := simplified[simplified.size() - 1]
		var current := out[i]
		var next := out[i + 1]
		var length_delta_one := (current - previous)
		var length_delta_two := (next - current)

		if length_delta_one.length() < 0.5:
			continue
		if length_delta_two.length() < 0.5:
			continue

		length_delta_one = length_delta_one.normalized()
		length_delta_two = length_delta_two.normalized()

		# Drop middle point when segments are collinear.
		if abs(length_delta_one.dot(length_delta_two)) > 0.999:
			continue

		simplified.append(current)

	simplified.append(out[out.size() - 1])
	return simplified


func _dominant_axis_normal(delta: Vector2) -> Vector2:
	if abs(delta.x) >= abs(delta.y):
		return Vector2.RIGHT if delta.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if delta.y >= 0.0 else Vector2.UP

func _wrap_pi(x: float) -> float:
	while x <= -PI:
		x += TAU
	while x > PI:
		x -= TAU
	return x


func _round_polyline(points: Array[Vector2], radius: float, segments: int) -> PackedVector2Array:
	# Produces a polyline with rounded corners from an axis-aligned polyline.
	if points.size() < 2:
		return PackedVector2Array()

	var out := PackedVector2Array()
	out.append(points[0])

	for i in range(1, points.size() - 1):
		if i == points.size() - 2:
			out.append(points[i])
			continue
		var previous := points[i - 1]
		var current := points[i]
		var next := points[i + 1]

		var v1 := (current - previous)
		var v2 := (next - current)
		var length_one := v1.length()
		var length_two := v2.length()
		if length_one < 0.001 or length_two < 0.001:
			continue

		var delta_one := v1 / length_one
		var delta_two := v2 / length_two

		# Only round if we actually turn 90 degrees (orthogonal)
		if abs(delta_one.dot(delta_two)) > 0.001:
			out.append(current)
			continue

		# Clamp radius so it fits in both segments
		var r = min(radius, (min(length_one, length_two) * 0.5) - 0.5)
		if r <= 0.0:
			out.append(current)
			continue

		# Tangent points on each segment
		var p1 = current - delta_one * r
		var p2 = current + delta_two * r
		out.append(p1)

		# Arc center for axis-aligned 90° turn
		var center = current - delta_one * r + delta_two * r

		var a1 := atan2(p1.y - center.y, p1.x - center.x)
		var a2 := atan2(p2.y - center.y, p2.x - center.x)

		# Determine direction (left turn = CCW, right turn = CW)
		var cross := delta_one.x * delta_two.y - delta_one.y * delta_two.x
		var ccw := cross > 0.0

		# Normalize angles so we step the short 90° way
		var delta := _wrap_pi(a2 - a1)

		# Force delta to match the turn direction
		if ccw and delta < 0.0:
			delta += TAU
		if (not ccw) and delta > 0.0:
			delta -= TAU

		# Sample arc (skip endpoints; we already added p1 and will add p2)
		for s in range(1, segments):
			var t := float(s) / float(segments)
			var angle := a1 + delta * t
			out.append(center + Vector2(cos(angle), sin(angle)) * r)

		out.append(p2)

	out.append(points[points.size() - 1])
	return out


func _route_points_local(container: Node2D, from_b: Node2D, from_port: NodePath, from_pos_g: Vector2, to_b: Node2D, to_port: NodePath, to_pos_g: Vector2) -> PackedVector2Array:
	return _route_points_local_with_normals(container, from_pos_g, _get_port_normal(from_b, from_port), to_pos_g, _get_port_normal(to_b, to_port))
	
func _route_points_local_with_normals(container: Node2D,from_pos_g: Vector2, from_n: Vector2,to_pos_g: Vector2, to_n: Vector2) -> PackedVector2Array:
	# Build a "rational" Manhattan path:
	# start -> start_stub -> orthogonal route -> end_stub -> end
	var stub_length := _adaptive_stub_length(from_pos_g, to_pos_g)

	# Global stub endpoints
	var a := from_pos_g
	var a2 := from_pos_g + from_n * stub_length
	var b := to_pos_g
	var b2 := to_pos_g + to_n * stub_length

	# Orthogonal between stubs
	var mid_poly := _build_manhattan_polyline(a2, b2) # Array[Vector2] (global)

	# Assemble full polyline (global)
	var poly_g: Array[Vector2] = []
	poly_g.append(a)
	poly_g.append(a2)
	for point in mid_poly:
		# avoid duplicates when aligned
		if poly_g.size() == 0 or poly_g[poly_g.size() - 1] != point:
			poly_g.append(point)
	if poly_g[poly_g.size() - 1] != b2:
		poly_g.append(b2)
	poly_g.append(b)
	poly_g = _sanitize_polyline(poly_g)

	# Convert to local space for the container and round corners in local space
	var poly_l: Array[Vector2] = []
	for point in poly_g:
		poly_l.append(container.to_local(point))
	poly_l = _sanitize_polyline(poly_l)

	return _round_polyline(poly_l, corner_radius, arc_segments)

# Preview / finalize lifecycle
func _on_port_start(building: Node2D, port_name: String, _start_pos: Vector2) -> void:
	# Start only once; if already drawing, treat as end.
	if _preview_container != null:
		_on_port_end(building, port_name, _start_pos)
		return

	if not _can_start_paths():
		_cleanup_preview()
		return

	_from_building = building
	_from_port_path = _resolve_origin_port_path(port_name)

	var from_pos = _get_port_center(_from_building, _from_port_path)
	if from_pos == null:
		push_warning("Missing origin port %s on %s" % [str(_from_port_path), building.name])
		_cleanup_preview()
		return

	_preview_container = Path2D.new()
	add_child(_preview_container)

	_preview_line = Line2D.new()
	_preview_line.width = line_width
	_preview_line.antialiased = true
	_preview_line.default_color = preview_color
	_preview_container.add_child(_preview_line)

	_refresh_preview(get_global_mouse_position())


func _on_port_update(_building: Node2D, _port_name: String, mouse_pos: Vector2) -> void:
	if not _can_start_paths():
		_cleanup_preview()
		return
	if _preview_container == null or _preview_line == null or _from_building == null:
		return
	_refresh_preview(mouse_pos)


func _refresh_preview(mouse_pos: Vector2) -> void:
	var from_pos = _get_port_center(_from_building, _from_port_path)
	if from_pos == null:
		_cleanup_preview()
		return

	var to_normal := _dominant_axis_normal(from_pos - mouse_pos)

	_preview_line.points = _route_points_local_with_normals(_preview_container, from_pos, _get_port_normal(_from_building, _from_port_path), mouse_pos, to_normal)


func _on_port_end(building: Node2D, port_name: String, mouse_pos: Vector2) -> void:
	if not _can_start_paths():
		_cleanup_preview()
		return

	if _preview_container == null or _preview_line == null or _from_building == null:
		return

	# Don't allow ending on the origin building (prevents accidental self-links)
	if building == _from_building:
		_cleanup_preview()
		return

	if not _is_valid_destination_port_name(port_name):
		_cleanup_preview()
		return

	var from_pos = _get_port_center(_from_building, _from_port_path)
	var to_port_path := NodePath("Ports/%s" % port_name)
	var to_pos = _get_port_center(building, to_port_path)

	if from_pos == null or to_pos == null:
		_cleanup_preview()
		return

	_finalize_path(_from_building, _from_port_path, from_pos, building, to_port_path, to_pos)


func _finalize_path(from_b: Node2D, from_port: NodePath, from_pos: Vector2, to_b: Node2D, to_port: NodePath, to_pos: Vector2) -> void:
	var path := Path2D.new()
	var line := Line2D.new()
	add_child(path)

	# Metadata for later deletion / rebake
	path.set_meta("from_building", from_b)
	path.set_meta("from_port", from_port)
	path.set_meta("to_building", to_b)
	path.set_meta("to_port", to_port)

	line.name = "Line"
	line.width = line_width
	line.antialiased = true
	line.default_color = final_color
	line.points = _route_points_local(path, from_b, from_port, from_pos, to_b, to_port, to_pos)
	var end_local: Vector2 = line.points[line.points.size() -1]
	var end_global: Vector2 = path.to_global(end_local)
	print("TO_POS:", to_pos, " END_GLOBAL:", end_global, " DELTA:", end_global - to_pos)
	path.add_child(line)

	# Cancel port drag visuals on the origin building (if implemented)
	if is_instance_valid(from_b) and from_b.has_method("cancel_port_drag"):
		from_b.cancel_port_drag()

	_cleanup_preview()

func _cleanup_preview() -> void:
	if _preview_container != null and is_instance_valid(_preview_container):
		_preview_container.queue_free()
	_preview_container = null
	_preview_line = null
	_from_building = null
	_from_port_path = DEFAULT_FROM_PORT_PATH

# Updating existing paths when buildings move / are deleted
func update_paths_for_building(building: Node2D) -> void:
	for child in get_children():
		if not (child is Path2D):
			continue
		var path := child as Path2D

		if not path.has_meta("from_building") or not path.has_meta("to_building"):
			continue

		var from_building: Node2D = path.get_meta("from_building")
		var to_building: Node2D = path.get_meta("to_building")
		if from_building != building and to_building != building:
			continue

		var from_port: NodePath = path.get_meta("from_port")
		var to_port: NodePath = path.get_meta("to_port")

		var from_pos = _get_port_center(from_building, from_port)
		var to_pos = _get_port_center(to_building, to_port)
		if from_pos == null or to_pos == null:
			continue

		var line := path.get_node_or_null("Line") as Line2D
		if line == null:
			for c in path.get_children():
				if c is Line2D:
					line = c
					break
		if line != null:
			line.points = _route_points_local(path, from_building, from_port, from_pos, to_building, to_port, to_pos)

#Upon deletion of a building, clean up the paths stemming from or to it.
func remove_paths_for_building(building: Node2D) -> void:
	var to_delete: Array[Node] = []
	for child in get_children():
		if child is Path2D and child.has_meta("from_building") and child.has_meta("to_building"):
			if child.get_meta("from_building") == building or child.get_meta("to_building") == building:
				to_delete.append(child)
	for n in to_delete:
		n.queue_free()
