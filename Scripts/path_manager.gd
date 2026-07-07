extends Node2D

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

signal rail_graph_changed

# Styling
@export var preview_color := Palette.PATH_PREVIEW
@export var final_color := Palette.PATH_FINAL
@export var line_width := 5.0

# Manhattan appearance
@export var port_stub_len := 36.0      # pixels the path extends straight out of a port
@export var corner_radius := 16.0      # pixels
@export var arc_segments := 6          # per rounded corner (higher = smoother)
@export var min_stub_len := 8.0
@export var obstacle_clearance := 10.0
@export var overlap_darken_step := 0.2
@export var overlap_darken_max := 0.48
@export var overlap_lane_tolerance := 1.0
@export var overlap_min_length := 8.0
@export var overlap_overlay_width_reduction := 2.0
@export var direction_indicator_min_path_length := 30.0
@export var direction_indicator_spacing := 220.0
@export var direction_indicator_max_count := 3
@export var direction_indicator_length := 20.0
@export var direction_indicator_width := 14.0

# BuildManager path gating
@export var build_manager_path: NodePath = NodePath("../BuildManager")
@export var endpoints_group := "buildings"

# Default origin port node path
const DEFAULT_FROM_PORT_PATH := NodePath("Ports/Output 1")
const INPUT_PORTS := ["Input 1", "Input 2", "Input 3", "Input 4", "Input 5"]
const RAIL_VERSION_V1 := 0
const RAIL_VERSION_V2 := 1
const RAIL_VERSION_V3 := 2
const V2_FINAL_COLOR := Color8(127, 200, 169, 255)
const V3_FINAL_COLOR := Color8(200, 162, 200, 255)
const RAIL_VISIBILITY_STANDARD := 0
const RAIL_VISIBILITY_HIGH := 1
const RAIL_VISIBILITY_NONE := 2
const RAIL_Z_STANDARD := 0
const RAIL_Z_HIGH_VISIBILITY := 100
const RAIL_ALPHA_VISIBLE := 1.0
const RAIL_ALPHA_HIDDEN := 0.0
const RAIL_HIGH_VISIBILITY_ALPHA_DEFAULT := 1.0
const RAIL_CAPACITY_BADGE_NAME := "RailCapacityBadge"
const RAIL_CAPACITY_TEXT_NAME := "CapacityText"
const RAIL_CAPACITY_BADGE_SIZE := Vector2(46.0, 24.0)
const RAIL_CAPACITY_BADGE_FILL := Color(0.08, 0.10, 0.13, 0.94)
const RAIL_CAPACITY_BADGE_BORDER := Color(0.92, 0.95, 0.98, 0.72)
const RAIL_CAPACITY_BADGE_FONT_SIZE := 13
const RAIL_CAPACITY_BADGE_TEXT := Palette.TEXT_BADGE
const RAIL_CAPACITY_BADGE_TEXT_OUTLINE := Color(0, 0, 0, 0.78)
const FLOW_BADGE_TEXT := Color(0.04, 0.06, 0.08, 1.0)
const FLOW_BADGE_TEXT_OUTLINE := Color(1.0, 1.0, 1.0, 0.42)
const FLOW_BADGE_TEXT_OUTLINE_SIZE := 1
const RAIL_CAPACITY_BADGE_MOUSE_FILTER := Control.MOUSE_FILTER_PASS
const FLOW_BADGE_FILL_ALPHA := 0.86
const FLOW_EPSILON := 0.001
const PATHING_SUPPLY_TOOLTIP_LIMIT := 5

# Selectable flow-simulation debug layers. Each renders a different per-rail metric
# on the capacity badge while flow simulation is active.
const FLOW_LAYER_DELTA := 0        # signed requested-vs-capacity balance (default)
const FLOW_LAYER_USED := 1         # delivered throughput
const FLOW_LAYER_REQUESTED := 2    # requested throughput (incl. blocked pressure)
const FLOW_LAYER_BLOCKED := 3      # flow that could not be delivered
const FLOW_LAYER_AVAILABLE := 4    # spare capacity
const FLOW_LAYER_SATURATION := 5   # used / capacity, as a percentage
const FLOW_LAYER_MIN := FLOW_LAYER_DELTA
const FLOW_LAYER_MAX := FLOW_LAYER_SATURATION

const FLOW_STATE_GOOD := Palette.BUILDING_OUTLINE_EXTRACTION    # balanced / spare
const FLOW_STATE_WARN := Palette.BUILDING_OUTLINE_CRAFTING      # near / over capacity
const FLOW_STATE_BLOCKED := Color8(214, 108, 96, 255)          # saturated / blocked
const FLOW_SATURATION_WARN_THRESHOLD := 0.8

const FLOW_LAYER_NAMES := {
	FLOW_LAYER_DELTA: "Balance",
	FLOW_LAYER_USED: "Used",
	FLOW_LAYER_REQUESTED: "Requested",
	FLOW_LAYER_BLOCKED: "Blocked",
	FLOW_LAYER_AVAILABLE: "Available",
	FLOW_LAYER_SATURATION: "Saturation",
}

const FlowBeadLayerScript := preload("res://Scripts/FlowBeadLayer.gd")
const FLOW_BEAD_LAYER_NAME := "FlowBeadLayer"
const FLOW_BEAD_LAYER_Z := 1
const FLOW_BEAD_REFERENCE_UPM := 480.0
const FLOW_BEAD_MIN_INTENSITY := 0.15

const STORAGE_BADGE_NAME := "StorageFlowBadge"
const STORAGE_BADGE_TEXT_NAME := "StorageFlowText"
const STORAGE_BADGE_SIZE := Vector2(54.0, 24.0)
const STORAGE_BADGE_OFFSET_Y := -58.0
const STORAGE_NODE_KIND := "storage"
const STORAGE_BUILDING_ID_PREFIX := "building_"

# Drag state
var _preview_container: Path2D = null
var _preview_line: Line2D = null
var _from_building: Node2D = null
var _from_port_path: NodePath = DEFAULT_FROM_PORT_PATH
var _rail_version_selector: OptionButton = null
var _selected_rail_version := RAIL_VERSION_V1
var _rail_visibility_mode := RAIL_VISIBILITY_STANDARD
var _high_visibility_alpha := RAIL_HIGH_VISIBILITY_ALPHA_DEFAULT
var _rail_flow_rate_visible := true
var _flow_simulation_enabled := false
var _flow_layer_mode := FLOW_LAYER_DELTA
var _flow_simulation_edge_results: Dictionary = {}
var _flow_simulation_node_results: Dictionary = {}
var _flow_simulation_warnings: Array = []
var _flow_bead_layer: Node2D = null
var _storage_badge_building_ids: Array = []
var _pathing_intelligence_edge_supply: Dictionary = {}
var _ui_scale := 1.0

# Cached nodes
var _build_manager: Node = null


func _ready() -> void:
	_build_manager = get_node_or_null(build_manager_path)
	_apply_rail_visibility_mode()

	# Connect to existing buildings
	_connect_to_buildings()

	# Auto-connect to newly added buildings
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	if not get_tree().node_removed.is_connected(_on_node_removed):
		get_tree().node_removed.connect(_on_node_removed)
	call_deferred("_refresh_path_overlap_shading")


func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	if _flow_bead_layer != null and is_instance_valid(_flow_bead_layer):
		_flow_bead_layer.call("set_scale_factor", _ui_scale)
	_refresh_all_rail_capacity_badges()


func set_rail_version_selector(selector: OptionButton) -> void:
	if _rail_version_selector != null and is_instance_valid(_rail_version_selector):
		if _rail_version_selector.item_selected.is_connected(_on_rail_version_changed):
			_rail_version_selector.item_selected.disconnect(_on_rail_version_changed)

	_rail_version_selector = selector
	if _rail_version_selector == null or not is_instance_valid(_rail_version_selector):
		_selected_rail_version = RAIL_VERSION_V1
		return

	if not _rail_version_selector.item_selected.is_connected(_on_rail_version_changed):
		_rail_version_selector.item_selected.connect(_on_rail_version_changed)
	_on_rail_version_changed(_rail_version_selector.selected)

func _on_rail_version_changed(index: int) -> void:
	_selected_rail_version = clampi(index, RAIL_VERSION_V1, RAIL_VERSION_V3)

func get_selected_rail_version() -> int:
	return _selected_rail_version

func cycle_rail_visibility_mode() -> int:
	set_rail_visibility_mode((_rail_visibility_mode + 1) % 3)
	return _rail_visibility_mode

func set_rail_visibility_mode(mode: int) -> void:
	_rail_visibility_mode = clampi(mode, RAIL_VISIBILITY_STANDARD, RAIL_VISIBILITY_NONE)
	_apply_rail_visibility_mode()

func get_rail_visibility_mode() -> int:
	return _rail_visibility_mode

func get_rail_visibility_mode_name() -> String:
	match _rail_visibility_mode:
		RAIL_VISIBILITY_HIGH:
			return "High Visibility"
		RAIL_VISIBILITY_NONE:
			return "None"
		_:
			return "Standard"

func set_high_visibility_alpha(alpha: float) -> void:
	_high_visibility_alpha = clampf(alpha, RAIL_ALPHA_HIDDEN, RAIL_ALPHA_VISIBLE)
	if _rail_visibility_mode == RAIL_VISIBILITY_HIGH:
		_apply_rail_visibility_mode()

func get_high_visibility_alpha() -> float:
	return _high_visibility_alpha

func set_rail_flow_rate_visible(enabled: bool) -> void:
	if _rail_flow_rate_visible == enabled:
		return
	_rail_flow_rate_visible = enabled
	_refresh_all_rail_capacity_badges()

func is_rail_flow_rate_visible() -> bool:
	return _rail_flow_rate_visible

func toggle_rail_flow_rate_visible() -> bool:
	set_rail_flow_rate_visible(not _rail_flow_rate_visible)
	return _rail_flow_rate_visible

func set_flow_simulation_enabled(enabled: bool) -> void:
	if _flow_simulation_enabled == enabled:
		return
	_flow_simulation_enabled = enabled
	_refresh_all_rail_capacity_badges()

func is_flow_simulation_enabled() -> bool:
	return _flow_simulation_enabled

func set_flow_layer_mode(mode: int) -> void:
	var clamped := clampi(mode, FLOW_LAYER_MIN, FLOW_LAYER_MAX)
	if _flow_layer_mode == clamped:
		return
	_flow_layer_mode = clamped
	if _flow_simulation_enabled:
		_refresh_all_rail_capacity_badges()

func get_flow_layer_mode() -> int:
	return _flow_layer_mode

func cycle_flow_layer_mode() -> int:
	set_flow_layer_mode(FLOW_LAYER_MIN if _flow_layer_mode >= FLOW_LAYER_MAX else _flow_layer_mode + 1)
	return _flow_layer_mode

func get_flow_layer_name() -> String:
	return String(FLOW_LAYER_NAMES.get(_flow_layer_mode, "Balance"))

func set_flow_simulation_result(result: Dictionary) -> void:
	var edges = result.get("edges", {})
	_flow_simulation_edge_results = edges.duplicate(true) if edges is Dictionary else {}
	var nodes = result.get("nodes", {})
	_flow_simulation_node_results = nodes.duplicate(true) if nodes is Dictionary else {}
	var warnings = result.get("warnings", [])
	_flow_simulation_warnings = warnings.duplicate(true) if warnings is Array else []
	_refresh_all_rail_capacity_badges()

func clear_flow_simulation_result() -> void:
	_flow_simulation_edge_results.clear()
	_flow_simulation_node_results.clear()
	_flow_simulation_warnings.clear()
	_refresh_all_rail_capacity_badges()

func set_pathing_intelligence_assessment(assessment: Dictionary) -> void:
	var edge_supply = assessment.get("edge_supply", {})
	_pathing_intelligence_edge_supply = edge_supply.duplicate(true) if edge_supply is Dictionary else {}
	_refresh_all_rail_capacity_badges()

func clear_pathing_intelligence_assessment() -> void:
	_pathing_intelligence_edge_supply.clear()
	_refresh_all_rail_capacity_badges()

func _apply_rail_visibility_mode() -> void:
	var next_alpha := RAIL_ALPHA_VISIBLE
	match _rail_visibility_mode:
		RAIL_VISIBILITY_HIGH:
			z_index = RAIL_Z_HIGH_VISIBILITY
			next_alpha = _high_visibility_alpha
		RAIL_VISIBILITY_NONE:
			z_index = RAIL_Z_STANDARD
			next_alpha = RAIL_ALPHA_HIDDEN
		_:
			z_index = RAIL_Z_STANDARD

	var next_modulate := modulate
	next_modulate.a = next_alpha
	modulate = next_modulate
	_sync_rail_layer_order()

func _sync_rail_layer_order() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	var buildings_root := parent_node.get_node_or_null("buildings")
	if buildings_root == null:
		return

	if _rail_visibility_mode == RAIL_VISIBILITY_HIGH:
		if get_index() != parent_node.get_child_count() - 1:
			parent_node.move_child(self, parent_node.get_child_count() - 1)
		return

	if get_index() > buildings_root.get_index():
		parent_node.move_child(self, buildings_root.get_index())

func get_path_rail_version(path: Path2D) -> int:
	if path == null or not is_instance_valid(path):
		return _selected_rail_version
	if path.has_meta("rail_version"):
		return clampi(int(path.get_meta("rail_version")), RAIL_VERSION_V1, RAIL_VERSION_V3)
	return _selected_rail_version

func _get_final_path_color() -> Color:
	return _get_final_path_color_for_version(_selected_rail_version)

func _get_final_path_color_for_version(rail_version: int) -> Color:
	match clampi(rail_version, RAIL_VERSION_V1, RAIL_VERSION_V3):
		RAIL_VERSION_V2:
			return V2_FINAL_COLOR
		RAIL_VERSION_V3:
			return V3_FINAL_COLOR
		_:
			return final_color


func _get_overlap_tinted_path_color(path: Path2D, overlap_depth: int) -> Color:
	var base_color := _get_final_path_color_for_version(get_path_rail_version(path))
	if overlap_depth <= 0:
		return base_color

	var shaded := base_color.darkened(min(float(overlap_depth) * overlap_darken_step, overlap_darken_max))
	shaded.a = base_color.a
	return shaded

# -------------------------------------------------------------------
# Building discovery / signal wiring
# -------------------------------------------------------------------

func _on_node_added(n: Node) -> void:
	# Prefer group membership, but also allow "duck typing" by signals (group might be assigned in _ready()).
	if n == null:
		return
	if n.is_in_group(endpoints_group) or n.has_signal("port_drag_started"):
		_connect_to_building(n)

func _on_node_removed(n: Node) -> void:
	if n == null:
		return
	if n == _from_building:
		cancel_active_path_drag()

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

func _get_history_host() -> Node:
	var main_scene := get_parent()
	if main_scene == null:
		return null
	if not main_scene.has_method("_capture_history_state") or not main_scene.has_method("_commit_history_action"):
		return null
	return main_scene

func _capture_history_state() -> Dictionary:
	var history_host := _get_history_host()
	if history_host == null:
		return {}
	var captured = history_host.call("_capture_history_state")
	return captured if captured is Dictionary else {}

func _commit_history_action(label: String, before_state: Dictionary) -> void:
	var history_host := _get_history_host()
	if history_host == null:
		return
	history_host.call("_commit_history_action", label, before_state)

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
	if _is_valid_start_port_name(start_port_name):
		return NodePath("Ports/%s" % start_port_name)
	if _is_universal_port_name(start_port_name):
		return NodePath("Ports/%s" % start_port_name)
	if _is_valid_destination_port_name(start_port_name):
		return NodePath("Ports/%s" % start_port_name)
	return DEFAULT_FROM_PORT_PATH

func _is_active_drag_valid() -> bool:
	return is_instance_valid(_preview_container) and is_instance_valid(_preview_line) and is_instance_valid(_from_building)

func _get_tile_size() -> float:
	if _build_manager != null and "tile_size" in _build_manager:
		return max(float(_build_manager.tile_size), 1.0)
	return 64.0

func _get_node_global_center(target_button: Node) -> Variant:
	if target_button is Control:
		var control := target_button as Control
		return control.get_global_transform() * (control.size * 0.5)
	if target_button is Node2D:
		return (target_button as Node2D).global_position
	if "global_position" in target_button:
		return target_button.global_position
	return null

func _get_raw_port_center(building: Node, port_path: NodePath) -> Variant:
	if building == null:
		return null
	var target_button := building.get_node_or_null(port_path)
	if target_button == null:
		return null
	return _get_node_global_center(target_button)

func _get_port_center(building: Node, port_path: NodePath) -> Variant:
	return _get_raw_port_center(building, port_path)


func _get_port_normal(building: Node, port_path: NodePath) -> Vector2:
	# Preferred: explicit metadata on the port Control:
	#   normal = Vector2.LEFT / RIGHT / UP / DOWN
	if building == null:
		return Vector2.RIGHT
	var target_button := building.get_node_or_null(port_path)
	if target_button != null and target_button.has_meta("normal"):
		var normal_standard = target_button.get_meta("normal")
		if normal_standard is Vector2:
			var normal_rotated: Vector2 = normal_standard.normalized()
			if normal_rotated.length() > 0.001:
				if building is Node2D:
					return normal_rotated.rotated((building as Node2D).global_rotation).normalized()
				return normal_rotated

	# Fallback: infer from port position relative to building center (global_position).
	if not (building is Node2D):
		return Vector2.RIGHT
	var building_center := (building as Node2D).global_position
	var port_center = _get_raw_port_center(building, port_path)
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

func _append_unique_scalar(values: Array[float], value: float, epsilon := 0.5) -> void:
	for existing in values:
		if abs(existing - value) <= epsilon:
			return
	values.append(value)

func _polyline_length(points: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total

func _get_polyline_bounds(points: Array[Vector2], padding := 0.0) -> Rect2:
	if points.is_empty():
		return Rect2()

	var min_x := points[0].x
	var max_x := points[0].x
	var min_y := points[0].y
	var max_y := points[0].y

	for point in points:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)

	return Rect2(
		Vector2(min_x - padding, min_y - padding),
		Vector2((max_x - min_x) + padding * 2.0, (max_y - min_y) + padding * 2.0)
	)

func _append_candidate(candidates: Array, points: Array[Vector2]) -> void:
	var candidate := _sanitize_polyline(points)
	if candidate.size() >= 2:
		candidates.append(candidate)


func _compact_candidate_score(candidate: Array[Vector2]) -> float:
	return _polyline_length(candidate) + float(max(candidate.size() - 2, 0)) * 96.0


func _compact_stub_candidate_score(candidate: Array[Vector2], departure_stub_axis: Vector2, arrival_stub_axis: Vector2 = Vector2.ZERO) -> float:
	var score := _compact_candidate_score(candidate)
	if candidate.size() < 2:
		return score

	var departure_axis := _route_axis(departure_stub_axis)
	if departure_axis != Vector2.ZERO:
		var first_segment := candidate[1] - candidate[0]
		if first_segment.length() > 0.5:
			var first_dir := _dominant_axis_normal(first_segment)
			var departure_alignment := first_dir.dot(departure_axis)
			if departure_alignment < -0.5:
				score += 48.0
			elif departure_alignment < 0.5:
				score += 18.0

	var arrival_axis := _route_axis(arrival_stub_axis)
	if arrival_axis != Vector2.ZERO:
		var last_segment := candidate[candidate.size() - 1] - candidate[candidate.size() - 2]
		if last_segment.length() > 0.5:
			var last_dir := _dominant_axis_normal(last_segment)
			var arrival_alignment := last_dir.dot(-arrival_axis)
			if arrival_alignment < -0.5:
				score += 48.0
			elif arrival_alignment < 0.5:
				score += 18.0

	return score


func _build_compact_direct_polyline(a: Vector2, b: Vector2, ignored_buildings: Array = [], departure_stub_axis: Vector2 = Vector2.ZERO, arrival_stub_axis: Vector2 = Vector2.ZERO) -> Array[Vector2]:
	var tile_size := _get_tile_size()
	var compact_span = max(abs(a.x - b.x), abs(a.y - b.y))
	if compact_span > tile_size * 1.75 and a.distance_to(b) > tile_size * 2.25:
		return []

	var candidates: Array = []
	_append_candidate(candidates, [a, b])
	_append_candidate(candidates, [a, Vector2(b.x, a.y), b])
	_append_candidate(candidates, [a, Vector2(a.x, b.y), b])

	var best_candidate: Array[Vector2] = []
	var best_score := INF
	for candidate_variant in candidates:
		var candidate: Array[Vector2] = candidate_variant
		if not _polyline_is_clear(candidate, ignored_buildings):
			continue

		var score := _compact_stub_candidate_score(candidate, departure_stub_axis, arrival_stub_axis)
		if score < best_score:
			best_score = score
			best_candidate = candidate

	return best_candidate


func _simplify_up_origin_departure(points: Array[Vector2], ignored_buildings: Array, from_n: Vector2, from_building: Node2D = null) -> Array[Vector2]:
	if _route_axis(from_n) != Vector2.UP:
		return points
	if points.size() < 5:
		return points

	var local_ignored_buildings := ignored_buildings.duplicate()
	if from_building != null and not local_ignored_buildings.has(from_building):
		local_ignored_buildings.append(from_building)

	var stub_point := points[1]
	var max_target_index = min(points.size() - 2, 4)
	for target_index in range(max_target_index, 2, -1):
		var target_point := points[target_index]
		var simplified_slice := _build_compact_direct_polyline(stub_point, target_point, local_ignored_buildings, from_n)
		if simplified_slice.is_empty():
			continue

		var original_slice: Array[Vector2] = []
		for i in range(1, target_index + 1):
			original_slice.append(points[i])

		if simplified_slice.size() >= original_slice.size():
			continue
		if _compact_candidate_score(simplified_slice) > _compact_candidate_score(original_slice) + 0.5:
			continue

		var simplified_points: Array[Vector2] = [points[0]]
		for point in simplified_slice:
			if simplified_points[simplified_points.size() - 1].distance_to(point) > 0.5:
				simplified_points.append(point)
		for i in range(target_index + 1, points.size()):
			if simplified_points[simplified_points.size() - 1].distance_to(points[i]) > 0.5:
				simplified_points.append(points[i])

		return _sanitize_polyline(simplified_points)

	return points


func _simplify_up_origin_destination_arrival(points: Array[Vector2], ignored_buildings: Array, from_n: Vector2, to_n: Vector2, to_building: Node2D = null) -> Array[Vector2]:
	if _route_axis(from_n) != Vector2.UP:
		return points
	if points.size() < 6:
		return points

	var local_ignored_buildings := ignored_buildings.duplicate()
	if to_building != null and not local_ignored_buildings.has(to_building):
		local_ignored_buildings.append(to_building)

	var stub_point := points[points.size() - 2]
	var min_start_index = max(2, points.size() - 5)
	for start_index in range(min_start_index, points.size() - 2):
		var start_point := points[start_index]
		var simplified_slice := _build_compact_direct_polyline(start_point, stub_point, local_ignored_buildings, Vector2.ZERO, to_n)
		if simplified_slice.is_empty():
			continue

		var original_slice: Array[Vector2] = []
		for i in range(start_index, points.size() - 1):
			original_slice.append(points[i])

		if simplified_slice.size() >= original_slice.size():
			continue
		if _compact_candidate_score(simplified_slice) > _compact_candidate_score(original_slice) + 0.5:
			continue

		var simplified_points: Array[Vector2] = []
		for i in range(start_index):
			simplified_points.append(points[i])
		for point in simplified_slice:
			if simplified_points.is_empty() or simplified_points[simplified_points.size() - 1].distance_to(point) > 0.5:
				simplified_points.append(point)
		if simplified_points[simplified_points.size() - 1].distance_to(points[points.size() - 1]) > 0.5:
			simplified_points.append(points[points.size() - 1])

		return _sanitize_polyline(simplified_points)

	return points


func _simplify_opposite_vertical_port_link(a: Vector2, a2: Vector2, b: Vector2, current_points: Array[Vector2], ignored_buildings: Array, from_n: Vector2, to_n: Vector2) -> Array[Vector2]:
	if _route_axis(from_n) != Vector2.UP or _route_axis(to_n) != Vector2.DOWN:
		return current_points

	var local_ignored_buildings := ignored_buildings.duplicate()
	var candidates: Array = []
	_append_candidate(candidates, [a, a2, b])
	_append_candidate(candidates, [a, a2, Vector2(b.x, a2.y), b])
	_append_candidate(candidates, [a, Vector2(a.x, b.y), b])

	var current_score := _compact_candidate_score(current_points)
	var best_candidate: Array[Vector2] = current_points
	var best_score := current_score

	for candidate_variant in candidates:
		var candidate: Array[Vector2] = candidate_variant
		if not _polyline_is_clear(candidate, local_ignored_buildings):
			continue

		var score := _compact_candidate_score(candidate)
		if score + 0.5 < best_score:
			best_score = score
			best_candidate = candidate

	return best_candidate


func _build_point_window(points: Array[Vector2], start_index: int, end_index: int) -> Array[Vector2]:
	var window: Array[Vector2] = []
	for i in range(start_index, end_index + 1):
		window.append(points[i])
	return window


func _replace_point_window(points: Array[Vector2], start_index: int, end_index: int, replacement: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in range(start_index):
		result.append(points[i])
	for point in replacement:
		if result.is_empty() or result[result.size() - 1].distance_to(point) > 0.5:
			result.append(point)
	for i in range(end_index + 1, points.size()):
		if result.is_empty() or result[result.size() - 1].distance_to(points[i]) > 0.5:
			result.append(points[i])
	return result


func _simplify_local_wiggles(points: Array[Vector2], ignored_buildings: Array) -> Array[Vector2]:
	var simplified := _sanitize_polyline(points)
	if simplified.size() < 4:
		return simplified

	var changed := true
	var passes := 0
	while changed and passes < 8:
		changed = false
		passes += 1

		# Keep the actual origin/destination neighborhoods intact; this pass is only for interior zigzags.
		for start_index in range(1, simplified.size() - 4):
			var window := _build_point_window(simplified, start_index, start_index + 3)
			var dir_one := window[1] - window[0]
			var dir_two := window[2] - window[1]
			var dir_three := window[3] - window[2]
			if dir_one.length() <= 0.5 or dir_two.length() <= 0.5 or dir_three.length() <= 0.5:
				continue

			var axis_one := _dominant_axis_normal(dir_one)
			var axis_two := _dominant_axis_normal(dir_two)
			var axis_three := _dominant_axis_normal(dir_three)
			if axis_one == axis_two or axis_two == axis_three or axis_one != axis_three:
				continue

			var replacement := _build_compact_direct_polyline(window[0], window[3], ignored_buildings)
			if replacement.is_empty():
				continue
			if replacement.size() >= window.size():
				continue
			if _compact_candidate_score(replacement) > _compact_candidate_score(window) + 0.5:
				continue

			simplified = _sanitize_polyline(_replace_point_window(simplified, start_index, start_index + 3, replacement))
			changed = true
			break

	return simplified


func _build_mid_route_slice(points: Array[Vector2]) -> Array[Vector2]:
	var mid_points: Array[Vector2] = []
	if points.size() < 2:
		return mid_points

	for i in range(1, points.size() - 1):
		mid_points.append(points[i])
	return mid_points


func _simplify_compact_full_route(points: Array[Vector2], ignored_buildings: Array, from_n: Vector2, to_n: Vector2) -> Array[Vector2]:
	var simplified := _sanitize_polyline(points)
	if simplified.size() < 4:
		return simplified

	var from_axis := _route_axis(from_n)
	var to_axis := _route_axis(to_n)
	if from_axis != Vector2.ZERO and to_axis != Vector2.ZERO and from_axis.dot(to_axis) > 0.99:
		return simplified

	var a := simplified[0]
	var a2 := simplified[1]
	var b := simplified[simplified.size() - 1]
	var b2 := simplified[simplified.size() - 2]
	var tile_size := _get_tile_size()
	var compact_span = max(abs(a2.x - b2.x), abs(a2.y - b2.y))
	if compact_span > tile_size * 1.75 and a2.distance_to(b2) > tile_size * 2.25:
		return simplified

	var candidates: Array = []
	if is_equal_approx(a2.x, b2.x) or is_equal_approx(a2.y, b2.y):
		_append_candidate(candidates, [a, a2, b2, b])
	_append_candidate(candidates, [a, a2, Vector2(b2.x, a2.y), b2, b])
	_append_candidate(candidates, [a, a2, Vector2(a2.x, b2.y), b2, b])

	var best_candidate: Array[Vector2] = simplified
	var best_score := _candidate_score(simplified, from_n, to_n)

	for candidate_variant in candidates:
		var candidate: Array[Vector2] = candidate_variant
		var mid_slice := _build_mid_route_slice(candidate)
		if not _polyline_is_clear(mid_slice, ignored_buildings):
			continue

		var score := _candidate_score(candidate, from_n, to_n)
		if score + 0.5 < best_score:
			best_score = score
			best_candidate = candidate
		elif abs(score - best_score) <= 0.5 and candidate.size() < best_candidate.size():
			best_candidate = candidate

	return _sanitize_polyline(best_candidate)

func _route_axis(normal: Vector2) -> Vector2:
	if normal.length() <= 0.001:
		return Vector2.ZERO
	return _dominant_axis_normal(normal)

func _route_detour_distance(a: Vector2, b: Vector2) -> float:
	var tile_size := _get_tile_size()
	var span = max(abs(a.x - b.x), abs(a.y - b.y))
	return max(tile_size * 0.5, min(span * 0.2, tile_size * 1.5), corner_radius + obstacle_clearance)

func _append_orientation_candidates(candidates: Array, a: Vector2, b: Vector2, from_n: Vector2, to_n: Vector2) -> void:
	var from_axis := _route_axis(from_n)
	var to_axis := _route_axis(to_n)
	if from_axis == Vector2.ZERO or to_axis == Vector2.ZERO:
		return

	var mid_x := (a.x + b.x) * 0.5
	var mid_y := (a.y + b.y) * 0.5
	_append_candidate(candidates, [a, Vector2(mid_x, a.y), Vector2(mid_x, b.y), b])
	_append_candidate(candidates, [a, Vector2(a.x, mid_y), Vector2(b.x, mid_y), b])

	var dot := from_axis.dot(to_axis)
	var detour := _route_detour_distance(a, b)

	if dot > 0.99:
		if abs(from_axis.y) > 0.0:
			var outer_y = (min(a.y, b.y) if from_axis.y < 0.0 else max(a.y, b.y)) + from_axis.y * detour
			_append_candidate(candidates, [a, Vector2(a.x, outer_y), Vector2(b.x, outer_y), b])
		else:
			var outer_x = (min(a.x, b.x) if from_axis.x < 0.0 else max(a.x, b.x)) + from_axis.x * detour
			_append_candidate(candidates, [a, Vector2(outer_x, a.y), Vector2(outer_x, b.y), b])
		return

	if dot < -0.99:
		if abs(from_axis.x) > 0.0:
			_append_candidate(candidates, [a, Vector2(mid_x, a.y), Vector2(mid_x, b.y), b])
		else:
			_append_candidate(candidates, [a, Vector2(a.x, mid_y), Vector2(b.x, mid_y), b])
		return

	if abs(from_axis.y) > 0.0:
		_append_candidate(candidates, [a, Vector2(a.x, mid_y), Vector2(b.x, mid_y), b])
	else:
		_append_candidate(candidates, [a, Vector2(mid_x, a.y), Vector2(mid_x, b.y), b])

func _get_occupied_cells() -> Dictionary:
	if _build_manager == null or not ("occupied_cells" in _build_manager):
		return {}
	var cells = _build_manager.occupied_cells
	return cells if cells is Dictionary else {}

func _get_cell_world_rect(cell: Vector2i) -> Rect2:
	var tile_size := _get_tile_size()
	var top_left := Vector2(cell.x, cell.y) * tile_size
	if _build_manager != null and _build_manager.has_method("cell_to_world"):
		top_left = _build_manager.cell_to_world(cell)
	return Rect2(top_left, Vector2(tile_size, tile_size))

func _get_nearby_obstacle_rects(bounds: Rect2, ignored_buildings: Array) -> Array[Rect2]:
	var obstacles: Array[Rect2] = []
	var occupied_cells := _get_occupied_cells()
	if occupied_cells.is_empty():
		return obstacles

	for cell in occupied_cells.keys():
		var occupant = occupied_cells[cell]
		if ignored_buildings.has(occupant):
			continue
		var obstacle_rect := _get_cell_world_rect(cell)
		if obstacle_rect.intersects(bounds):
			obstacles.append(obstacle_rect)
	return obstacles

func _segment_intersects_rect(start: Vector2, end: Vector2, rect: Rect2) -> bool:
	if is_equal_approx(start.x, end.x):
		var x := start.x
		if x < rect.position.x or x > rect.position.x + rect.size.x:
			return false
		var min_y = min(start.y, end.y)
		var max_y = max(start.y, end.y)
		return max_y >= rect.position.y and min_y <= rect.position.y + rect.size.y

	if is_equal_approx(start.y, end.y):
		var y := start.y
		if y < rect.position.y or y > rect.position.y + rect.size.y:
			return false
		var min_x = min(start.x, end.x)
		var max_x = max(start.x, end.x)
		return max_x >= rect.position.x and min_x <= rect.position.x + rect.size.x

	return false

func _polyline_is_clear(points: Array[Vector2], ignored_buildings: Array) -> bool:
	if points.size() < 2:
		return true

	var blocked_cells := _get_blocked_route_cells(ignored_buildings)
	if blocked_cells.is_empty():
		return true

	for i in range(1, points.size()):
		var start := points[i - 1]
		var end := points[i]
		if not (is_equal_approx(start.x, end.x) or is_equal_approx(start.y, end.y)):
			return false

		if _segment_hits_blocked_cells(start, end, blocked_cells):
			return false

	return true


func _route_enters_building_body(points: Array[Vector2], endpoint_bodies: Array) -> bool:
	# True if the route passes through the *body* of an endpoint building. Only
	# the footprint cells on the port's interior side (opposite the outward
	# normal) count: a legitimate approach enters from the outward side and stops
	# at the port, while a pass-through crosses to the far/interior side. This is
	# robust to exactly where the port sits within the footprint.
	if points.size() < 2:
		return false
	var occupied := _get_occupied_cells()
	if occupied.is_empty():
		return false

	var body_cells := {}
	for meta_variant in endpoint_bodies:
		var meta: Dictionary = meta_variant
		var building = meta.get("building")
		if building == null or not is_instance_valid(building):
			continue
		var port_cell := _world_to_cell(meta.get("port", Vector2.ZERO))
		var interior := -_dominant_axis_normal(meta.get("normal", Vector2.RIGHT))
		for cell_variant in occupied.keys():
			var cell: Vector2i = cell_variant
			if occupied[cell] != building:
				continue
			var relative := Vector2(cell - port_cell)
			if relative.dot(interior) > 0.5:
				body_cells[cell] = true

	if body_cells.is_empty():
		return false

	for i in range(1, points.size()):
		if _segment_hits_blocked_cells(points[i - 1], points[i], body_cells):
			return true
	return false


func _candidate_score(candidate: Array[Vector2], from_n: Vector2, to_n: Vector2) -> float:
	var score := _polyline_length(candidate) + float(max(candidate.size() - 2, 0)) * 12.0
	var preferred_segment_length = max(corner_radius * 1.5, 12.0)
	var preferred_turn_after_stub = max(port_stub_len * 0.35, 4.0)

	for i in range(1, candidate.size()):
		var segment_length := candidate[i - 1].distance_to(candidate[i])
		if segment_length < preferred_segment_length:
			score += (preferred_segment_length - segment_length) * 4.0

	var from_axis := _route_axis(from_n)
	var to_axis := _route_axis(to_n)
	if candidate.size() >= 2 and from_axis != Vector2.ZERO:
		var first_segment := candidate[1] - candidate[0]
		if first_segment.length() > 0.5:
			var first_dir := _dominant_axis_normal(first_segment)
			var first_alignment := first_dir.dot(from_axis)
			if first_alignment < -0.5:
				score += 42.0
			elif first_alignment > 0.99 and candidate.size() > 2 and first_segment.length() > preferred_turn_after_stub:
				score += (first_segment.length() - preferred_turn_after_stub) * 3.5

	if candidate.size() >= 2 and to_axis != Vector2.ZERO:
		var last_segment := candidate[candidate.size() - 1] - candidate[candidate.size() - 2]
		if last_segment.length() > 0.5:
			var last_dir := _dominant_axis_normal(last_segment)
			var last_alignment := last_dir.dot(-to_axis)
			if last_alignment < -0.5:
				score += 42.0
			elif last_alignment > 0.99 and candidate.size() > 2 and last_segment.length() > preferred_turn_after_stub:
				score += (last_segment.length() - preferred_turn_after_stub) * 3.5

	if from_axis != Vector2.ZERO and to_axis != Vector2.ZERO and from_axis.dot(to_axis) > 0.99 and candidate.size() <= 3:
		score += 24.0

	return score


func _get_cell_center(cell: Vector2i) -> Vector2:
	return _get_cell_world_rect(cell).get_center()


func _get_building_cells_for_routing(building: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if building == null:
		return cells

	if _build_manager != null and _build_manager.has_method("_anchor_cell_from_building_position") and _build_manager.has_method("get_building_cells"):
		var anchor_cell = _build_manager.call("_anchor_cell_from_building_position", building, building.global_position)
		if anchor_cell is Vector2i:
			var routed_cells = _build_manager.call("get_building_cells", building, anchor_cell)
			if routed_cells is Array:
				for cell_variant in routed_cells:
					if cell_variant is Vector2i:
						cells.append(cell_variant)
				if not cells.is_empty():
					return cells

	var occupied_cells := _get_occupied_cells()
	for cell_variant in occupied_cells.keys():
		if occupied_cells[cell_variant] == building and cell_variant is Vector2i:
			cells.append(cell_variant)

	return cells


func _get_building_cell_rect(building: Node) -> Rect2i:
	var cells := _get_building_cells_for_routing(building)
	if cells.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)

	var min_x := cells[0].x
	var max_x := cells[0].x
	var min_y := cells[0].y
	var max_y := cells[0].y

	for cell in cells:
		min_x = min(min_x, cell.x)
		max_x = max(max_x, cell.x)
		min_y = min(min_y, cell.y)
		max_y = max(max_y, cell.y)

	return Rect2i(
		Vector2i(min_x, min_y),
		Vector2i((max_x - min_x) + 1, (max_y - min_y) + 1)
	)


func _get_building_world_rect(building: Node) -> Rect2:
	var cell_rect := _get_building_cell_rect(building)
	if cell_rect.size == Vector2i.ZERO:
		return Rect2()

	var top_left := _get_cell_world_rect(cell_rect.position).position
	var tile_size := _get_tile_size()
	return Rect2(top_left, Vector2(cell_rect.size.x * tile_size, cell_rect.size.y * tile_size))


func _get_required_stub_clearance() -> float:
	return max(corner_radius + line_width * 0.5 + obstacle_clearance + 2.0, obstacle_clearance + 4.0, 8.0)


func _get_standard_stub_point(port_pos: Vector2, normal: Vector2) -> Vector2:
	var axis := _dominant_axis_normal(normal)
	return port_pos + axis * max(port_stub_len, 1.0)


func _stub_clears_building_rect(building: Node2D, stub_point: Vector2, normal: Vector2, clearance: float) -> bool:
	var building_rect := _get_building_world_rect(building)
	if building_rect.size == Vector2.ZERO:
		return true

	var axis := _dominant_axis_normal(normal)
	if axis == Vector2.RIGHT:
		return stub_point.x >= building_rect.position.x + building_rect.size.x + clearance
	if axis == Vector2.LEFT:
		return stub_point.x <= building_rect.position.x - clearance
	if axis == Vector2.DOWN:
		return stub_point.y >= building_rect.position.y + building_rect.size.y + clearance
	return stub_point.y <= building_rect.position.y - clearance


func _stub_hits_other_buildings(start: Vector2, end: Vector2, ignored_buildings: Array) -> bool:
	var segment_padding = line_width * 0.5 + 1.0
	var segment_bounds := _get_polyline_bounds([start, end], segment_padding)
	var nearby_obstacles := _get_nearby_obstacle_rects(segment_bounds, ignored_buildings)

	for obstacle in nearby_obstacles:
		if _segment_intersects_rect(start, end, obstacle.grow(segment_padding)):
			return true

	return false


func _get_outward_clearance_point(building: Node2D, port_pos: Vector2, normal: Vector2) -> Vector2:
	var axis := _dominant_axis_normal(normal)
	var base_distance = max(port_stub_len, 1.0)
	var fallback = port_pos + axis * base_distance
	var building_rect := _get_building_world_rect(building)
	if building_rect.size == Vector2.ZERO:
		return fallback

	# Leave enough room for the rounded corner so the visual bend cannot curl back into the building body.
	var clearance = _get_required_stub_clearance()
	if axis == Vector2.RIGHT:
		return Vector2(max(fallback.x, building_rect.position.x + building_rect.size.x + clearance), port_pos.y)
	if axis == Vector2.LEFT:
		return Vector2(min(fallback.x, building_rect.position.x - clearance), port_pos.y)
	if axis == Vector2.DOWN:
		return Vector2(port_pos.x, max(fallback.y, building_rect.position.y + building_rect.size.y + clearance))
	return Vector2(port_pos.x, min(fallback.y, building_rect.position.y - clearance))


func _get_stub_endpoint(building: Node2D, port_pos: Vector2, normal: Vector2) -> Vector2:
	var standard_stub := _get_standard_stub_point(port_pos, normal)
	var clearance := _get_required_stub_clearance()
	var ignored_buildings: Array = []
	if building != null:
		ignored_buildings.append(building)

	var needs_collision_escape := not _stub_clears_building_rect(building, standard_stub, normal, clearance)
	if not needs_collision_escape and not _stub_hits_other_buildings(port_pos, standard_stub, ignored_buildings):
		return standard_stub

	var axis := _dominant_axis_normal(normal)
	var candidate := _get_outward_clearance_point(building, port_pos, normal)
	if not _stub_hits_other_buildings(port_pos, candidate, ignored_buildings):
		return candidate

	var extension_step := _get_tile_size()
	for i in range(1, 5):
		var extended_candidate := candidate + axis * extension_step * float(i)
		if not _stub_hits_other_buildings(port_pos, extended_candidate, ignored_buildings):
			return extended_candidate

	return candidate


func _world_to_cell(pos: Vector2) -> Vector2i:
	if _build_manager != null and _build_manager.has_method("world_to_cell"):
		return _build_manager.world_to_cell(pos)
	return Vector2i(floor(pos.x / _get_tile_size()), floor(pos.y / _get_tile_size()))


func _rect2i_has_point(rect: Rect2i, point: Vector2i) -> bool:
	return (
		point.x >= rect.position.x
		and point.y >= rect.position.y
		and point.x < rect.position.x + rect.size.x
		and point.y < rect.position.y + rect.size.y
	)


func _intersect_rect2i(a: Rect2i, b: Rect2i) -> Rect2i:
	var left = max(a.position.x, b.position.x)
	var top = max(a.position.y, b.position.y)
	var right = min(a.position.x + a.size.x, b.position.x + b.size.x)
	var bottom = min(a.position.y + a.size.y, b.position.y + b.size.y)
	if right <= left or bottom <= top:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	return Rect2i(Vector2i(left, top), Vector2i(right - left, bottom - top))


func _world_rect_to_cell_rect(rect: Rect2) -> Rect2i:
	var min_x = min(rect.position.x, rect.position.x + rect.size.x)
	var max_x = max(rect.position.x, rect.position.x + rect.size.x)
	var min_y = min(rect.position.y, rect.position.y + rect.size.y)
	var max_y = max(rect.position.y, rect.position.y + rect.size.y)
	var start_cell := _world_to_cell(Vector2(min_x, min_y))
	var end_cell := _world_to_cell(Vector2(max_x - 0.001, max_y - 0.001))
	var left = min(start_cell.x, end_cell.x)
	var top = min(start_cell.y, end_cell.y)
	var right = max(start_cell.x, end_cell.x)
	var bottom = max(start_cell.y, end_cell.y)
	return Rect2i(Vector2i(left, top), Vector2i(right - left + 1, bottom - top + 1))


func _get_grid_search_bounds() -> Rect2i:
	if _build_manager != null and "tile_map_layer" in _build_manager:
		var layer = _build_manager.tile_map_layer
		if layer != null and is_instance_valid(layer):
			var used_rect: Rect2i = layer.get_used_rect()
			if used_rect.size != Vector2i.ZERO:
				var padding := Vector2i(2, 2)
				return Rect2i(used_rect.position - padding, used_rect.size + padding * 2)
	return Rect2i(Vector2i.ZERO, Vector2i.ZERO)


func _get_blocked_route_cells(ignored_buildings: Array) -> Dictionary:
	var blocked := {}
	var occupied_cells := _get_occupied_cells()
	for cell in occupied_cells.keys():
		var occupant = occupied_cells[cell]
		if ignored_buildings.has(occupant):
			continue
		blocked[cell] = true
	return blocked


func _append_unique_direction(directions: Array, direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	for existing in directions:
		if existing == direction:
			return
	directions.append(direction)


func _preferred_neighbor_directions(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var directions: Array = []
	var delta := to_cell - from_cell
	var step_x := 1 if delta.x > 0 else (-1 if delta.x < 0 else 0)
	var step_y := 1 if delta.y > 0 else (-1 if delta.y < 0 else 0)

	if abs(delta.x) >= abs(delta.y):
		_append_unique_direction(directions, Vector2i(step_x, 0))
		_append_unique_direction(directions, Vector2i(0, step_y))
	else:
		_append_unique_direction(directions, Vector2i(0, step_y))
		_append_unique_direction(directions, Vector2i(step_x, 0))

	_append_unique_direction(directions, Vector2i(-step_x, 0))
	_append_unique_direction(directions, Vector2i(0, -step_y))
	_append_unique_direction(directions, Vector2i.LEFT)
	_append_unique_direction(directions, Vector2i.RIGHT)
	_append_unique_direction(directions, Vector2i.UP)
	_append_unique_direction(directions, Vector2i.DOWN)
	return directions


func _get_route_search_rect(start_cell: Vector2i, end_cell: Vector2i, blocked_cells: Dictionary, margin: int) -> Rect2i:
	var min_x = min(start_cell.x, end_cell.x)
	var max_x = max(start_cell.x, end_cell.x)
	var min_y = min(start_cell.y, end_cell.y)
	var max_y = max(start_cell.y, end_cell.y)

	var base_rect := Rect2i(
		Vector2i(min_x - margin * 2, min_y - margin * 2),
		Vector2i((max_x - min_x) + 1 + margin * 4, (max_y - min_y) + 1 + margin * 4)
	)

	for cell_variant in blocked_cells.keys():
		var cell: Vector2i = cell_variant
		if not _rect2i_has_point(base_rect, cell):
			continue
		min_x = min(min_x, cell.x)
		max_x = max(max_x, cell.x)
		min_y = min(min_y, cell.y)
		max_y = max(max_y, cell.y)

	var search_rect := Rect2i(
		Vector2i(min_x - margin, min_y - margin),
		Vector2i((max_x - min_x) + 1 + margin * 2, (max_y - min_y) + 1 + margin * 2)
	)

	var grid_bounds := _get_grid_search_bounds()
	if grid_bounds.size != Vector2i.ZERO:
		var clipped := _intersect_rect2i(search_rect, grid_bounds)
		if clipped.size != Vector2i.ZERO:
			return clipped

	return search_rect


func _find_cell_path(start_cell: Vector2i, end_cell: Vector2i, blocked_cells: Dictionary, search_rect: Rect2i) -> Array:
	var frontier: Array = [start_cell]
	var came_from := {start_cell: start_cell}
	var head := 0

	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1

		if current == end_cell:
			break

		for direction_variant in _preferred_neighbor_directions(current, end_cell):
			var direction: Vector2i = direction_variant
			var next := current + direction
			if not _rect2i_has_point(search_rect, next):
				continue
			if blocked_cells.has(next) and next != start_cell and next != end_cell:
				continue
			if came_from.has(next):
				continue

			frontier.append(next)
			came_from[next] = current

	if not came_from.has(end_cell):
		return []

	var path: Array = []
	var cursor: Vector2i = end_cell
	while cursor != start_cell:
		path.push_front(cursor)
		cursor = came_from[cursor]
	path.push_front(start_cell)
	return path


func _append_distinct_point(points: Array[Vector2], point: Vector2) -> void:
	if points.is_empty() or points[points.size() - 1].distance_to(point) > 0.5:
		points.append(point)


func _append_start_connector(points: Array[Vector2], from_point: Vector2, to_point: Vector2, from_n: Vector2) -> void:
	_append_distinct_point(points, from_point)
	if from_point.distance_to(to_point) <= 0.5:
		return
	if is_equal_approx(from_point.x, to_point.x) or is_equal_approx(from_point.y, to_point.y):
		_append_distinct_point(points, to_point)
		return

	var pivot := Vector2(to_point.x, from_point.y)
	if abs(from_n.y) > abs(from_n.x):
		pivot = Vector2(from_point.x, to_point.y)

	_append_distinct_point(points, pivot)
	_append_distinct_point(points, to_point)


func _append_end_connector(points: Array[Vector2], from_point: Vector2, to_point: Vector2, to_n: Vector2) -> void:
	_append_distinct_point(points, from_point)
	if from_point.distance_to(to_point) <= 0.5:
		return
	if is_equal_approx(from_point.x, to_point.x) or is_equal_approx(from_point.y, to_point.y):
		_append_distinct_point(points, to_point)
		return

	var pivot := Vector2(from_point.x, to_point.y)
	if abs(to_n.y) > abs(to_n.x):
		pivot = Vector2(to_point.x, from_point.y)

	_append_distinct_point(points, pivot)
	_append_distinct_point(points, to_point)


func _segment_hits_blocked_cells(start: Vector2, end: Vector2, blocked_cells: Dictionary) -> bool:
	if blocked_cells.is_empty():
		return false

	var min_x = min(start.x, end.x)
	var max_x = max(start.x, end.x)
	var min_y = min(start.y, end.y)
	var max_y = max(start.y, end.y)
	var collision_padding = max(line_width * 0.5 + 1.0, 2.0)
	var segment_rect := Rect2(
		Vector2(min_x, min_y),
		Vector2(max(max_x - min_x, 0.001), max(max_y - min_y, 0.001))
	).grow(collision_padding)

	var cell_rect := _world_rect_to_cell_rect(segment_rect)
	for y in range(cell_rect.position.y, cell_rect.position.y + cell_rect.size.y):
		for x in range(cell_rect.position.x, cell_rect.position.x + cell_rect.size.x):
			var cell := Vector2i(x, y)
			if not blocked_cells.has(cell):
				continue

			var obstacle_rect := _get_cell_world_rect(cell).grow(collision_padding)
			if _segment_intersects_rect(start, end, obstacle_rect):
				return true

	return false


func _find_building_ancestor(node: Node) -> Node2D:
	var current := node
	while current != null:
		if current is Node2D and (current.is_in_group(endpoints_group) or current.has_signal("port_drag_started")):
			return current as Node2D
		current = current.get_parent()
	return null


func _get_preview_target_info(mouse_pos: Vector2, from_pos: Vector2) -> Dictionary:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered is Button and hovered.is_in_group("port_button"):
		var hovered_button := hovered as Button
		var target_building := _find_building_ancestor(hovered_button)
		if target_building != null and target_building != _from_building and _is_valid_destination_port_name(hovered_button.name):
			var target_port_path := NodePath("Ports/%s" % hovered_button.name)
			var target_pos = _get_port_center(target_building, target_port_path)
			if target_pos != null:
				return {
					"position": target_pos,
					"normal": _get_port_normal(target_building, target_port_path),
					"ignored": [_from_building, target_building],
					"building": target_building,
				}

	return {
		"position": mouse_pos,
		"normal": _dominant_axis_normal(from_pos - mouse_pos),
		"ignored": [_from_building],
		"building": null,
	}


func _build_grid_fallback_polyline(a: Vector2, b: Vector2, from_n: Vector2, to_n: Vector2, ignored_buildings: Array = []) -> Array[Vector2]:
	var blocked_cells := _get_blocked_route_cells(ignored_buildings)
	var start_cell := _world_to_cell(a)
	var end_cell := _world_to_cell(b)

	for margin in [4, 8, 12]:
		var search_rect := _get_route_search_rect(start_cell, end_cell, blocked_cells, margin)
		if search_rect.size == Vector2i.ZERO:
			continue

		var cell_path := _find_cell_path(start_cell, end_cell, blocked_cells, search_rect)
		if cell_path.is_empty():
			continue

		var points: Array[Vector2] = []
		var first_center := _get_cell_center(cell_path[0])
		_append_start_connector(points, a, first_center, from_n)

		for i in range(1, cell_path.size()):
			_append_distinct_point(points, _get_cell_center(cell_path[i]))

		var last_center := _get_cell_center(cell_path[cell_path.size() - 1])
		_append_end_connector(points, last_center, b, to_n)

		var candidate := _sanitize_polyline(points)
		if _polyline_is_clear(candidate, ignored_buildings):
			return candidate

	return []

func _build_manhattan_polyline(a: Vector2, b: Vector2, from_n: Vector2, to_n: Vector2, ignored_buildings: Array = []) -> Array[Vector2]:
	var compact_route := _build_compact_direct_polyline(a, b, ignored_buildings, from_n, to_n)
	if not compact_route.is_empty():
		return compact_route

	var candidates: Array = []
	_append_candidate(candidates, [a, b])
	_append_candidate(candidates, [a, Vector2(b.x, a.y), b])
	_append_candidate(candidates, [a, Vector2(a.x, b.y), b])
	_append_orientation_candidates(candidates, a, b, from_n, to_n)

	var tile_size := _get_tile_size()
	var direct_bounds := _get_polyline_bounds([a, b], tile_size * 3.0)
	var nearby_obstacles := _get_nearby_obstacle_rects(direct_bounds, ignored_buildings)
	var x_guides: Array[float] = [a.x, b.x]
	var y_guides: Array[float] = [a.y, b.y]
	_append_unique_scalar(x_guides, (a.x + b.x) * 0.5)
	_append_unique_scalar(y_guides, (a.y + b.y) * 0.5)

	for obstacle in nearby_obstacles:
		_append_unique_scalar(x_guides, obstacle.position.x - obstacle_clearance)
		_append_unique_scalar(x_guides, obstacle.position.x + obstacle.size.x + obstacle_clearance)
		_append_unique_scalar(y_guides, obstacle.position.y - obstacle_clearance)
		_append_unique_scalar(y_guides, obstacle.position.y + obstacle.size.y + obstacle_clearance)

	for x in x_guides:
		_append_candidate(candidates, [a, Vector2(x, a.y), Vector2(x, b.y), b])
	for y in y_guides:
		_append_candidate(candidates, [a, Vector2(a.x, y), Vector2(b.x, y), b])

	var best_route: Array[Vector2] = []
	var best_score := INF

	for candidate_variant in candidates:
		var candidate: Array[Vector2] = candidate_variant
		if not _polyline_is_clear(candidate, ignored_buildings):
			continue

		var score := _candidate_score(candidate, from_n, to_n)
		if score < best_score:
			best_score = score
			best_route = candidate

	if not best_route.is_empty():
		return best_route

	var fallback_route := _build_grid_fallback_polyline(a, b, from_n, to_n, ignored_buildings)
	if not fallback_route.is_empty():
		return fallback_route

	if is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y):
		return [a, b]

	return _sanitize_polyline([a, _choose_corner(a, b), b])

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


func _get_path_line(path: Path2D) -> Line2D:
	if path == null or not is_instance_valid(path):
		return null

	var line := path.get_node_or_null("Line") as Line2D
	if line != null:
		return line

	for child in path.get_children():
		if child is Line2D:
			return child as Line2D

	return null


func _get_path_global_points(path: Path2D, line: Line2D) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if path == null or line == null:
		return points

	var source_points = path.get_meta("route_polyline_local") if path.has_meta("route_polyline_local") else line.points
	for local_point in source_points:
		points.append(path.to_global(local_point))

	return points


func _get_direction_marker_root(path: Path2D) -> Node2D:
	var marker_root := path.get_node_or_null("DirectionMarkers") as Node2D
	if marker_root != null:
		return marker_root

	marker_root = Node2D.new()
	marker_root.name = "DirectionMarkers"
	marker_root.z_index = 2
	path.add_child(marker_root)
	return marker_root


func _clear_direction_markers(path: Path2D) -> void:
	var marker_root := path.get_node_or_null("DirectionMarkers")
	if marker_root == null:
		return

	for child in marker_root.get_children():
		child.queue_free()


func _get_packed_polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func _sample_polyline_point_and_tangent(points: PackedVector2Array, distance_along: float) -> Dictionary:
	if points.size() < 2:
		return {}

	var total_length := _get_packed_polyline_length(points)
	var remaining = clamp(distance_along, 0.0, total_length)

	for i in range(1, points.size()):
		var start: Vector2 = points[i - 1]
		var end: Vector2 = points[i]
		var segment := end - start
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue

		if remaining <= segment_length or i == points.size() - 1:
			var t = clamp(remaining / segment_length, 0.0, 1.0)
			return {
				"position": start.lerp(end, t),
				"tangent": segment.normalized(),
			}

		remaining -= segment_length

	var fallback_tangent := (points[points.size() - 1] - points[max(points.size() - 2, 0)]).normalized()
	return {
		"position": points[points.size() - 1],
		"tangent": fallback_tangent,
	}


func _get_direction_marker_distances(total_length: float) -> Array[float]:
	var distances: Array[float] = []
	if total_length < direction_indicator_min_path_length:
		return distances

	var marker_count := clampi(int(floor(total_length / direction_indicator_spacing)) + 1, 1, direction_indicator_max_count)
	if marker_count <= 1:
		distances.append(total_length * 0.5)
		return distances

	var margin = min(direction_indicator_length, total_length * 0.2)
	var usable_length = max(total_length - margin * 2.0, 0.0)
	var step = usable_length / float(marker_count - 1)
	for i in range(marker_count):
		distances.append(margin + step * float(i))

	return distances


func _refresh_direction_markers_for_path(path: Path2D, line: Line2D) -> void:
	_clear_direction_markers(path)
	if path == null or line == null:
		return
	if line.points.size() < 2:
		return

	var total_length := _get_packed_polyline_length(line.points)
	if total_length < direction_indicator_min_path_length:
		return

	var marker_root := _get_direction_marker_root(path)
	var marker_color := line.default_color

	for distance_along in _get_direction_marker_distances(total_length):
		var sample := _sample_polyline_point_and_tangent(line.points, distance_along)
		if sample.is_empty():
			continue

		var tangent: Vector2 = sample.get("tangent", Vector2.RIGHT)
		if tangent.length() <= 0.001:
			continue

		var marker := Node2D.new()
		marker.position = sample.get("position", Vector2.ZERO)
		marker.rotation = tangent.angle()

		var polygon := Polygon2D.new()
		polygon.color = marker_color
		var half_length := direction_indicator_length * 0.5
		var half_width := direction_indicator_width * 0.5
		polygon.polygon = PackedVector2Array([
			Vector2(half_length, 0.0),
			Vector2(-half_length, half_width),
			Vector2(-half_length, -half_width),
		])

		marker.add_child(polygon)
		marker_root.add_child(marker)


func _get_rail_capacity_text(rail_version: int) -> String:
	match clampi(rail_version, RAIL_VERSION_V1, RAIL_VERSION_V3):
		RAIL_VERSION_V2:
			return "240"
		RAIL_VERSION_V3:
			return "480"
		_:
			return "120"


func _make_rail_capacity_badge_style(fill: Color, border: Color) -> StyleBoxFlat:
	var badge_style := Palette.make_panel_style(fill, border, _scaled_int(6), _scaled_int(1))
	badge_style.set_content_margin(SIDE_LEFT, _scaled(6))
	badge_style.set_content_margin(SIDE_RIGHT, _scaled(6))
	badge_style.set_content_margin(SIDE_TOP, _scaled(3))
	badge_style.set_content_margin(SIDE_BOTTOM, _scaled(3))
	return badge_style


func _apply_rail_capacity_badge_style(badge: PanelContainer, fill: Color, border: Color) -> void:
	if badge == null:
		return
	badge.add_theme_stylebox_override("panel", _make_rail_capacity_badge_style(fill, border))


func _get_rail_capacity_badge(path: Path2D) -> PanelContainer:
	var badge := path.get_node_or_null(RAIL_CAPACITY_BADGE_NAME) as PanelContainer
	if badge != null:
		_configure_rail_capacity_badge_hover(badge)
		return badge

	badge = PanelContainer.new()
	badge.name = RAIL_CAPACITY_BADGE_NAME
	badge.z_index = 3
	_configure_rail_capacity_badge_hover(badge)
	var badge_size := _scaled_vec2(RAIL_CAPACITY_BADGE_SIZE)
	badge.custom_minimum_size = badge_size
	badge.size = badge_size

	_apply_rail_capacity_badge_style(badge, RAIL_CAPACITY_BADGE_FILL, RAIL_CAPACITY_BADGE_BORDER)

	var label := Label.new()
	label.name = RAIL_CAPACITY_TEXT_NAME
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(max(badge_size.x - _scaled(12.0), 1.0), max(badge_size.y - _scaled(6.0), 1.0))
	label.add_theme_color_override("font_color", RAIL_CAPACITY_BADGE_TEXT)
	label.add_theme_color_override("font_outline_color", RAIL_CAPACITY_BADGE_TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", _scaled_int(2))
	label.add_theme_font_size_override("font_size", UiScale.font_size(RAIL_CAPACITY_BADGE_FONT_SIZE, _ui_scale))
	badge.add_child(label)

	path.add_child(badge)
	return badge


func _configure_rail_capacity_badge_hover(badge: PanelContainer) -> void:
	if badge == null:
		return
	badge.mouse_filter = RAIL_CAPACITY_BADGE_MOUSE_FILTER


func _refresh_rail_capacity_badge_for_path(path: Path2D, line: Line2D) -> void:
	if path == null or line == null:
		return

	if not _rail_flow_rate_visible:
		_set_rail_capacity_badge_visible(path, false)
		return

	var badge := _get_rail_capacity_badge(path)
	if line.points.size() < 2:
		badge.visible = false
		return

	var total_length := _get_packed_polyline_length(line.points)
	if total_length <= 0.001:
		badge.visible = false
		return

	var sample := _sample_polyline_point_and_tangent(line.points, total_length * 0.5)
	if sample.is_empty():
		badge.visible = false
		return

	var badge_state := _get_rail_capacity_badge_state(path)
	_apply_rail_capacity_badge_style(
		badge,
		badge_state.get("fill", RAIL_CAPACITY_BADGE_FILL),
		badge_state.get("border", RAIL_CAPACITY_BADGE_BORDER)
	)
	badge.tooltip_text = str(badge_state.get("tooltip", ""))

	var label := badge.get_node_or_null(RAIL_CAPACITY_TEXT_NAME) as Label
	if label != null:
		label.text = str(badge_state.get("text", _get_rail_capacity_text(get_path_rail_version(path))))
		label.tooltip_text = badge.tooltip_text
		label.add_theme_color_override("font_color", badge_state.get("font_color", RAIL_CAPACITY_BADGE_TEXT))
		label.add_theme_color_override("font_outline_color", badge_state.get("font_outline_color", RAIL_CAPACITY_BADGE_TEXT_OUTLINE))
		label.add_theme_constant_override("outline_size", _scaled_int(int(badge_state.get("outline_size", 2))))
		label.add_theme_font_size_override("font_size", UiScale.font_size(RAIL_CAPACITY_BADGE_FONT_SIZE, _ui_scale))
		var label_size := Vector2(max(_scaled(RAIL_CAPACITY_BADGE_SIZE.x - 12.0), 1.0), max(_scaled(RAIL_CAPACITY_BADGE_SIZE.y - 6.0), 1.0))
		label.custom_minimum_size = label_size
		label.size = label_size

	var badge_size := _scaled_vec2(RAIL_CAPACITY_BADGE_SIZE)
	badge.custom_minimum_size = badge_size
	badge.size = badge_size
	badge.position = Vector2(sample.get("position", Vector2.ZERO)) - (badge_size * 0.5)
	badge.visible = true


func _get_rail_capacity_badge_state(path: Path2D) -> Dictionary:
	var capacity_text := _get_rail_capacity_text(get_path_rail_version(path))
	if not _flow_simulation_enabled:
		return {
			"text": capacity_text,
			"fill": RAIL_CAPACITY_BADGE_FILL,
			"border": RAIL_CAPACITY_BADGE_BORDER,
			"tooltip": _append_pathing_supply_tooltip("Rail capacity: %s upm" % capacity_text, path),
			"font_color": RAIL_CAPACITY_BADGE_TEXT,
			"font_outline_color": RAIL_CAPACITY_BADGE_TEXT_OUTLINE,
			"outline_size": 2,
		}

	var edge_result := _get_flow_edge_result_for_path(path)
	if edge_result.is_empty():
		return {
			"text": capacity_text,
			"fill": RAIL_CAPACITY_BADGE_FILL,
			"border": RAIL_CAPACITY_BADGE_BORDER,
			"tooltip": "Flow simulation has no result for this rail.",
			"font_color": RAIL_CAPACITY_BADGE_TEXT,
			"font_outline_color": RAIL_CAPACITY_BADGE_TEXT_OUTLINE,
			"outline_size": 2,
		}

	var layer_state := _get_flow_layer_badge_state(edge_result)
	var flow_color: Color = layer_state.get("color", FLOW_STATE_GOOD)
	return {
		"text": str(layer_state.get("text", "")),
		"fill": Palette.with_alpha(flow_color, FLOW_BADGE_FILL_ALPHA),
		"border": flow_color,
		"tooltip": _append_pathing_supply_tooltip(str(layer_state.get("tooltip", "")), path),
		"font_color": FLOW_BADGE_TEXT,
		"font_outline_color": FLOW_BADGE_TEXT_OUTLINE,
		"outline_size": FLOW_BADGE_TEXT_OUTLINE_SIZE,
	}


# Produces the badge text/color/tooltip for the active flow layer. Each layer reads
# a different metric from the simulator's per-edge result.
func _get_flow_layer_badge_state(edge_result: Dictionary) -> Dictionary:
	match _flow_layer_mode:
		FLOW_LAYER_USED:
			return _flow_layer_metric_state("Used flow", float(edge_result.get("used_upm", 0.0)), _flow_saturation_color(edge_result), edge_result)
		FLOW_LAYER_REQUESTED:
			return _flow_layer_metric_state("Requested flow", float(edge_result.get("requested_upm", 0.0)), _flow_requested_color(edge_result), edge_result)
		FLOW_LAYER_BLOCKED:
			var blocked := float(edge_result.get("blocked_upm", 0.0))
			var blocked_color := FLOW_STATE_BLOCKED if blocked > FLOW_EPSILON else FLOW_STATE_GOOD
			return _flow_layer_metric_state("Blocked flow", blocked, blocked_color, edge_result)
		FLOW_LAYER_AVAILABLE:
			return _flow_layer_available_state(edge_result)
		FLOW_LAYER_SATURATION:
			return _flow_layer_saturation_state(edge_result)
		_:
			return _flow_layer_delta_state(edge_result)


func _flow_layer_delta_state(edge_result: Dictionary) -> Dictionary:
	var delta := _get_flow_capacity_delta(edge_result)
	return {
		"text": _format_flow_delta(delta),
		"color": _get_flow_badge_color(delta),
		"tooltip": _get_flow_badge_tooltip(edge_result, delta),
	}


func _flow_layer_metric_state(header: String, value: float, color: Color, edge_result: Dictionary) -> Dictionary:
	return {
		"text": "%d" % int(round(value)),
		"color": color,
		"tooltip": _flow_layer_tooltip(header, edge_result),
	}


func _flow_layer_available_state(edge_result: Dictionary) -> Dictionary:
	if bool(edge_result.get("unlimited", false)):
		return {
			"text": "--",
			"color": FLOW_STATE_GOOD,
			"tooltip": _flow_layer_tooltip("Spare capacity", edge_result),
		}
	var available := float(edge_result.get("available_upm", 0.0))
	var color := FLOW_STATE_GOOD if available > FLOW_EPSILON else FLOW_STATE_BLOCKED
	return _flow_layer_metric_state("Spare capacity", available, color, edge_result)


func _flow_layer_saturation_state(edge_result: Dictionary) -> Dictionary:
	if bool(edge_result.get("unlimited", false)):
		return {
			"text": "--",
			"color": FLOW_STATE_GOOD,
			"tooltip": _flow_layer_tooltip("Saturation", edge_result),
		}
	var saturation := _flow_saturation(edge_result)
	return {
		"text": "%d%%" % int(round(saturation * 100.0)),
		"color": _flow_saturation_color(edge_result),
		"tooltip": _flow_layer_tooltip("Saturation", edge_result),
	}


func _flow_saturation(edge_result: Dictionary) -> float:
	if bool(edge_result.get("unlimited", false)):
		return 0.0
	var capacity := float(edge_result.get("capacity_upm", 0.0))
	if capacity <= FLOW_EPSILON:
		return 0.0
	return clampf(float(edge_result.get("used_upm", 0.0)) / capacity, 0.0, 1.0)


func _flow_saturation_color(edge_result: Dictionary) -> Color:
	if bool(edge_result.get("unlimited", false)):
		return FLOW_STATE_GOOD
	var saturation := _flow_saturation(edge_result)
	if saturation >= 1.0 - FLOW_EPSILON:
		return FLOW_STATE_BLOCKED
	if saturation >= FLOW_SATURATION_WARN_THRESHOLD:
		return FLOW_STATE_WARN
	return FLOW_STATE_GOOD


func _flow_requested_color(edge_result: Dictionary) -> Color:
	if bool(edge_result.get("unlimited", false)):
		return FLOW_STATE_GOOD
	var capacity := float(edge_result.get("capacity_upm", 0.0))
	var requested := float(edge_result.get("requested_upm", 0.0))
	if capacity <= FLOW_EPSILON:
		return FLOW_STATE_GOOD
	if requested > capacity + FLOW_EPSILON:
		return FLOW_STATE_BLOCKED
	if requested >= capacity * FLOW_SATURATION_WARN_THRESHOLD:
		return FLOW_STATE_WARN
	return FLOW_STATE_GOOD


func _flow_layer_tooltip(header: String, edge_result: Dictionary) -> String:
	var unlimited := bool(edge_result.get("unlimited", false))
	var capacity_text := "unlimited" if unlimited else "%.0f" % float(edge_result.get("capacity_upm", 0.0))
	var spare_text := "unlimited" if unlimited else "%.0f" % float(edge_result.get("available_upm", 0.0))
	var saturation_text := "n/a" if unlimited else "%d%%" % int(round(_flow_saturation(edge_result) * 100.0))
	return "%s\nUsed %.0f / %s upm\nRequested %.0f upm\nBlocked %.0f upm\nSpare %s upm\nSaturation %s" % [
		header,
		float(edge_result.get("used_upm", 0.0)),
		capacity_text,
		float(edge_result.get("requested_upm", 0.0)),
		float(edge_result.get("blocked_upm", 0.0)),
		spare_text,
		saturation_text,
	]


func _get_flow_edge_result_for_path(path: Path2D) -> Dictionary:
	var edge_id := _get_flow_edge_id_for_path(path)
	var edge_result = _flow_simulation_edge_results.get(edge_id, {})
	return edge_result if edge_result is Dictionary else {}


func _get_flow_edge_id_for_path(path: Path2D) -> String:
	if path == null:
		return ""
	return "rail_%d" % path.get_instance_id()


func _get_flow_capacity_delta(edge_result: Dictionary) -> float:
	if bool(edge_result.get("unlimited", false)):
		return 0.0
	return float(edge_result.get("requested_upm", 0.0)) - float(edge_result.get("capacity_upm", 0.0))


func _get_flow_badge_color(delta: float) -> Color:
	var rounded := _rounded_flow_delta(delta)
	if rounded > 0:
		return Palette.BUILDING_OUTLINE_CRAFTING
	if rounded < 0:
		return Palette.BUILDING_OUTLINE_PROCESSING
	return Palette.BUILDING_OUTLINE_EXTRACTION


func _format_flow_delta(delta: float) -> String:
	var rounded := _rounded_flow_delta(delta)
	if rounded == 0:
		return "0"
	if rounded > 0:
		return "+%d" % rounded
	return str(rounded)


func _rounded_flow_delta(delta: float) -> int:
	return int(round(delta))


func _get_flow_badge_tooltip(edge_result: Dictionary, delta: float) -> String:
	var rounded := _rounded_flow_delta(delta)
	var state_line := "Fully saturated"
	if rounded > 0:
		state_line = "Over capacity by %d upm" % rounded
	elif rounded < 0:
		state_line = "Spare capacity %d upm" % abs(rounded)

	return "%s\nRequested %.0f / %.0f upm\nUsed %.0f upm\nBlocked %.0f upm" % [
		state_line,
		float(edge_result.get("requested_upm", 0.0)),
		float(edge_result.get("capacity_upm", 0.0)),
		float(edge_result.get("used_upm", 0.0)),
		float(edge_result.get("blocked_upm", 0.0)),
	]


func _append_pathing_supply_tooltip(base_tooltip: String, path: Path2D) -> String:
	var supply_tooltip := _get_pathing_supply_tooltip(path)
	if supply_tooltip == "":
		return base_tooltip
	return "%s\n%s" % [base_tooltip, supply_tooltip]


func _get_pathing_supply_tooltip(path: Path2D) -> String:
	if path == null:
		return ""
	var edge_id := _get_flow_edge_id_for_path(path)
	var supply = _pathing_intelligence_edge_supply.get(edge_id, {})
	if not (supply is Dictionary):
		return ""

	var supply_data: Dictionary = supply
	var resources: Array = supply_data.get("resources", [])
	if resources.is_empty():
		return "Available resources: none detected"

	var facts: Dictionary = supply_data.get("resource_facts", {})
	var lines: Array[String] = []
	lines.append("Available: %s" % _join_supply_resource_names(resources, facts))
	if bool(supply_data.get("is_shared", false)):
		lines.append("Shared rail: multiple resources available")

	var unused = supply_data.get("unused_resources", [])
	if unused is Array and not (unused as Array).is_empty():
		if bool(supply_data.get("is_dead_end", false)):
			lines.append("Dead-end rail: nothing downstream uses %s" % _join_supply_resource_names(unused, facts))
		else:
			lines.append("No downstream consumer: %s" % _join_supply_resource_names(unused, facts))

	var count = mini(resources.size(), PATHING_SUPPLY_TOOLTIP_LIMIT)
	for i in range(count):
		var resource = resources[i]
		var fact: Dictionary = facts.get(resource, {})
		var origins := _join_supply_origin_labels(fact.get("origins", []))
		if origins == "":
			continue
		lines.append("%s from %s" % [
			String(fact.get("display_name", _format_resource_name(str(resource)))),
			origins
		])

	if resources.size() > PATHING_SUPPLY_TOOLTIP_LIMIT:
		lines.append("+%d more resource(s)" % (resources.size() - PATHING_SUPPLY_TOOLTIP_LIMIT))

	var impact = supply_data.get("downstream_impact", [])
	if impact is Array and not (impact as Array).is_empty():
		var break_text := _join_impact_targets(impact, "break")
		if break_text != "":
			lines.append("Removing this rail would starve: %s" % break_text)
		var degrade_text := _join_impact_targets(impact, "degrade")
		if degrade_text != "":
			lines.append("Removing this rail would under-supply: %s" % degrade_text)

	return "\n".join(lines)


func _join_impact_targets(impact: Array, severity: String) -> String:
	var targets: Array[String] = []
	var overflow := 0
	for item_variant in impact:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant
		if String(item.get("severity", "")) != severity:
			continue
		if targets.size() >= PATHING_SUPPLY_TOOLTIP_LIMIT:
			overflow += 1
			continue
		targets.append("%s (%s)" % [
			String(item.get("label", "")),
			String(item.get("display_name", ""))
		])
	if overflow > 0:
		targets.append("+%d more" % overflow)
	return ", ".join(targets)


func _join_supply_resource_names(resources: Array, facts: Dictionary) -> String:
	var names: Array[String] = []
	for resource in resources:
		var fact: Dictionary = facts.get(resource, {})
		names.append(String(fact.get("display_name", _format_resource_name(str(resource)))))
	return ", ".join(names)


func _join_supply_origin_labels(origins_value) -> String:
	var origins: Array = origins_value if origins_value is Array else []
	var labels: Array[String] = []
	for origin_variant in origins:
		if not (origin_variant is Dictionary):
			continue
		var origin: Dictionary = origin_variant
		var label := String(origin.get("label", ""))
		if label == "" or labels.has(label):
			continue
		labels.append(label)
	return ", ".join(labels)


func _format_resource_name(value: String) -> String:
	return value.strip_edges().replace("_", " ").replace("-", " ").capitalize()


func _set_rail_capacity_badge_visible(path: Path2D, visible: bool) -> void:
	if path == null:
		return
	var badge := path.get_node_or_null(RAIL_CAPACITY_BADGE_NAME) as Control
	if badge != null:
		badge.visible = visible


func _refresh_all_rail_capacity_badges() -> void:
	for child in get_children():
		if not (child is Path2D):
			continue

		var path := child as Path2D
		if path == _preview_container:
			continue
		if not path.has_meta("from_building") or not path.has_meta("to_building"):
			continue

		var line := _get_path_line(path)
		if line == null:
			_set_rail_capacity_badge_visible(path, false)
			continue

		_refresh_rail_capacity_badge_for_path(path, line)

	_refresh_flow_beads()
	_refresh_storage_badges()


func _get_flow_bead_layer() -> Node2D:
	if _flow_bead_layer != null and is_instance_valid(_flow_bead_layer):
		return _flow_bead_layer
	_flow_bead_layer = FlowBeadLayerScript.new()
	_flow_bead_layer.name = FLOW_BEAD_LAYER_NAME
	_flow_bead_layer.z_index = FLOW_BEAD_LAYER_Z
	add_child(_flow_bead_layer)
	_flow_bead_layer.call("set_scale_factor", _ui_scale)
	return _flow_bead_layer


func _refresh_flow_beads() -> void:
	var layer := _get_flow_bead_layer()
	if layer == null:
		return

	if not _flow_simulation_enabled:
		layer.call("set_rails", [])
		layer.call("set_loop_rails", [])
		layer.call("set_enabled", false)
		return

	var loop_pairs := _collect_loop_edge_pairs()
	var rails: Array = []
	var loop_rails: Array = []
	for child in get_children():
		if not (child is Path2D):
			continue
		var path := child as Path2D
		if path == _preview_container:
			continue
		if not path.has_meta("from_building") or not path.has_meta("to_building"):
			continue

		var line := _get_path_line(path)
		if line == null:
			continue

		var global_points := _get_path_global_points(path, line)
		if global_points.size() < 2:
			continue
		var local_points := PackedVector2Array()
		for global_point in global_points:
			local_points.append(to_local(global_point))

		var edge_result := _get_flow_edge_result_for_path(path)
		if not edge_result.is_empty():
			var intensity := _flow_bead_intensity(edge_result)
			if intensity > 0.0:
				rails.append({
					"points": local_points,
					"intensity": intensity,
				})

		if not loop_pairs.is_empty():
			var pair_key := "%s|%s" % [
				_node_id_for_path_endpoint(path, "from_building"),
				_node_id_for_path_endpoint(path, "to_building"),
			]
			if loop_pairs.has(pair_key):
				loop_rails.append({"points": local_points})

	layer.call("set_rails", rails)
	layer.call("set_loop_rails", loop_rails)
	layer.call("set_enabled", true)


# Builds the set of directed "fromNodeId|toNodeId" pairs that participate in a
# simulator-detected flow loop, so the overlay can highlight the looping rails.
func _collect_loop_edge_pairs() -> Dictionary:
	var pairs := {}
	for warning_variant in _flow_simulation_warnings:
		if not (warning_variant is Dictionary):
			continue
		if String(warning_variant.get("type", "")) != "loop_detected":
			continue
		var nodes = warning_variant.get("nodes", [])
		if not (nodes is Array):
			continue
		for i in range(1, nodes.size()):
			pairs["%s|%s" % [String(nodes[i - 1]), String(nodes[i])]] = true
	return pairs


func _node_id_for_path_endpoint(path: Path2D, meta_key: String) -> String:
	if not path.has_meta(meta_key):
		return ""
	var building = path.get_meta(meta_key)
	if building is Node and is_instance_valid(building):
		return "%s%d" % [STORAGE_BUILDING_ID_PREFIX, (building as Node).get_instance_id()]
	return ""


func _flow_bead_intensity(edge_result: Dictionary) -> float:
	var used := float(edge_result.get("used_upm", 0.0))
	if used <= FLOW_EPSILON:
		return 0.0
	if bool(edge_result.get("unlimited", false)):
		return clampf(used / FLOW_BEAD_REFERENCE_UPM, FLOW_BEAD_MIN_INTENSITY, 1.0)
	return clampf(_flow_saturation(edge_result), FLOW_BEAD_MIN_INTENSITY, 1.0)


# Attaches a stored-inventory badge to each storage building while flow simulation is
# active, surfacing the simulator's storage-as-buffer state (total stored + fill/drain).
func _refresh_storage_badges() -> void:
	var previous_ids: Array = _storage_badge_building_ids.duplicate()
	_storage_badge_building_ids = []

	if _flow_simulation_enabled:
		for node_id in _flow_simulation_node_results.keys():
			var node_result = _flow_simulation_node_results[node_id]
			if not (node_result is Dictionary):
				continue
			if String(node_result.get("kind", "")) != STORAGE_NODE_KIND:
				continue
			var building := _building_from_node_id(String(node_id))
			if building == null:
				continue
			_apply_storage_badge(building, node_result)
			_storage_badge_building_ids.append(building.get_instance_id())

	for building_id in previous_ids:
		if _storage_badge_building_ids.has(building_id):
			continue
		var obj = instance_from_id(building_id)
		if obj is Node2D and is_instance_valid(obj):
			_set_storage_badge_visible(obj as Node2D, false)


func _building_from_node_id(node_id: String) -> Node2D:
	if not node_id.begins_with(STORAGE_BUILDING_ID_PREFIX):
		return null
	var id_text := node_id.trim_prefix(STORAGE_BUILDING_ID_PREFIX)
	if not id_text.is_valid_int():
		return null
	var obj = instance_from_id(int(id_text))
	if obj is Node2D and is_instance_valid(obj):
		return obj as Node2D
	return null


func _apply_storage_badge(building: Node2D, node_result: Dictionary) -> void:
	var badge := _get_storage_badge(building)
	if badge == null:
		return

	var inventory: Dictionary = node_result.get("storage_inventory", {})
	var total_stored := 0.0
	for resource in inventory.keys():
		total_stored += maxf(float(inventory[resource]), 0.0)

	var incoming := float(node_result.get("total_incoming_upm", 0.0))
	var outgoing := float(node_result.get("total_outgoing_upm", 0.0))
	var net := incoming - outgoing

	var color := RAIL_CAPACITY_BADGE_BORDER
	if net > FLOW_EPSILON:
		color = FLOW_STATE_GOOD
	elif net < -FLOW_EPSILON:
		color = FLOW_STATE_WARN

	_apply_rail_capacity_badge_style(badge, Palette.with_alpha(color, FLOW_BADGE_FILL_ALPHA), color)
	badge.tooltip_text = _build_storage_badge_tooltip(inventory, total_stored, net)

	var label := badge.get_node_or_null(STORAGE_BADGE_TEXT_NAME) as Label
	if label != null:
		label.text = _format_storage_quantity(total_stored)
		label.tooltip_text = badge.tooltip_text
		label.add_theme_color_override("font_color", FLOW_BADGE_TEXT)
		label.add_theme_color_override("font_outline_color", FLOW_BADGE_TEXT_OUTLINE)
		label.add_theme_constant_override("outline_size", _scaled_int(FLOW_BADGE_TEXT_OUTLINE_SIZE))
		label.add_theme_font_size_override("font_size", UiScale.font_size(RAIL_CAPACITY_BADGE_FONT_SIZE, _ui_scale))

	var badge_size := _scaled_vec2(STORAGE_BADGE_SIZE)
	badge.custom_minimum_size = badge_size
	badge.size = badge_size
	badge.position = Vector2(-badge_size.x * 0.5, _scaled(STORAGE_BADGE_OFFSET_Y))
	badge.visible = true


func _get_storage_badge(building: Node2D) -> PanelContainer:
	if building == null:
		return null
	var badge := building.get_node_or_null(STORAGE_BADGE_NAME) as PanelContainer
	if badge != null:
		return badge

	badge = PanelContainer.new()
	badge.name = STORAGE_BADGE_NAME
	badge.z_index = 4
	badge.mouse_filter = RAIL_CAPACITY_BADGE_MOUSE_FILTER

	var label := Label.new()
	label.name = STORAGE_BADGE_TEXT_NAME
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", FLOW_BADGE_TEXT)
	label.add_theme_font_size_override("font_size", UiScale.font_size(RAIL_CAPACITY_BADGE_FONT_SIZE, _ui_scale))
	badge.add_child(label)

	building.add_child(badge)
	return badge


func _set_storage_badge_visible(building: Node2D, visible_state: bool) -> void:
	if building == null or not is_instance_valid(building):
		return
	var badge := building.get_node_or_null(STORAGE_BADGE_NAME) as PanelContainer
	if badge != null:
		badge.visible = visible_state


func _format_storage_quantity(value: float) -> String:
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%d" % int(round(value))


func _build_storage_badge_tooltip(inventory: Dictionary, total_stored: float, net: float) -> String:
	var lines: Array[String] = []
	var state := "Stable"
	if net > FLOW_EPSILON:
		state = "Filling +%.0f upm" % net
	elif net < -FLOW_EPSILON:
		state = "Draining %.0f upm" % net
	lines.append("Storage buffer: %s" % state)
	lines.append("Total stored: %.0f" % total_stored)

	if inventory.is_empty():
		lines.append("Empty")
	else:
		for resource in inventory.keys():
			lines.append("  %s: %.0f" % [_format_resource_display(String(resource)), float(inventory[resource])])
	return "\n".join(lines)


func _format_resource_display(resource: String) -> String:
	return resource.strip_edges().replace("_", " ").replace("-", " ").capitalize()


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)


func _scaled_vec2(value: Vector2) -> Vector2:
	return UiScale.scaled_vec2(value, _ui_scale)


func _get_overlap_segments_for_path(path: Path2D) -> Array:
	var line := _get_path_line(path)
	if line == null:
		return []

	var points := _get_path_global_points(path, line)
	var segments: Array = []
	for i in range(1, points.size()):
		var start: Vector2 = points[i - 1]
		var end: Vector2 = points[i]
		if start.distance_to(end) < overlap_min_length:
			continue

		if is_equal_approx(start.x, end.x):
			segments.append({
				"axis": "v",
				"lane": start.x,
				"start": min(start.y, end.y),
				"end": max(start.y, end.y),
			})
		elif is_equal_approx(start.y, end.y):
			segments.append({
				"axis": "h",
				"lane": start.y,
				"start": min(start.x, end.x),
				"end": max(start.x, end.x),
			})

	return segments


func _segments_overlap(segment_a: Dictionary, segment_b: Dictionary) -> bool:
	if segment_a.get("axis", "") != segment_b.get("axis", ""):
		return false
	if abs(float(segment_a.get("lane", 0.0)) - float(segment_b.get("lane", 0.0))) > overlap_lane_tolerance:
		return false

	var overlap_start = max(float(segment_a.get("start", 0.0)), float(segment_b.get("start", 0.0)))
	var overlap_end = min(float(segment_a.get("end", 0.0)), float(segment_b.get("end", 0.0)))
	return overlap_end + overlap_lane_tolerance >= overlap_start


func _segments_intersect(segment_a: Dictionary, segment_b: Dictionary) -> bool:
	var axis_a := String(segment_a.get("axis", ""))
	var axis_b := String(segment_b.get("axis", ""))
	if axis_a == axis_b:
		return _segments_overlap(segment_a, segment_b)

	var horizontal := segment_a if axis_a == "h" else segment_b
	var vertical := segment_a if axis_a == "v" else segment_b
	if String(horizontal.get("axis", "")) != "h" or String(vertical.get("axis", "")) != "v":
		return false

	var point_x := float(vertical.get("lane", 0.0))
	var point_y := float(horizontal.get("lane", 0.0))
	return (
		point_x >= float(horizontal.get("start", 0.0)) - overlap_lane_tolerance
		and point_x <= float(horizontal.get("end", 0.0)) + overlap_lane_tolerance
		and point_y >= float(vertical.get("start", 0.0)) - overlap_lane_tolerance
		and point_y <= float(vertical.get("end", 0.0)) + overlap_lane_tolerance
	)


func _path_segments_overlap(segments_a: Array, segments_b: Array) -> bool:
	for segment_a_variant in segments_a:
		var segment_a: Dictionary = segment_a_variant
		for segment_b_variant in segments_b:
			var segment_b: Dictionary = segment_b_variant
			if _segments_intersect(segment_a, segment_b):
				return true
	return false


func _get_overlap_overlay(path: Path2D) -> Node2D:
	var overlay := path.get_node_or_null("OverlapOverlay") as Node2D
	if overlay != null:
		return overlay

	overlay = Node2D.new()
	overlay.name = "OverlapOverlay"
	overlay.z_index = 1
	path.add_child(overlay)
	return overlay


func _clear_overlap_overlay(path: Path2D) -> void:
	var overlay := path.get_node_or_null("OverlapOverlay")
	if overlay == null:
		return

	for child in overlay.get_children():
		child.queue_free()


func _segment_overlap_slice(segment_a: Dictionary, segment_b: Dictionary) -> Dictionary:
	if not _segments_overlap(segment_a, segment_b):
		return {}

	return {
		"axis": segment_a.get("axis", ""),
		"lane": segment_a.get("lane", 0.0),
		"start": max(float(segment_a.get("start", 0.0)), float(segment_b.get("start", 0.0))),
		"end": min(float(segment_a.get("end", 0.0)), float(segment_b.get("end", 0.0))),
	}


func _slice_to_local_points(path: Path2D, overlap_slice: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var axis := String(overlap_slice.get("axis", ""))
	var lane := float(overlap_slice.get("lane", 0.0))
	var segment_start := float(overlap_slice.get("start", 0.0))
	var segment_end := float(overlap_slice.get("end", 0.0))
	if segment_end - segment_start < overlap_min_length:
		return points

	if axis == "h":
		points.append(path.to_local(Vector2(segment_start, lane)))
		points.append(path.to_local(Vector2(segment_end, lane)))
	elif axis == "v":
		points.append(path.to_local(Vector2(lane, segment_start)))
		points.append(path.to_local(Vector2(lane, segment_end)))

	return points


func _draw_overlap_overlay(path: Path2D, overlap_slices: Array, overlap_depth: int) -> void:
	_clear_overlap_overlay(path)
	if overlap_slices.is_empty() or overlap_depth <= 0:
		return

	var overlay := _get_overlap_overlay(path)
	var overlay_color := _get_overlap_tinted_path_color(path, overlap_depth + 1)
	var overlay_width = max(line_width - overlap_overlay_width_reduction, line_width * 0.5)

	for overlap_slice_variant in overlap_slices:
		var overlap_slice: Dictionary = overlap_slice_variant
		var overlay_points := _slice_to_local_points(path, overlap_slice)
		if overlay_points.size() < 2:
			continue

		var overlap_line := Line2D.new()
		overlap_line.width = overlay_width
		overlap_line.antialiased = true
		overlap_line.default_color = overlay_color
		overlap_line.points = overlay_points
		overlay.add_child(overlap_line)


func _refresh_path_overlap_shading() -> void:
	var path_entries: Array = []
	for child in get_children():
		if not (child is Path2D):
			continue

		var path := child as Path2D
		if path == _preview_container:
			continue
		if not path.has_meta("from_building") or not path.has_meta("to_building"):
			continue

		var line := _get_path_line(path)
		if line == null:
			continue

		path_entries.append({
			"path": path,
			"line": line,
			"segments": _get_overlap_segments_for_path(path),
		})

	for i in range(path_entries.size()):
		var entry: Dictionary = path_entries[i]
		var overlap_depth := 0
		var segments: Array = entry.get("segments", [])
		for j in range(i):
			var prior_entry: Dictionary = path_entries[j]
			var prior_segments: Array = prior_entry.get("segments", [])
			if _path_segments_overlap(segments, prior_segments):
				overlap_depth += 1

		var path: Path2D = entry.get("path")
		var line: Line2D = entry.get("line")
		line.default_color = _get_overlap_tinted_path_color(path, overlap_depth)
		_clear_overlap_overlay(path)
		_refresh_direction_markers_for_path(path, line)
		_refresh_rail_capacity_badge_for_path(path, line)


func _refresh_path_markers(paths: Array[Path2D]) -> void:
	for path in paths:
		if path == null or not is_instance_valid(path):
			continue

		var line := _get_path_line(path)
		if line == null:
			continue
		_refresh_direction_markers_for_path(path, line)
		_refresh_rail_capacity_badge_for_path(path, line)


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var segment_length_sq := segment.length_squared()
	if segment_length_sq <= 0.001:
		return point.distance_to(start)

	var t = clamp((point - start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest = start + segment * t
	return point.distance_to(closest)


func _is_point_near_polyline(point: Vector2, points: PackedVector2Array, tolerance: float) -> bool:
	if points.size() < 2:
		return false

	for i in range(1, points.size()):
		if _distance_to_segment(point, points[i - 1], points[i]) <= tolerance:
			return true
	return false


func _get_baked_path_under_global_point(global_point: Vector2) -> Path2D:
	var children := get_children()
	for i in range(children.size() - 1, -1, -1):
		var child = children[i]
		if not (child is Path2D):
			continue

		var path := child as Path2D
		if path == _preview_container:
			continue
		if not path.has_meta("from_building") or not path.has_meta("to_building"):
			continue

		var line := _get_path_line(path)
		if line == null or line.points.size() < 2:
			continue

		var local_mouse := path.to_local(global_point)
		var hit_tolerance = max(line.width * 0.75, 8.0)
		if _is_point_near_polyline(local_mouse, line.points, hit_tolerance):
			return path

	return null


func try_remove_path_under_mouse() -> bool:
	if _rail_visibility_mode == RAIL_VISIBILITY_NONE:
		return false

	var target_path := _get_baked_path_under_global_point(get_global_mouse_position())
	if target_path == null:
		return false

	var history_before := _capture_history_state()
	_detach_and_queue_free_path(target_path)
	_refresh_path_overlap_shading()
	rail_graph_changed.emit()
	_commit_history_action("Rail deleted", history_before)
	return true


func _build_route_points_local(container: Node2D, from_b: Node2D, from_port: NodePath, from_pos_g: Vector2, to_b: Node2D, to_port: NodePath, to_pos_g: Vector2) -> Array[Vector2]:
	return _build_route_points_local_with_normals(
		container,
		from_pos_g,
		_get_port_normal(from_b, from_port),
		to_pos_g,
		_get_port_normal(to_b, to_port),
		[from_b, to_b],
		from_b,
		to_b
	)


func _route_points_local(container: Node2D, from_b: Node2D, from_port: NodePath, from_pos_g: Vector2, to_b: Node2D, to_port: NodePath, to_pos_g: Vector2) -> PackedVector2Array:
	return _round_polyline(_build_route_points_local(container, from_b, from_port, from_pos_g, to_b, to_port, to_pos_g), corner_radius, arc_segments)


func _build_route_points_local_with_normals(container: Node2D, from_pos_g: Vector2, from_n: Vector2, to_pos_g: Vector2, to_n: Vector2, ignored_buildings: Array = [], from_building: Node2D = null, to_building: Node2D = null) -> Array[Vector2]:
	# Build a "rational" Manhattan path:
	# start -> start_stub -> orthogonal route -> end_stub -> end

	# Global stub endpoints
	var a := from_pos_g
	var b := to_pos_g
	var a2 := _get_stub_endpoint(from_building, from_pos_g, from_n)
	var b2 := _get_stub_endpoint(to_building, to_pos_g, to_n)
	var mid_route_ignored_buildings: Array = []
	for ignored_building in ignored_buildings:
		if ignored_building == null:
			continue
		if ignored_building == from_building or ignored_building == to_building:
			continue
		if mid_route_ignored_buildings.has(ignored_building):
			continue
		mid_route_ignored_buildings.append(ignored_building)

	# Orthogonal between stubs
	var mid_poly := _build_manhattan_polyline(a2, b2, from_n, to_n, mid_route_ignored_buildings) # Array[Vector2] (global)

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

	# Pre-compaction route: the mid-route treats the endpoint buildings as
	# obstacles, so this version routes AROUND them. Kept as a safe fallback in
	# case a compaction pass shortcuts straight through a footprint.
	var base_poly_g: Array[Vector2] = []
	for point in poly_g:
		base_poly_g.append(point)

	poly_g = _simplify_opposite_vertical_port_link(a, a2, b, poly_g, ignored_buildings, from_n, to_n)
	poly_g = _simplify_up_origin_departure(poly_g, mid_route_ignored_buildings, from_n, from_building)
	poly_g = _simplify_up_origin_destination_arrival(poly_g, mid_route_ignored_buildings, from_n, to_n, to_building)
	poly_g = _simplify_local_wiggles(poly_g, mid_route_ignored_buildings)
	poly_g = _simplify_compact_full_route(poly_g, mid_route_ignored_buildings, from_n, to_n)
	poly_g = _sanitize_polyline(poly_g)

	# No rail may cross an endpoint building's body. Vertical-normal compaction
	# passes can shortcut straight through a footprint; if that happened, fall
	# back to the pre-compaction route that routed around it. This is a no-op for
	# the clean routes (they already clear the bodies), so it only reshapes the
	# rare pass-through cases.
	var endpoint_bodies := [
		{"building": from_building, "port": a, "normal": from_n},
		{"building": to_building, "port": b, "normal": to_n},
	]
	if _route_enters_building_body(poly_g, endpoint_bodies):
		poly_g = _sanitize_polyline(base_poly_g)

	# Convert to local space for the container and round corners in local space
	var poly_l: Array[Vector2] = []
	for point in poly_g:
		poly_l.append(container.to_local(point))
	poly_l = _sanitize_polyline(poly_l)

	return poly_l


func _route_points_local_with_normals(container: Node2D, from_pos_g: Vector2, from_n: Vector2, to_pos_g: Vector2, to_n: Vector2, ignored_buildings: Array = [], from_building: Node2D = null, to_building: Node2D = null) -> PackedVector2Array:
	return _round_polyline(
		_build_route_points_local_with_normals(container, from_pos_g, from_n, to_pos_g, to_n, ignored_buildings, from_building, to_building),
		corner_radius,
		arc_segments
	)

# Preview / finalize lifecycle
func _on_port_start(building: Node2D, port_name: String, _start_pos: Vector2) -> void:
	if building == null or not is_instance_valid(building):
		cancel_active_path_drag()
		return
	
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
	if not _is_active_drag_valid():
		_cleanup_preview()
		return
	_refresh_preview(mouse_pos)


func _refresh_preview(mouse_pos: Vector2) -> void:
	if not _is_active_drag_valid():
		_cleanup_preview()
		return
	
	var from_pos = _get_port_center(_from_building, _from_port_path)
	if from_pos == null:
		_cleanup_preview()
		return

	var preview_target := _get_preview_target_info(mouse_pos, from_pos)
	var to_pos: Vector2 = preview_target["position"]
	var to_normal: Vector2 = preview_target["normal"]
	var ignored_buildings: Array = preview_target["ignored"]
	var to_building: Node2D = preview_target["building"]

	_preview_line.points = _route_points_local_with_normals(
		_preview_container,
		from_pos,
		_get_port_normal(_from_building, _from_port_path),
		to_pos,
		to_normal,
		ignored_buildings,
		_from_building,
		to_building
	)


func _on_port_end(building: Node2D, port_name: String, _mouse_pos: Vector2) -> void:
	if not _can_start_paths():
		_cleanup_preview()
		return

	if building == null or not is_instance_valid(building):
		_cleanup_preview()
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


func _finalize_path(from_b: Node2D, from_port: NodePath, from_pos: Vector2, to_b: Node2D, to_port: NodePath, to_pos: Vector2, rail_version: int = -1, record_history := true, emit_graph_update := true) -> void:
	var history_before := _capture_history_state() if record_history else {}
	var path := Path2D.new()
	var line := Line2D.new()
	var resolved_rail_version := _selected_rail_version if rail_version < 0 else clampi(rail_version, RAIL_VERSION_V1, RAIL_VERSION_V3)
	add_child(path)

	# Metadata for later deletion / rebake
	path.set_meta("from_building", from_b)
	path.set_meta("from_port", from_port)
	path.set_meta("to_building", to_b)
	path.set_meta("to_port", to_port)
	path.set_meta("rail_version", resolved_rail_version)

	line.name = "Line"
	line.width = line_width
	line.antialiased = true
	line.default_color = _get_final_path_color_for_version(resolved_rail_version)
	var raw_local_points := _build_route_points_local(path, from_b, from_port, from_pos, to_b, to_port, to_pos)
	line.points = _round_polyline(raw_local_points, corner_radius, arc_segments)
	path.set_meta("route_polyline_local", raw_local_points)
	path.add_child(line)
	_refresh_path_overlap_shading()

	# Cancel port drag visuals on the origin building (if implemented)
	if is_instance_valid(from_b) and from_b.has_method("cancel_port_drag"):
		from_b.cancel_port_drag()

	_cleanup_preview()
	if emit_graph_update:
		rail_graph_changed.emit()
	if record_history:
		_commit_history_action("Rail created", history_before)

func _cleanup_preview() -> void:
	if _preview_container != null and is_instance_valid(_preview_container):
		_preview_container.queue_free()
	_preview_container = null
	_preview_line = null
	_from_building = null
	_from_port_path = DEFAULT_FROM_PORT_PATH

func cancel_active_path_drag() -> void:
	if is_instance_valid(_from_building) and _from_building.has_method("cancel_port_drag"):
		_from_building.cancel_port_drag()
	_cleanup_preview()

# Updating existing paths when buildings move / are deleted
func update_paths_for_building(building: Node2D, refresh_overlap := true) -> void:
	var updated_paths: Array[Path2D] = []
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
			var raw_local_points := _build_route_points_local(path, from_building, from_port, from_pos, to_building, to_port, to_pos)
			line.points = _round_polyline(raw_local_points, corner_radius, arc_segments)
			path.set_meta("route_polyline_local", raw_local_points)
			updated_paths.append(path)
	if refresh_overlap:
		_refresh_path_overlap_shading()
	else:
		_refresh_path_markers(updated_paths)

#Upon deletion of a building, clean up the paths stemming from or to it.
func remove_paths_for_building(building: Node2D) -> void:
	if building == _from_building:
		cancel_active_path_drag()
	
	var to_delete: Array[Node] = []
	for child in get_children():
		if child is Path2D and child.has_meta("from_building") and child.has_meta("to_building"):
			if child.get_meta("from_building") == building or child.get_meta("to_building") == building:
				to_delete.append(child)
	for n in to_delete:
		_detach_and_queue_free_path(n)
	_refresh_path_overlap_shading()
	if not to_delete.is_empty():
		rail_graph_changed.emit()

func _detach_and_queue_free_path(path: Node) -> void:
	if path == null:
		return
	var parent := path.get_parent()
	if parent != null:
		parent.remove_child(path)
	path.queue_free()
