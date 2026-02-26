extends Node2D
"""
Manhattan (orthogonal) routing with rounded corners + port "stubs" so lines
leave/arrive perpendicular to the building face (a "rational angle").

Also supports Universal* ports as BOTH origin and destination.

Rules
- Origin port:
  - If drag started on a port whose name begins with "Universal", that exact port is the origin.
  - Otherwise origin defaults to Ports/Output 1.
- Destination port:
  - Clicked port if it is "Input 1".."Input 4" OR begins with "Universal".
- Preview: red/transparent. Final: green/opaque.
- Finalized paths are stored as Path2D children with a Line2D child and endpoint metadata:
  from_building, from_port, to_building, to_port

Guard rails (BuildManager integration)
- If BuildManager indicates build/ghost mode is active, PathManager ignores start/update/end
  and cleans up any preview.
"""

@export var endpoints_group := "buildings"

# Styling
@export var preview_color := Color(1, 0, 0, 0.5)
@export var final_color := Color(0, 1, 0, 1)
@export var line_width := 5.0

# Manhattan appearance
@export var port_stub_len := 36.0      # pixels the path extends straight out of a port
@export var corner_radius := 16.0      # pixels
@export var arc_segments := 6          # per rounded corner (higher = smoother)

# BuildManager path gating
@export var build_manager_path: NodePath = NodePath("../BuildManager")

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


# -------------------------------------------------------------------
# Guard rails
# -------------------------------------------------------------------

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


# -------------------------------------------------------------------
# Port helpers
# -------------------------------------------------------------------

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
	var n := building.get_node_or_null(port_path)
	if n == null:
		return null

	if n is Control:
		var c := n as Control
		var center := c.get_global_rect().get_center()

		# Push the endpoint outward to the rim of the button
		var normal := _get_port_normal(building, port_path)
		var r = min(c.size.x, c.size.y) * 0.5
		return center - normal * r

	if n is Node2D:
		return (n as Node2D).global_position

	if "global_position" in n:
		return n.global_position

	return null


func _get_port_normal(building: Node2D, port_path: NodePath) -> Vector2:
	# Preferred: explicit metadata on the port Control:
	#   normal = Vector2.LEFT / RIGHT / UP / DOWN
	var n := building.get_node_or_null(port_path)
	if n != null and n.has_meta("normal"):
		var v = n.get_meta("normal")
		if v is Vector2:
			var vv: Vector2 = v
			if vv.length() > 0.001:
				return vv.rotated(building.global_rotation).normalized()

	# Fallback: infer from port position relative to building center (global_position).
	var center := building.global_position
	var p = _get_port_center(building, port_path)
	if p == null:
		return Vector2.RIGHT

	var delta: Vector2 = (p as Vector2) - center
	if abs(delta.x) >= abs(delta.y):
		return Vector2.RIGHT if delta.x > 0.0 else Vector2.LEFT
	else:
		return Vector2.DOWN if delta.y > 0.0 else Vector2.UP


# -------------------------------------------------------------------
# Manhattan routing with stubs + rounded corners
# -------------------------------------------------------------------

func _choose_corner(a: Vector2, b: Vector2) -> Vector2:
	# Two L-shape options
	var c1 := Vector2(b.x, a.y)
	var c2 := Vector2(a.x, b.y)

	# Choose the option that keeps both legs "reasonably long" (avoids tiny first/last leg artifacts)
	var s1 = min(a.distance_to(c1), c1.distance_to(b))
	var s2 = min(a.distance_to(c2), c2.distance_to(b))
	return c1 if s1 >= s2 else c2


func _build_manhattan_polyline(a: Vector2, b: Vector2) -> Array[Vector2]:
	# If already axis-aligned, no corner needed.
	if is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y):
		return [a, b]
	var c := _choose_corner(a, b)
	return [a, c, b]


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

		# Only round if we actually turn 90 degrees (orthogonal)
		if abs(d1.dot(d2)) > 0.001:
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
		for s in range(1, segments):
			var t := float(s) / float(segments)
			var ang := a1 + delta * t
			out.append(center + Vector2(cos(ang), sin(ang)) * r)

		out.append(p2)

	out.append(points[points.size() - 1])
	return out


func _route_points_local(
		container: Node2D,
		from_b: Node2D, from_port: NodePath, from_pos_g: Vector2,
		to_b: Node2D, to_port: NodePath, to_pos_g: Vector2
	) -> PackedVector2Array:
	# Build a "rational" Manhattan path:
	# start -> start_stub -> orthogonal route -> end_stub -> end
	var from_n := _get_port_normal(from_b, from_port)
	var to_n := _get_port_normal(to_b, to_port)

	# Global stub endpoints
	var a := from_pos_g
	var a2 := from_pos_g + from_n * port_stub_len
	var b := to_pos_g
	var b2 := to_pos_g + to_n * port_stub_len

	# Orthogonal between stubs
	var mid_poly := _build_manhattan_polyline(a2, b2) # Array[Vector2] (global)

	# Assemble full polyline (global)
	var poly_g: Array[Vector2] = []
	poly_g.append(a)
	poly_g.append(a2)
	for p in mid_poly:
		# avoid duplicates when aligned
		if poly_g.size() == 0 or poly_g[poly_g.size() - 1] != p:
			poly_g.append(p)
	if poly_g[poly_g.size() - 1] != b2:
		poly_g.append(b2)
	poly_g.append(b)

	# Convert to local space for the container and round corners in local space
	var poly_l: Array[Vector2] = []
	for p in poly_g:
		poly_l.append(container.to_local(p))

	return _round_polyline(poly_l, corner_radius, arc_segments)


# -------------------------------------------------------------------
# Preview / finalize lifecycle
# -------------------------------------------------------------------

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

	# Preview has no "to building", so we fake normals by using the origin normal and mouse direction.
	# Route to mouse using a temporary end port normal inferred from direction.
	var temp_to_pos: Vector2 = mouse_pos
	var temp_to_building := _from_building
	var temp_to_port := _from_port_path

	_preview_line.points = _route_points_local(
		_preview_container,
		_from_building, _from_port_path, from_pos,
		temp_to_building, temp_to_port, temp_to_pos
	)


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
	add_child(path)

	# Metadata for later deletion / rebake
	path.set_meta("from_building", from_b)
	path.set_meta("from_port", from_port)
	path.set_meta("to_building", to_b)
	path.set_meta("to_port", to_port)

	var line := Line2D.new()
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


# -------------------------------------------------------------------
# Updating existing paths when buildings move / are deleted
# -------------------------------------------------------------------

func update_paths_for_building(building: Node2D) -> void:
	for child in get_children():
		if not (child is Path2D):
			continue
		var path := child as Path2D

		if not path.has_meta("from_building") or not path.has_meta("to_building"):
			continue

		var from_b: Node2D = path.get_meta("from_building")
		var to_b: Node2D = path.get_meta("to_building")
		if from_b != building and to_b != building:
			continue

		var from_port: NodePath = path.get_meta("from_port")
		var to_port: NodePath = path.get_meta("to_port")

		var from_pos = _get_port_center(from_b, from_port)
		var to_pos = _get_port_center(to_b, to_port)
		if from_pos == null or to_pos == null:
			continue

		var line := path.get_node_or_null("Line") as Line2D
		if line == null:
			for c in path.get_children():
				if c is Line2D:
					line = c
					break
		if line != null:
			line.points = _route_points_local(path, from_b, from_port, from_pos, to_b, to_port, to_pos)


func remove_paths_for_building(building: Node2D) -> void:
	var to_delete: Array[Node] = []
	for child in get_children():
		if child is Path2D and child.has_meta("from_building") and child.has_meta("to_building"):
			if child.get_meta("from_building") == building or child.get_meta("to_building") == building:
				to_delete.append(child)
	for n in to_delete:
		n.queue_free()
