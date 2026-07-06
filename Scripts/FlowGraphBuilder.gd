extends RefCounted
class_name FlowGraphBuilder

const FlowSimulatorScript := preload("res://Scripts/FlowSimulator.gd")
const RecipeRegistryScript := preload("res://Scripts/RecipeRegistry.gd")

const RAIL_CAPACITY_V1_UPM := 120.0
const RAIL_CAPACITY_V2_UPM := 240.0
const RAIL_CAPACITY_V3_UPM := 480.0

const RAIL_VERSION_V1 := 0
const RAIL_VERSION_V2 := 1
const RAIL_VERSION_V3 := 2

const STORAGE_BUILDING_IDS := {
	&"storage_v1": true,
	&"storage_v2": true,
	&"multistore": true,
	&"expandable_storage": true,
}

const SUPPORT_BUILDING_IDS := {
	&"rail_support": true,
	&"rail_connector": true,
	&"rail_modulator_3": true,
	&"rail_mod_3": true,
	&"rail_modulator_5": true,
	&"rail_mod_5": true,
	&"multirail_3": true,
	&"multirail_5": true,
	&"radial_rail": true,
	&"radial_rail_connect": true,
	&"zipline": true,
}

const DEBUG_BUILDING_DISPLAY_NAMES := {
	&"dispatcher": "Dispatcher",
	&"receiver": "Receiver",
	&"rail_support": "Rail Support",
	&"rail_connector": "Rail Connector",
	&"rail_modulator_3": "Rail Modulator 3",
	&"rail_modulator_5": "Rail Modulator 5",
	&"multirail_3": "Multirail 3",
	&"multirail_5": "Multirail 5",
	&"storage_v1": "Storage V1",
	&"storage_v2": "Storage V2",
	&"multistore": "MultiStore",
	&"expandable_storage": "Expandable Storage",
	&"zipline": "Zipline",
}


static func build_from_scene(buildings_root: Node, path_manager: Node) -> Dictionary:
	var warnings: Array = []
	var nodes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var node_id_by_building := {}

	if buildings_root == null:
		warnings.append(_warning("missing_buildings_root", "Flow graph build skipped: buildings root is missing."))
		return _make_graph(nodes, edges, warnings)

	for child in buildings_root.get_children():
		if not (child is Node2D):
			continue

		var building := child as Node2D
		var node := _build_node_for_building(building)
		nodes.append(node)
		node_id_by_building[building] = String(node.get("id", ""))

	if path_manager == null:
		warnings.append(_warning("missing_path_manager", "Flow graph has buildings but no PathManager rails."))
		return _make_graph(nodes, edges, warnings)

	for child in path_manager.get_children():
		if not (child is Path2D):
			continue
		var path := child as Path2D
		var edge := _build_edge_for_path(path, path_manager, node_id_by_building, warnings)
		if not edge.is_empty():
			edges.append(edge)

	return _make_graph(nodes, edges, warnings)


static func node_id_for_building(building: Node) -> String:
	if building == null:
		return ""
	return "building_%d" % building.get_instance_id()


static func edge_id_for_path(path: Node) -> String:
	if path == null:
		return ""
	return "rail_%d" % path.get_instance_id()


static func capacity_for_rail_version(rail_version: int) -> float:
	match clampi(rail_version, RAIL_VERSION_V1, RAIL_VERSION_V3):
		RAIL_VERSION_V2:
			return RAIL_CAPACITY_V2_UPM
		RAIL_VERSION_V3:
			return RAIL_CAPACITY_V3_UPM
		_:
			return RAIL_CAPACITY_V1_UPM


static func summarize_result(result: Dictionary, max_edges := 5) -> Array[String]:
	var lines: Array[String] = []
	var node_results: Dictionary = result.get("nodes", {})
	var edge_results: Dictionary = result.get("edges", {})
	var warnings: Array = result.get("warnings", [])
	lines.append("Flow Sim: %d nodes, %d rails, %d warning(s)" % [
		node_results.size(),
		edge_results.size(),
		warnings.size()
	])

	for warning in warnings:
		if warning is Dictionary:
			lines.append("Warning: %s" % str(warning.get("message", warning.get("type", "Unknown warning"))))

	var blocked_edges := _sorted_edge_results_by_blocked(edge_results)
	if blocked_edges.is_empty():
		lines.append("No blocked rail flow.")
	else:
		lines.append("Top chokepoints:")
		var blocked_count = mini(blocked_edges.size(), max_edges)
		for i in range(blocked_count):
			lines.append(_format_edge_result_line(blocked_edges[i]))

	var sorted_edges := _sorted_edge_results_by_usage(edge_results)
	if sorted_edges.is_empty():
		lines.append("No simulated rail flow.")
		return lines

	lines.append("Busiest rails:")
	var edge_count = mini(sorted_edges.size(), max_edges)
	for i in range(edge_count):
		lines.append(_format_edge_result_line(sorted_edges[i]))

	return lines


static func _make_graph(nodes: Array[Dictionary], edges: Array[Dictionary], warnings: Array) -> Dictionary:
	return {
		"nodes": nodes,
		"edges": edges,
		"builder_warnings": warnings,
		"metadata": {
			"unit": "units_per_minute",
			"node_count": nodes.size(),
			"edge_count": edges.size(),
		}
	}


static func _build_node_for_building(building: Node2D) -> Dictionary:
	var building_id := _get_building_id(building)
	var selected_item = _get_selected_recipe_like(building)
	var rates := _get_building_rates(building, building_id, selected_item)
	var inputs: Dictionary = rates.get("inputs", {})
	var outputs: Dictionary = rates.get("outputs", {})
	var kind := _classify_building(building_id, inputs, outputs)
	var ports := _collect_port_names(building)

	var node := {
		"id": node_id_for_building(building),
		"kind": kind,
		"building_id": str(building_id),
		"name": building.name,
		"label": _building_label(building),
		"instance_id": building.get_instance_id(),
		"inputs": inputs,
		"outputs": outputs,
		"input_requirements": _get_stack_summaries(selected_item, "inputs"),
		"output_products": _get_stack_summaries(selected_item, "outputs"),
		"ports": ports,
		"position": [building.global_position.x, building.global_position.y],
	}

	if kind == FlowSimulatorScript.NODE_KIND_STORAGE:
		node["inventory"] = _get_storage_inventory(building)
		node["storage_capacity"] = _get_storage_capacity(building)

	var selected_path := _get_resource_path(selected_item)
	if selected_path != "":
		node["selected_resource_path"] = selected_path

	return node


static func _build_edge_for_path(path: Path2D, path_manager: Node, node_id_by_building: Dictionary, warnings: Array) -> Dictionary:
	if not path.has_meta("from_building") or not path.has_meta("to_building"):
		return {}

	var from_building = path.get_meta("from_building")
	var to_building = path.get_meta("to_building")
	if not node_id_by_building.has(from_building) or not node_id_by_building.has(to_building):
		warnings.append(_warning("missing_path_endpoint", "Skipped rail with endpoint outside the buildings root."))
		return {}

	var rail_version := _get_path_rail_version(path, path_manager)
	return {
		"id": edge_id_for_path(path),
		"from": String(node_id_by_building[from_building]),
		"to": String(node_id_by_building[to_building]),
		"capacity_upm": capacity_for_rail_version(rail_version),
		"rail_version": rail_version,
		"from_port": str(path.get_meta("from_port")) if path.has_meta("from_port") else "",
		"to_port": str(path.get_meta("to_port")) if path.has_meta("to_port") else "",
		"from_label": _building_label(from_building),
		"to_label": _building_label(to_building),
		"path_instance_id": path.get_instance_id(),
	}


static func _get_path_rail_version(path: Path2D, path_manager: Node) -> int:
	if path_manager != null and path_manager.has_method("get_path_rail_version"):
		return int(path_manager.call("get_path_rail_version", path))
	if path.has_meta("rail_version"):
		return int(path.get_meta("rail_version"))
	return RAIL_VERSION_V1


static func _get_building_id(building: Node) -> StringName:
	if building != null and "id" in building:
		return StringName(building.get("id"))
	return StringName("")


static func _classify_building(building_id: StringName, inputs: Dictionary, outputs: Dictionary) -> String:
	if STORAGE_BUILDING_IDS.has(building_id):
		return FlowSimulatorScript.NODE_KIND_STORAGE
	if SUPPORT_BUILDING_IDS.has(building_id):
		return FlowSimulatorScript.NODE_KIND_SUPPORT
	if building_id == &"receiver":
		return FlowSimulatorScript.NODE_KIND_SOURCE
	if building_id == &"dispatcher":
		return FlowSimulatorScript.NODE_KIND_MACHINE
	if inputs.is_empty() and not outputs.is_empty():
		return FlowSimulatorScript.NODE_KIND_SOURCE
	if inputs.is_empty() and outputs.is_empty() and _id_looks_like_support(building_id):
		return FlowSimulatorScript.NODE_KIND_SUPPORT
	return FlowSimulatorScript.NODE_KIND_MACHINE


static func _id_looks_like_support(building_id: StringName) -> bool:
	var id_text := str(building_id)
	return id_text.contains("rail") or id_text.contains("zipline")


static func _get_building_rates(building: Node, building_id: StringName, selected_item) -> Dictionary:
	var deltas := _get_deltas_for_selected_item(selected_item)
	if not deltas.is_empty():
		return _split_deltas(deltas)

	if building_id == &"receiver":
		return {
			"inputs": {},
			"outputs": _get_shipment_endpoint_item_rates(selected_item)
		}

	if building_id == &"dispatcher":
		return {
			"inputs": _get_shipment_endpoint_item_rates(selected_item),
			"outputs": {}
		}

	if building != null and "recipe" in building:
		var recipe = building.get("recipe")
		var recipe_deltas := _get_deltas_for_selected_item(recipe)
		if not recipe_deltas.is_empty():
			return _split_deltas(recipe_deltas)

	return {
		"inputs": {},
		"outputs": {}
	}


static func _get_selected_recipe_like(building: Node) -> Variant:
	var purity: OptionButton = null
	if building != null:
		purity = building.get_node_or_null("Purity") as OptionButton
	var purity_item = _get_selected_option_metadata(purity)
	if purity_item != null:
		return purity_item

	var recipe: OptionButton = null
	if building != null:
		recipe = building.get_node_or_null("Recipe") as OptionButton
	var recipe_item = _get_selected_option_metadata(recipe)
	if recipe_item != null:
		return recipe_item

	if building != null and "recipe" in building:
		return building.get("recipe")
	return null


static func _get_selected_option_metadata(option: OptionButton) -> Variant:
	if option == null:
		return null
	if option.selected < 0 or option.selected >= option.item_count:
		return null
	return option.get_item_metadata(option.selected)


static func _get_stack_summaries(selected_item, stack_property: String) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	if selected_item == null:
		return summaries
	if not (selected_item is Object):
		return summaries

	var stacks = (selected_item as Object).get(stack_property)
	if not (stacks is Array):
		return summaries

	for i in range(stacks.size()):
		var stack = stacks[i]
		if stack == null or not (stack is Object):
			continue

		var resource_id := _get_stack_resource_id(stack)
		if resource_id == StringName(""):
			continue

		summaries.append({
			"resource": resource_id,
			"display_name": _get_stack_display_name(stack, resource_id),
			"qty": _get_stack_quantity(stack),
			"index": i,
		})
	return summaries


static func _get_stack_resource_id(stack: Object) -> StringName:
	var raw_id = stack.get("id")
	if raw_id != null and StringName(str(raw_id)) != StringName(""):
		return StringName(str(raw_id))

	var item = stack.get("item")
	if item is Object:
		var item_id = (item as Object).get("id")
		if item_id != null:
			return StringName(str(item_id))
	return StringName("")


static func _get_stack_display_name(stack: Object, resource_id: StringName) -> String:
	var item = stack.get("item")
	if item is Object:
		var display_name = (item as Object).get("display_name")
		if display_name != null and str(display_name).strip_edges() != "":
			return str(display_name)
	return _format_resource_name(str(resource_id))


static func _get_stack_quantity(stack: Object) -> float:
	var qty = stack.get("qty")
	if qty == null:
		return 0.0
	return float(qty)


static func _get_deltas_for_selected_item(selected_item) -> Dictionary:
	if selected_item == null:
		return {}
	if selected_item is Resource and selected_item.has_method("get_deltas"):
		var deltas = selected_item.call("get_deltas")
		return _normalize_rate_map(deltas) if deltas is Dictionary else {}
	return {}


static func _split_deltas(deltas: Dictionary) -> Dictionary:
	var inputs := {}
	var outputs := {}
	for resource in deltas.keys():
		var amount := float(deltas[resource])
		var key := StringName(str(resource))
		if amount < 0.0:
			inputs[key] = absf(amount)
		elif amount > 0.0:
			outputs[key] = amount
	return {
		"inputs": inputs,
		"outputs": outputs
	}


static func _get_shipment_endpoint_item_rates(selected_item) -> Dictionary:
	if selected_item == null:
		return {}

	var deltas := _get_deltas_for_selected_item(selected_item)
	if deltas.is_empty():
		return {}

	var split := _split_deltas(deltas)
	var outputs: Dictionary = split.get("outputs", {})
	if not outputs.is_empty():
		return outputs
	return split.get("inputs", {})


static func _normalize_rate_map(value: Dictionary) -> Dictionary:
	var rates := {}
	for resource in value.keys():
		var amount := float(value[resource])
		if not is_equal_approx(amount, 0.0):
			rates[StringName(str(resource))] = amount
	return rates


static func _collect_port_names(building: Node) -> Dictionary:
	var ports := {
		"input": [],
		"output": [],
		"universal": [],
	}
	if building == null:
		return ports

	var ports_root := building.get_node_or_null("Ports")
	if ports_root == null:
		return ports

	for child in ports_root.get_children():
		var port_name := str(child.name)
		if port_name.begins_with("Input"):
			ports["input"].append(port_name)
		elif port_name.begins_with("Output"):
			ports["output"].append(port_name)
		elif port_name.begins_with("Universal"):
			ports["universal"].append(port_name)

	return ports


static func _get_storage_inventory(building: Node) -> Dictionary:
	if building == null:
		return {}
	if building.has_meta("flow_inventory"):
		var inventory = building.get_meta("flow_inventory")
		if inventory is Dictionary:
			return _normalize_rate_map(inventory)
	if "flow_inventory" in building:
		var property_inventory = building.get("flow_inventory")
		if property_inventory is Dictionary:
			return _normalize_rate_map(property_inventory)
	return {}


static func _get_storage_capacity(building: Node) -> float:
	if building == null:
		return -1.0
	if "storage_capacity" in building:
		return float(building.get("storage_capacity"))
	if building.has_meta("storage_capacity"):
		return float(building.get_meta("storage_capacity"))
	return -1.0


static func _get_resource_path(value) -> String:
	if value is Resource:
		return (value as Resource).resource_path
	return ""


static func _sorted_edge_results_by_usage(edge_results: Dictionary) -> Array:
	var edges: Array = []
	for edge_id in edge_results.keys():
		var edge = edge_results[edge_id]
		if edge is Dictionary:
			edges.append(edge)

	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var usage_a := float(a.get("used_upm", 0.0))
		var usage_b := float(b.get("used_upm", 0.0))
		if not is_equal_approx(usage_a, usage_b):
			return usage_a > usage_b
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return edges


static func _sorted_edge_results_by_blocked(edge_results: Dictionary) -> Array:
	var edges: Array = []
	for edge_id in edge_results.keys():
		var edge = edge_results[edge_id]
		if edge is Dictionary and float(edge.get("blocked_upm", 0.0)) > 0.001:
			edges.append(edge)

	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var blocked_a := float(a.get("blocked_upm", 0.0))
		var blocked_b := float(b.get("blocked_upm", 0.0))
		if not is_equal_approx(blocked_a, blocked_b):
			return blocked_a > blocked_b
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return edges


static func _format_edge_result_line(edge: Dictionary) -> String:
	var capacity := float(edge.get("capacity_upm", 0.0))
	var capacity_text := "unlimited" if bool(edge.get("unlimited", false)) else "%.0f" % capacity
	return "%s | %.0f/%s upm | blocked %.0f" % [
		_format_edge_label(edge),
		float(edge.get("used_upm", 0.0)),
		capacity_text,
		float(edge.get("blocked_upm", 0.0))
	]


static func _format_edge_label(edge: Dictionary) -> String:
	var data: Dictionary = edge.get("data", {})
	var from_label := str(data.get("from_label", edge.get("from", "")))
	var to_label := str(data.get("to_label", edge.get("to", "")))
	var from_port := _format_port_label(str(data.get("from_port", "")))
	var to_port := _format_port_label(str(data.get("to_port", "")))
	if from_port != "" or to_port != "":
		return "%s %s -> %s %s" % [from_label, from_port, to_label, to_port]
	return "%s -> %s" % [from_label, to_label]


static func _building_label(building) -> String:
	if building == null:
		return "Unknown"
	var name_text := str(building.name)
	var building_id := _get_building_id(building)
	if building_id != StringName(""):
		var display_name := _get_building_display_name(building_id)
		return "%s#%s" % [display_name, _get_building_debug_suffix(building, name_text)]
	return name_text


static func _get_building_display_name(building_id: StringName) -> String:
	if DEBUG_BUILDING_DISPLAY_NAMES.has(building_id):
		return String(DEBUG_BUILDING_DISPLAY_NAMES[building_id])
	var registry_names: Dictionary = RecipeRegistryScript.BUILDING_DISPLAY_NAMES
	if registry_names.has(building_id):
		return String(registry_names[building_id])
	return str(building_id).replace("_", " ").capitalize()


static func _get_building_debug_suffix(building: Node, name_text: String) -> String:
	var auto_prefix := "@Node2D@"
	if name_text.begins_with(auto_prefix):
		return name_text.trim_prefix(auto_prefix)
	return str(building.get_instance_id())


static func _format_port_label(port_path: String) -> String:
	var port_text := port_path.get_file().strip_edges()
	if port_text == "":
		return ""
	if port_text.begins_with("Universal"):
		return "U" + port_text.trim_prefix("Universal").strip_edges()
	if port_text.begins_with("Input"):
		return "I" + port_text.trim_prefix("Input").strip_edges()
	if port_text.begins_with("Output"):
		return "O" + port_text.trim_prefix("Output").strip_edges()
	return port_text


static func _format_resource_name(value: String) -> String:
	return value.strip_edges().replace("_", " ").replace("-", " ").capitalize()


static func _warning(kind: String, message: String) -> Dictionary:
	return {
		"type": kind,
		"message": message
	}
