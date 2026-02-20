extends Node2D
"""
Manhattan (orthogonal) routing with rounded corners.

Updated to support Universal* ports as BOTH origin and destination.

Rules:
- If the drag started from a port whose name begins with "Universal", that port is used as the origin.
  Otherwise origin defaults to Ports/Output 1.
- Destination is the clicked port if it is either:
  - "Input 1".."Input 4" OR
  - begins with "Universal"
- Preview is red/transparent; finalized is green/opaque.
- Finalized paths are stored as Path2D children with a Line2D child and endpoint metadata.
"""

@export var endpoints_group := "buildings"

# Styling
@export var preview_color := Color(1, 0, 0, 0.5)
@export var final_color := Color(0, 1, 0, 1)
@export var line_width := 5.0
@export var corner_radius := 16.0      # pixels
@export var arc_segments := 6          # per corner (higher = smoother)
@export var build_manager_path: NodePath = NodePath("../BuildManager")
var _build_mode_active = null

# Default origin port node path
const DEFAULT_FROM_PORT_PATH := NodePath("Ports/Output 1")
const INPUT_PORTS := ["Input 1", "Input 2", "Input 3", "Input 4"]

# Drag state
var _preview_container: Path2D
var _preview_line: Line2D
var _from_building: Node2D
var _from_port_path: NodePath = DEFAULT_FROM_PORT_PATH

func _ready() -> void:
	_connect_to_buildings()
	_build_mode_active = get_node_or_null(build_manager_path)
	get_tree().node_added.connect(_on_node_added)
	
func _on_node_added(n: Node) -> void:
	#connect as soon as a building appears
	if n.is_in_group(endpoints_group):
		_connect_to_building(n)

func _connect_to_buildings() -> void:
	for b in get_tree().get_nodes_in_group(endpoints_group):
		_connect_to_building(b)

# --- Port geometry helpers ---

func _get_port_center(building: Node, port_path: NodePath) -> Variant:
	var n := building.get_node_or_null(port_path)
	if n == null:
		return null
	if n is Control:
		return (n as Control).get_global_rect().get_center()
	# Fallback: for Node2D-like ports
	if n is Node2D:
		return (n as Node2D).global_position
	if "global_position" in n:
		return n.global_position
	return null

func _can_start_paths() -> bool:
	if _build_mode_active!= null and _build_mode_active.has_method("is_build_mode_active"):
		return not _build_mode_active.is_build_mode_active()
	return true

func _is_universal_port_name(port_name: String) -> bool:
	# Matches "Universal", "Universal 1", "UniversalOutput", etc.
	return port_name.begins_with("Universal")

func _is_valid_input_port_name(port_name: String) -> bool:
	return port_name in INPUT_PORTS

func _resolve_origin_port_path(port_name: String) -> NodePath:
	# If the user starts dragging from a Universal* port, use that.
	# Otherwise, use the default Output 1.
	if _is_universal_port_name(port_name):
		return NodePath("Ports/%s" % port_name)
	return DEFAULT_FROM_PORT_PATH

func _is_valid_destination_port_name(port_name: String) -> bool:
	return _is_valid_input_port_name(port_name) or _is_universal_port_name(port_name)

# --- Manhattan routing with rounded corners ---

func _choose_corner(a: Vector2, b: Vector2) -> Vector2:
	# Two L-shape options
	var c1 := Vector2(b.x, a.y)
	var c2 := Vector2(a.x, b.y)

	var s1 = min(a.distance_to(c1), c1.distance_to(b))
	var s2 = min(a.distance_to(c2), c2.distance_to(b))
	return c1 if s1 >= s2 else c2

func _build_manhattan_polyline(a: Vector2, b: Vector2) -> Array[Vector2]:
	# If already axis-aligned, no corner needed.
	if is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y):
		return [a, b]
	var c := _choose_corner(a, b)
	return [a, c, b]

func _round_polyline(points: Array[Vector2], radius: float) -> PackedVector2Array:
	# Produces a polyline with rounded corners from an axis-aligned polyline.
	if points.size() < 2:
		return PackedVector2Array()

	var out := PackedVector2Array()
	out.append(points[0])

	for i in range(1, points.size() - 1):
		var prev := points[i - 1]
		var cur := points[i]
		var nxt := points[i + 1]

		var v1 := (cur - prev)
		var v2 := (nxt - cur)
		var len1 := v1.length()
		var len2 := v2.length()
		if len1 < 0.001 or len2 < 0.001:
			continue

		var d1 := v1 / len1
		var d2 := v2 / len2

		# Only round if we actually turn 90 degrees
		if abs(d1.dot(d2)) > 0.001:
			# Nearly straight; keep the vertex
			out.append(cur)
			continue

		# Clamp radius so it fits in both segments
		var r = min(radius, (min(len1, len2) * 0.5) - 0.5)
		if r <= 0.0:
			out.append(cur)
			continue

		# Tangent points on each segment
		var p1 = cur - d1 * r
		var p2 = cur + d2 * r
		out.append(p1)

		# Arc center for axis-aligned 90° turn
		var center = cur - d1 * r + d2 * r

		var a1 := atan2(p1.y - center.y, p1.x - center.x)
		var a2 := atan2(p2.y - center.y, p2.x - center.x)

		# Determine direction (left turn = CCW, right turn = CW)
		var cross := d1.x * d2.y - d1.y * d2.x
		var ccw := cross > 0.0

		# Normalize angles so we step the short 90° way
		var delta := _wrap_pi(a2 - a1)

		# Force delta to match the turn direction
		if ccw and delta < 0.0:
			delta += TAU
		if (not ccw) and delta > 0.0:
			delta -= TAU

		# Sample arc (skip endpoints; we already added p1 and will add p2)
		for s in range(1, arc_segments):
			var t := float(s) / float(arc_segments)
			var ang := a1 + delta * t
			out.append(center + Vector2(cos(ang), sin(ang)) * r)

		out.append(p2)

	out.append(points[points.size() - 1])
	return out

func _wrap_pi(x: float) -> float:
			while x <= -PI: x += TAU
			while x > PI: x -= TAU
			return x

func _route_points_global(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	var poly := _build_manhattan_polyline(from_pos, to_pos)
	return _round_polyline(poly, corner_radius)

# --- Preview / finalize lifecycle ---

func _on_port_start(building: Node2D, port_name: String, start_pos: Vector2) -> void:
	# Start only once; if already drawing, treat as end.
	if _preview_container != null:
		_on_port_end(building, port_name, start_pos)
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

	# Initial preview points
	var pts := _route_points_global(from_pos, get_global_mouse_position())
	_preview_line.points = pts

func _on_port_update(building: Node2D, port_name: String, mouse_pos: Vector2) -> void:
	if not _can_start_paths():
		_cleanup_preview()
		return
	
	if _preview_container == null or _preview_line == null or _from_building == null:
		return

	var from_pos = _get_port_center(_from_building, _from_port_path)
	if from_pos == null:
		_cleanup_preview()
		return

	_preview_line.points = _route_points_global(from_pos, mouse_pos)

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

	# Destination can be Input 1..4 OR Universal*
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

func _finalize_path(from_b: Node2D, from_port: NodePath, from_pos: Vector2,
		to_b: Node2D, to_port: NodePath, to_pos: Vector2) -> void:

	# Create a new container for the final path
	var path := Path2D.new()
	add_child(path)

	# Metadata for later deletion / rebake
	path.set_meta("from_building", from_b)
	path.set_meta("from_port", from_port)
	path.set_meta("to_building", to_b)
	path.set_meta("to_port", to_port)

	# Draw final Line2D (green)
	var line := Line2D.new()
	line.name = "Line"
	line.width = line_width
	line.antialiased = true
	line.default_color = final_color
	line.points = _route_points_global(from_pos, to_pos)
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

# --- Updating existing paths when buildings move ---

func update_paths_for_building(building: Node2D) -> void:
	for child in get_children():
		if not (child is Path2D):
			continue
		if not child.has_meta("from_building") or not child.has_meta("to_building"):
			continue

		var from_b: Node2D = child.get_meta("from_building")
		var to_b: Node2D = child.get_meta("to_building")
		if from_b != building and to_b != building:
			continue

		var from_port: NodePath = child.get_meta("from_port")
		var to_port: NodePath = child.get_meta("to_port")

		var from_pos = _get_port_center(from_b, from_port)
		var to_pos = _get_port_center(to_b, to_port)
		if from_pos == null or to_pos == null:
			continue

		var line := child.get_node_or_null("Line") as Line2D
		if line == null:
			# Fallback: find any Line2D
			for c in child.get_children():
				if c is Line2D:
					line = c
					break
		if line != null:
			line.points = _route_points_global(from_pos, to_pos)

func remove_paths_for_building(building: Node2D) -> void:
	var to_delete: Array[Node] = []
	for child in get_children():
		if child is Path2D and child.has_meta("from_building") and child.has_meta("to_building"):
			if child.get_meta("from_building") == building or child.get_meta("to_building") == building:
				to_delete.append(child)
	for n in to_delete:
		n.queue_free()
		
func _connect_to_building(b: Node) -> void:
	if b == null:
		return
	#only connect if it exposes the expected signal
	if not b. has_signal("port_drag_started"):
		return
	
	if not b.port_drag_started.is_connected(_on_port_start):
		b.port_drag_started.connect(_on_port_start)
	if not b.port_drag_updated.is_connected(_on_port_update):
		b.port_drag_updated.connect(_on_port_update)
	if not b.port_drag_ended.is_connected(_on_port_end):
		b.port_drag_ended.connect(_on_port_end)
