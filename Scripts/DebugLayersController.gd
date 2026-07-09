class_name DebugLayersController
extends RefCounted

# Owns the stackable diagnostic overlay system that draws directly on the build grid
# (building health, heat/power/cost heatmap, wasted output, disconnected, production
# stage, rail saturation) plus its legend. Extracted from main.gd; the host (main)
# supplies the live scene refs (buildings_root, path_manager, build_manager), the UI
# scale, and the CanvasLayer/viewport the legend lives on.

const Palette = preload("res://Scripts/palette.gd")
const OVERLAY_SCRIPT := preload("res://Scripts/debug_layer_overlay.gd")
const LAYER_MODEL := preload("res://Scripts/debug_layer_model.gd")
const FLOW_GRAPH_BUILDER := preload("res://Scripts/FlowGraphBuilder.gd")
const FLOW_SIMULATOR := preload("res://Scripts/FlowSimulator.gd")
const PATHING_INTELLIGENCE := preload("res://Scripts/PathingIntelligence.gd")

const OVERLAY_Z := 120     # above high-visibility rails (RAIL_Z_HIGH_VISIBILITY = 100)
const HEATMAP_METRICS := ["heat", "power", "cost"]
const HEATMAP_METRIC_LABELS := {
	"heat": "Heat",
	"power": "Power",
	"cost": "Build Cost",
}

var _host: Node = null
var _enabled := false
var _layer_active: Dictionary = {}       # layer id (String) -> bool
var _heatmap_metric := 0                  # index into HEATMAP_METRICS
var _overlay: Node2D = null
var _refresh_queued := false
var _legend: PanelContainer = null


func _init(host: Node) -> void:
	_host = host


func setup() -> void:
	var path_manager: Node = _host.path_manager
	if path_manager != null and path_manager.has_signal("rail_graph_changed"):
		var refresh_callable := Callable(self, "queue_refresh")
		if not path_manager.is_connected("rail_graph_changed", refresh_callable):
			path_manager.connect("rail_graph_changed", refresh_callable)


# --- Public state queries (menu enable/pressed state lives in main) ---
func is_enabled() -> bool:
	return _enabled


func is_layer_active(layer_id: String) -> bool:
	return bool(_layer_active.get(layer_id, false))


func is_heatmap_active() -> bool:
	return _enabled and bool(_layer_active.get("heatmap", false))


# --- Public commands ---
func toggle_enabled() -> void:
	_enabled = not _enabled
	if _enabled:
		if not _any_layer_active():
			_layer_active["health"] = true   # sensible default so the toggle shows something
		_refresh()
	else:
		var overlay := _get_overlay()
		if overlay != null:
			overlay.call("set_enabled", false)
		_update_legend()


func toggle_layer(layer_id: String) -> void:
	if not _enabled or layer_id == "":
		return
	_layer_active[layer_id] = not bool(_layer_active.get(layer_id, false))
	_refresh()


func cycle_heatmap_metric() -> void:
	if not _enabled or not bool(_layer_active.get("heatmap", false)):
		return
	_heatmap_metric = (_heatmap_metric + 1) % HEATMAP_METRICS.size()
	_refresh()


func queue_refresh() -> void:
	if not _enabled or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh")


func on_ui_scale_changed() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.call("set_scale_factor", _host._ui_scale)
	if _enabled:
		_update_legend()


# --- Internals ---
func _any_layer_active() -> bool:
	for layer_id in _layer_active.keys():
		if bool(_layer_active[layer_id]):
			return true
	return false


func _get_overlay() -> Node2D:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	var path_manager: Node = _host.path_manager
	if path_manager == null:
		return null
	_overlay = OVERLAY_SCRIPT.new()
	_overlay.name = "DebugLayerOverlay"
	_overlay.z_index = OVERLAY_Z
	path_manager.add_child(_overlay)
	_overlay.call("set_scale_factor", _host._ui_scale)
	return _overlay


func _refresh() -> void:
	_refresh_queued = false
	var overlay := _get_overlay()
	if overlay == null:
		return
	if not _enabled:
		overlay.call("set_enabled", false)
		_update_legend()
		return
	var buildings_root: Node2D = _host.buildings_root
	if buildings_root == null:
		overlay.call("set_enabled", false)
		return

	var graph: Dictionary = FLOW_GRAPH_BUILDER.build_from_scene(buildings_root, _host.path_manager)
	var simulation: Dictionary = {}
	var graph_edges = graph.get("edges", [])
	if graph_edges is Array and not (graph_edges as Array).is_empty():
		var simulator: RefCounted = FLOW_SIMULATOR.new()
		simulation = simulator.simulate(graph)
	var options := {"world_units_per_tile": _host._pathing_world_units_per_tile()}
	var assessment: Dictionary = PATHING_INTELLIGENCE.analyze_graph(graph, simulation, options)

	overlay.call("set_scale_factor", _host._ui_scale)
	overlay.call("set_active_layers", _layer_active)
	overlay.call("set_payload", _build_payload(graph, assessment, simulation))
	overlay.call("set_enabled", true)
	_update_legend()


func _build_payload(graph: Dictionary, assessment: Dictionary, simulation: Dictionary) -> Dictionary:
	var nodes := _as_array(graph.get("nodes", []))
	var building_assessments: Dictionary = assessment.get("building_assessments", {}) if assessment.get("building_assessments", {}) is Dictionary else {}
	var edge_supply: Dictionary = assessment.get("edge_supply", {}) if assessment.get("edge_supply", {}) is Dictionary else {}
	var tile: float = _host._pathing_world_units_per_tile()
	if tile <= 0.0:
		tile = 64.0

	var geo := {}          # node_id -> {center: Vector2, size: Vector2}
	var node_by_id := {}
	for node_variant in nodes:
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := String(node.get("id", ""))
		if node_id == "":
			continue
		node_by_id[node_id] = node
		geo[node_id] = {
			"center": _node_center(node),
			"size": _node_size(node, tile),
		}

	return {
		"health": _build_health_payload(building_assessments, geo),
		"heatmap": _build_heatmap_payload(nodes, geo),
		"waste": _build_waste_payload(edge_supply, geo),
		"orphan": _build_orphan_payload(graph, node_by_id, geo),
		"tiering": _build_tiering_payload(graph, nodes, geo),
		"saturation": _build_saturation_payload(simulation),
	}


func _build_tiering_payload(graph: Dictionary, nodes: Array, geo: Dictionary) -> Dictionary:
	var result: Dictionary = LAYER_MODEL.production_tiers(graph)
	var tiers: Dictionary = result.get("tiers", {}) if result.get("tiers", {}) is Dictionary else {}
	var max_tier := int(result.get("max_tier", 0))
	var entries: Array = []
	for node_variant in nodes:
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		# Supports/junctions are transparent to the chain, so don't clutter the map with them.
		var kind := String(node.get("kind", "")).to_lower()
		if kind == "support" or kind == "junction" or kind == "router":
			continue
		var node_id := String(node.get("id", ""))
		if not tiers.has(node_id):
			continue
		var g = geo.get(node_id, {})
		if not (g is Dictionary) or (g as Dictionary).is_empty():
			continue
		var tier := int(tiers[node_id])
		var t := (float(tier) / float(max_tier)) if max_tier > 0 else 0.0
		entries.append({"center": g["center"], "size": g["size"], "tier": tier, "t": t})
	return {"entries": entries, "max_tier": max_tier}


func _build_saturation_payload(simulation: Dictionary) -> Dictionary:
	var saturations: Dictionary = LAYER_MODEL.rail_saturations(simulation)
	var rails: Array = []
	for edge_id in saturations.keys():
		var info = saturations[edge_id]
		if not (info is Dictionary):
			continue
		var points := _rail_global_points(String(edge_id))
		if points.size() >= 2:
			rails.append({"points": points, "state": String((info as Dictionary).get("state", "spare"))})
	return {"rails": rails}


func _build_health_payload(building_assessments: Dictionary, geo: Dictionary) -> Array:
	var entries: Array = []
	for node_id in building_assessments.keys():
		var ba = building_assessments[node_id]
		if not (ba is Dictionary):
			continue
		var state := String(LAYER_MODEL.health_state(ba))
		if state == "":
			continue
		var g = geo.get(String(node_id), {})
		if not (g is Dictionary) or (g as Dictionary).is_empty():
			continue
		entries.append({
			"center": g["center"],
			"size": g["size"],
			"state": state,
			"label": String((ba as Dictionary).get("node_label", "")),
		})
	return entries


func _build_heatmap_payload(nodes: Array, geo: Dictionary) -> Dictionary:
	var metric := String(HEATMAP_METRICS[_heatmap_metric])
	var raw: Array = []
	var values: Array = []
	for node_variant in nodes:
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var building := _building_for_node(node)
		if building == null:
			continue
		var value := _building_metric(building, metric)
		if value <= 0.0:
			continue
		var g = geo.get(String(node.get("id", "")), {})
		if not (g is Dictionary) or (g as Dictionary).is_empty():
			continue
		raw.append({"center": g["center"], "size": g["size"], "value": value})
		values.append(value)

	var ts := LAYER_MODEL.normalize(values)
	var entries: Array = []
	for i in range(raw.size()):
		var item: Dictionary = raw[i]
		entries.append({"center": item["center"], "size": item["size"], "t": float(ts[i]), "value": item["value"]})
	return {"metric": metric, "entries": entries}


func _building_metric(building: Node, metric: String) -> float:
	match metric:
		"heat":
			return absf(float(building.get("heat"))) if "heat" in building else 0.0
		"power":
			return absf(float(building.get("power"))) if "power" in building else 0.0
		"cost":
			return absf(float(building.get("build_cost_amount"))) if "build_cost_amount" in building else 0.0
	return 0.0


func _build_waste_payload(edge_supply: Dictionary, geo: Dictionary) -> Dictionary:
	var waste: Dictionary = LAYER_MODEL.waste_sources(edge_supply)
	var buildings: Array = []
	for from_id in _as_array(waste.get("from_ids", [])):
		var g = geo.get(String(from_id), {})
		if g is Dictionary and not (g as Dictionary).is_empty():
			buildings.append({"center": g["center"], "size": g["size"]})
	var rails: Array = []
	for edge_id in _as_array(waste.get("edge_ids", [])):
		var points := _rail_global_points(String(edge_id))
		if points.size() >= 2:
			rails.append({"points": points})
	return {"buildings": buildings, "rails": rails}


func _build_orphan_payload(graph: Dictionary, node_by_id: Dictionary, geo: Dictionary) -> Dictionary:
	var result: Dictionary = LAYER_MODEL.orphans(graph)
	var buildings: Array = []
	for node_id in _as_array(result.get("disconnected", [])):
		var g = geo.get(String(node_id), {})
		if g is Dictionary and not (g as Dictionary).is_empty():
			buildings.append({"center": g["center"], "size": g["size"]})

	var ports: Array = []
	var unconnected: Dictionary = result.get("unconnected_ports", {}) if result.get("unconnected_ports", {}) is Dictionary else {}
	for node_id in unconnected.keys():
		var node = node_by_id.get(String(node_id), {})
		if not (node is Dictionary):
			continue
		var building := _building_for_node(node)
		if building == null:
			continue
		for port_name in _as_array(unconnected[node_id]):
			var port_pos = _port_global_position(building, String(port_name))
			if port_pos is Vector2:
				ports.append({"pos": port_pos})
	return {"buildings": buildings, "ports": ports}


func _port_global_position(building: Node, port_name: String):
	var ports_root = building.get_node_or_null("Ports")
	if ports_root == null:
		return null
	var port_node = ports_root.get_node_or_null(port_name)
	if port_node is Node2D:
		return (port_node as Node2D).global_position
	return null


func _node_center(node: Dictionary) -> Vector2:
	var position = node.get("position", null)
	if position is Array and (position as Array).size() >= 2:
		return Vector2(float(position[0]), float(position[1]))
	if position is Vector2:
		return position
	return Vector2.ZERO


func _node_size(node: Dictionary, tile: float) -> Vector2:
	var building := _building_for_node(node)
	var build_manager: Node = _host.build_manager
	if building != null and build_manager != null and build_manager.has_method("get_rotated_footprint"):
		var footprint = build_manager.call("get_rotated_footprint", building)
		if footprint is Vector2i and footprint != Vector2i.ZERO:
			return Vector2(footprint) * tile
	return Vector2(tile, tile)


func _building_for_node(node: Dictionary) -> Node:
	var instance_id = node.get("instance_id", 0)
	if typeof(instance_id) == TYPE_INT and int(instance_id) != 0:
		var obj = instance_from_id(int(instance_id))
		if obj is Node and is_instance_valid(obj):
			return obj as Node
	return null


func _rail_global_points(edge_id: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	var prefix := "rail_"
	if not edge_id.begins_with(prefix):
		return points
	var instance_id := int(edge_id.trim_prefix(prefix))
	if instance_id == 0:
		return points
	var obj = instance_from_id(instance_id)
	if not (obj is Path2D) or not is_instance_valid(obj):
		return points
	var path := obj as Path2D
	# The routed geometry lives on the "route_polyline_local" meta (falling back to the
	# Line2D child's points), not on Path2D.curve — mirror PathManager._get_path_global_points.
	var source_points = path.get_meta("route_polyline_local") if path.has_meta("route_polyline_local") else null
	if source_points == null:
		var line := path.get_node_or_null("Line") as Line2D
		if line == null:
			for child in path.get_children():
				if child is Line2D:
					line = child as Line2D
					break
		if line != null:
			source_points = line.points
	if source_points == null:
		return points
	for local_point in source_points:
		if local_point is Vector2:
			points.append(path.to_global(local_point))
	return points


func _as_array(value) -> Array:
	return value if value is Array else []


func _update_legend() -> void:
	if not _enabled or not _any_layer_active():
		if _legend != null and is_instance_valid(_legend):
			_legend.visible = false
		return
	var panel := _get_legend()
	var vbox := panel.get_node("Margin/Rows") as VBoxContainer
	for child in vbox.get_children():
		child.queue_free()

	vbox.add_child(_legend_title("Debug Layers"))
	if bool(_layer_active.get("health", false)):
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.HEALTH_SUPPLIED, "Supplied", false))
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.HEALTH_UNDER, "Under-supplied", false))
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.HEALTH_MISSING, "Missing input", false))
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.HEALTH_DISCONNECTED, "Disconnected", true))
	if bool(_layer_active.get("heatmap", false)):
		var metric := String(HEATMAP_METRICS[_heatmap_metric])
		var metric_label := String(HEATMAP_METRIC_LABELS.get(metric, metric))
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.HEAT_HOT, "%s (low → high)" % metric_label, false))
	if bool(_layer_active.get("waste", false)):
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.WASTE_COLOR, "Wasted output", false))
	if bool(_layer_active.get("orphan", false)):
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.ORPHAN_COLOR, "Disconnected / unused port", true))
	if bool(_layer_active.get("tiering", false)):
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.TIER_HIGH, "Production stage (raw → final)", false))
	if bool(_layer_active.get("saturation", false)):
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.SATURATION_SPARE, "Rail: spare capacity", false))
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.SATURATION_NEAR, "Rail: near capacity (≥85%)", false))
		vbox.add_child(_legend_row(OVERLAY_SCRIPT.SATURATION_OVER, "Rail: at / over capacity", false))

	panel.visible = true
	panel.reset_size()
	_position_legend(panel)


func _get_legend() -> PanelContainer:
	if _legend != null and is_instance_valid(_legend):
		return _legend
	var panel := PanelContainer.new()
	panel.name = "DebugLayerLegend"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER))
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "Rows"
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	var canvas := _host.get_node("Camera2D/CanvasLayer")
	canvas.add_child(panel)
	_legend = panel
	return panel


func _legend_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", int(round(12 * _host._ui_scale)))
	return label


func _legend_row(color: Color, text: String, dashed: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = _host._scaled_vec2(Vector2(16, 12))
	swatch.color = Palette.with_alpha(color, 1.0)
	row.add_child(swatch)
	var label := Label.new()
	label.text = text + (" (dashed)" if dashed else "")
	label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	label.add_theme_font_size_override("font_size", int(round(13 * _host._ui_scale)))
	row.add_child(label)
	return row


func _position_legend(panel: PanelContainer) -> void:
	var viewport_size: Vector2 = _host.get_viewport().get_visible_rect().size
	var margin := 12.0 * float(_host._ui_scale)
	panel.position = Vector2(margin, viewport_size.y - panel.size.y - margin)
