extends RefCounted
class_name PathingIntelligence

const Palette = preload("res://Scripts/palette.gd")

const NODE_KIND_SOURCE := "source"
const NODE_KIND_MACHINE := "machine"
const NODE_KIND_STORAGE := "storage"
const NODE_KIND_JUNCTION := "junction"
const NODE_KIND_SUPPORT := "support"
const NODE_KIND_ROUTER := "router"

const REQUIREMENT_SUPPLIED := "supplied"
const REQUIREMENT_MISSING := "missing"

# Sufficiency compares estimated upstream supply rate against recipe demand rate.
# It is an "is enough produced upstream" signal, not an allocated/delivered rate,
# so a bus shared by multiple consumers can still read sufficient here.
const SUFFICIENCY_SUFFICIENT := "sufficient"
const SUFFICIENCY_UNDER := "under_supplied"
const SUFFICIENCY_UNKNOWN := "unknown"
const SUFFICIENCY_EPSILON := 0.01

# supply_basis records which number drove the sufficiency check, so tooltips stay honest.
const SUPPLY_BASIS_ESTIMATED := "estimated"
const SUPPLY_BASIS_DELIVERED := "delivered"

# Downstream impact (2.1): what removing a rail would do to consumers downstream.
const IMPACT_SEVERITY_BREAK := "break"       # a required input goes fully missing
const IMPACT_SEVERITY_DEGRADE := "degrade"   # a satisfied input drops to under-supplied
# Skip the per-rail counterfactual on very large plans (it is O(rails) re-analyses).
const DEFAULT_IMPACT_EDGE_CAP := 150

const META_HOME_POSITION := &"pathing2_home_position"
const META_HOME_COLOR := &"pathing2_home_color"
const META_LAYOUT_KEY := &"pathing2_layout_key"
const META_OVERRIDE_ACTIVE := &"pathing2_override_active"

const COLOR_SUPPLIED := Color8(41, 90, 108, 220)
const COLOR_SHARED := Color8(66, 98, 118, 228)
const COLOR_MISSING := Color8(126, 92, 35, 220)
const COLOR_UNUSED := Color8(75, 86, 100, 220)
# Present-but-insufficient. A bright orange reads as a distinct color name ("orange")
# versus the dark amber-brown of COLOR_MISSING across common color-vision types.
const COLOR_UNDER_SUPPLIED := Color8(214, 138, 34, 228)


# options (all optional):
#   world_units_per_tile: float  -> converts world distance to approximate tile counts for suggestions
#   catalog_lookup: Callable(StringName) -> String  -> names the building that produces a resource
#       (used only when nothing in the plan produces a missing resource)
#   minimal: bool  -> skips suggestions, dead-end, and supplier indexing; used by the
#       downstream-impact counterfactuals, which only need per-building requirement states
static func analyze_graph(graph: Dictionary, simulation: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var nodes := _as_array(graph.get("nodes", []))
	var edges := _normalize_edges(_as_array(graph.get("edges", [])))
	var node_index := _build_node_index(nodes)
	var node_order := _build_node_order(nodes, node_index)
	var incoming_edges := _build_edge_adjacency(edges, "to")
	var edge_delivered := _build_edge_delivered(simulation)
	var has_simulation := not edge_delivered.is_empty()
	var minimal := bool(options.get("minimal", false))
	var supply_cache := {}
	var edge_supply := {}

	for edge in edges:
		var edge_id := String(edge.get("id", ""))
		if edge_id == "":
			continue
		var from_id := String(edge.get("from", ""))
		var supply := _collect_supply_for_node(from_id, node_index, incoming_edges, supply_cache, [])
		edge_supply[edge_id] = _make_edge_supply(edge, supply)

	if not minimal:
		_annotate_dead_end_edges(edge_supply, node_index, edges)
	var building_assessments := _build_building_assessments(node_index, node_order, incoming_edges, edge_supply, edge_delivered, has_simulation)
	if not minimal:
		var supplier_index := _build_supplier_index(node_index, node_order, edge_supply)
		_attach_missing_supply_suggestions(building_assessments, node_index, supplier_index, options)
	return {
		"edge_supply": edge_supply,
		"building_assessments": building_assessments,
		"metadata": {
			"node_count": node_order.size(),
			"edge_count": edges.size(),
			"assessed_building_count": building_assessments.size(),
			"has_simulation": has_simulation,
		}
	}


# Extracts per-edge delivered rates (units/min) from a FlowSimulator result so the
# sufficiency check can use what actually arrives rather than upstream availability.
static func _build_edge_delivered(simulation: Dictionary) -> Dictionary:
	var result := {}
	var edges = simulation.get("edges", {})
	if not (edges is Dictionary):
		return result
	for edge_id in edges.keys():
		var edge_result = edges[edge_id]
		if not (edge_result is Dictionary):
			continue
		var delivered = (edge_result as Dictionary).get("delivered_by_resource", {})
		if not (delivered is Dictionary):
			continue
		var rate_map := {}
		for resource in delivered.keys():
			var amount := float(delivered[resource])
			if amount > 0.0:
				rate_map[StringName(str(resource))] = amount
		result[String(edge_id)] = rate_map
	return result


static func apply_scene_assessment(buildings_root: Node, assessment: Dictionary) -> void:
	if buildings_root == null:
		return

	var building_assessments = assessment.get("building_assessments", {})
	var assessments: Dictionary = building_assessments if building_assessments is Dictionary else {}
	for child in buildings_root.get_children():
		if not (child is Node2D):
			continue
		var building := child as Node2D
		var node_id := "building_%d" % building.get_instance_id()
		var building_assessment = assessments.get(node_id, {})
		if building_assessment is Dictionary and not (building_assessment as Dictionary).is_empty():
			_apply_building_assessment(building, building_assessment)
		else:
			_clear_building_intelligence(building)


static func _build_node_index(nodes: Array) -> Dictionary:
	var node_index := {}
	for i in range(nodes.size()):
		var node_variant = nodes[i]
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := String(node.get("id", "node_%d" % i))
		if node_id == "":
			continue
		node_index[node_id] = node
	return node_index


static func _build_node_order(nodes: Array, node_index: Dictionary) -> Array:
	var order: Array = []
	for i in range(nodes.size()):
		var node_variant = nodes[i]
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := String(node.get("id", "node_%d" % i))
		if node_id != "" and node_index.has(node_id) and not order.has(node_id):
			order.append(node_id)
	return order


static func _normalize_edges(raw_edges: Array) -> Array:
	var edges: Array = []
	for i in range(raw_edges.size()):
		var edge_variant = raw_edges[i]
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if from_id == "" or to_id == "":
			continue
		var normalized := edge.duplicate(true)
		if String(normalized.get("id", "")) == "":
			normalized["id"] = "edge_%d" % i
		edges.append(normalized)
	return edges


static func _build_edge_adjacency(edges: Array, key_name: String) -> Dictionary:
	var adjacency := {}
	for edge_variant in edges:
		var edge: Dictionary = edge_variant
		var node_id := String(edge.get(key_name, ""))
		if node_id == "":
			continue
		if not adjacency.has(node_id):
			adjacency[node_id] = []
		(adjacency[node_id] as Array).append(edge)
	return adjacency


static func _collect_supply_for_node(node_id: String, node_index: Dictionary, incoming_edges: Dictionary, supply_cache: Dictionary, stack: Array) -> Dictionary:
	if node_id == "" or not node_index.has(node_id):
		return {}
	if supply_cache.has(node_id):
		return _duplicate_supply_map(supply_cache[node_id])
	if stack.has(node_id):
		return {}

	var node: Dictionary = node_index.get(node_id, {})
	var next_stack := stack.duplicate()
	next_stack.append(node_id)

	var supply := _own_supply_for_node(node)
	if _node_passes_through(node):
		for edge_variant in _as_array(incoming_edges.get(node_id, [])):
			var edge: Dictionary = edge_variant
			var upstream := _collect_supply_for_node(String(edge.get("from", "")), node_index, incoming_edges, supply_cache, next_stack)
			_merge_supply_maps(supply, upstream)

	supply_cache[node_id] = _duplicate_supply_map(supply)
	return supply


# Flags, per rail, which of its carried resources have no downstream consumer.
# The forward mirror of the upstream supply walk: storage is treated as a valid sink
# (bussing into storage is not a dead-end), and machines terminally consume their recipe inputs.
static func _annotate_dead_end_edges(edge_supply: Dictionary, node_index: Dictionary, edges: Array) -> void:
	var outgoing_edges := _build_edge_adjacency(edges, "from")
	var demand_cache := {}
	for edge_id in edge_supply.keys():
		var es: Dictionary = edge_supply[edge_id]
		var rail_resources := _as_array(es.get("resources", []))
		var unused: Array = []
		if not rail_resources.is_empty():
			var downstream := _collect_demand_for_node(String(es.get("to", "")), node_index, outgoing_edges, demand_cache, [])
			if not bool(downstream.get("accepts_all", false)):
				var demanded: Dictionary = downstream.get("resources", {})
				for resource in rail_resources:
					if not demanded.has(StringName(str(resource))):
						unused.append(resource)
		es["unused_resources"] = unused
		es["is_dead_end"] = (not rail_resources.is_empty()) and unused.size() == rail_resources.size()
		edge_supply[edge_id] = es


static func _collect_demand_for_node(node_id: String, node_index: Dictionary, outgoing_edges: Dictionary, demand_cache: Dictionary, stack: Array) -> Dictionary:
	if node_id == "" or not node_index.has(node_id):
		return {"accepts_all": false, "resources": {}}
	if demand_cache.has(node_id):
		return _duplicate_demand(demand_cache[node_id])
	if stack.has(node_id):
		return {"accepts_all": false, "resources": {}}

	var node: Dictionary = node_index.get(node_id, {})
	var kind := _node_kind(node)
	var result := {"accepts_all": false, "resources": {}}

	if kind == NODE_KIND_STORAGE:
		# Storage stockpiles anything, so a rail feeding it always has a valid destination.
		result["accepts_all"] = true
	elif kind == NODE_KIND_MACHINE:
		# A machine terminally consumes its recipe inputs; incoming resources do not pass through.
		var resources: Dictionary = result["resources"]
		for requirement_variant in _requirements_for_node(node):
			var requirement: Dictionary = requirement_variant
			resources[StringName(str(requirement.get("resource", "")))] = true
	else:
		# Source / support / junction / router forward demand to whatever they feed.
		var next_stack := stack.duplicate()
		next_stack.append(node_id)
		var resources: Dictionary = result["resources"]
		for edge_variant in _as_array(outgoing_edges.get(node_id, [])):
			var edge: Dictionary = edge_variant
			var downstream := _collect_demand_for_node(String(edge.get("to", "")), node_index, outgoing_edges, demand_cache, next_stack)
			if bool(downstream.get("accepts_all", false)):
				result["accepts_all"] = true
			for resource in (downstream.get("resources", {}) as Dictionary).keys():
				resources[resource] = true

	demand_cache[node_id] = _duplicate_demand(result)
	return result


static func _duplicate_demand(value: Dictionary) -> Dictionary:
	return {
		"accepts_all": bool(value.get("accepts_all", false)),
		"resources": (value.get("resources", {}) as Dictionary).duplicate(),
	}


# Downstream impact preview: for each rail, counterfactually removes it, re-analyzes, and
# records which downstream consumers would break (input goes missing) or degrade (drops to
# under-supplied). Counterfactual diffing is what makes this redundancy-aware: if another rail
# still supplies the resource, removing this one is correctly reported as no impact.
# Mutates assessment["edge_supply"][*]["downstream_impact"].
static func annotate_downstream_impact(assessment: Dictionary, graph: Dictionary, edge_cap: int = DEFAULT_IMPACT_EDGE_CAP) -> void:
	var edge_supply = assessment.get("edge_supply", {})
	if not (edge_supply is Dictionary):
		return
	var edge_supply_dict: Dictionary = edge_supply

	# Clear any prior impact so stale data never lingers between refreshes.
	for edge_id in edge_supply_dict.keys():
		(edge_supply_dict[edge_id] as Dictionary)["downstream_impact"] = []

	var edges := _as_array(graph.get("edges", []))
	if edges.is_empty() or (edge_cap > 0 and edges.size() > edge_cap):
		return

	var baseline := analyze_graph(graph, {}, {"minimal": true})
	var baseline_states := _requirement_states_by_building(baseline)

	for edge_id_variant in edge_supply_dict.keys():
		var edge_id := String(edge_id_variant)
		var counterfactual := analyze_graph(_graph_without_edge(graph, edge_id), {}, {"minimal": true})
		var counterfactual_states := _requirement_states_by_building(counterfactual)
		(edge_supply_dict[edge_id] as Dictionary)["downstream_impact"] = _diff_impacts(baseline_states, counterfactual_states)


static func _graph_without_edge(graph: Dictionary, edge_id: String) -> Dictionary:
	var kept: Array = []
	for edge_variant in _as_array(graph.get("edges", [])):
		if not (edge_variant is Dictionary):
			continue
		if String((edge_variant as Dictionary).get("id", "")) == edge_id:
			continue
		kept.append(edge_variant)
	return {"nodes": graph.get("nodes", []), "edges": kept}


static func _requirement_states_by_building(assessment: Dictionary) -> Dictionary:
	var result := {}
	var building_assessments = assessment.get("building_assessments", {})
	if not (building_assessments is Dictionary):
		return result
	for node_id in building_assessments.keys():
		var building_assessment: Dictionary = building_assessments[node_id]
		var per_resource := {}
		for requirement_variant in _as_array(building_assessment.get("requirements", [])):
			var requirement: Dictionary = requirement_variant
			per_resource[StringName(str(requirement.get("resource", "")))] = {
				"state": String(requirement.get("state", "")),
				"sufficiency": String(requirement.get("sufficiency", "")),
				"display_name": String(requirement.get("display_name", "")),
			}
		result[String(node_id)] = {
			"label": String(building_assessment.get("node_label", "")),
			"requirements": per_resource,
		}
	return result


static func _diff_impacts(baseline_states: Dictionary, counterfactual_states: Dictionary) -> Array:
	var impacts: Array = []
	for node_id in baseline_states.keys():
		var baseline: Dictionary = baseline_states[node_id]
		var baseline_requirements: Dictionary = baseline.get("requirements", {})
		var counterfactual: Dictionary = counterfactual_states.get(node_id, {})
		var counterfactual_requirements: Dictionary = counterfactual.get("requirements", {})
		for resource in baseline_requirements.keys():
			var before: Dictionary = baseline_requirements[resource]
			if String(before.get("state", "")) != REQUIREMENT_SUPPLIED:
				continue  # already missing in the baseline; this rail is not what supplies it
			var after: Dictionary = counterfactual_requirements.get(resource, {})
			var severity := ""
			if String(after.get("state", "")) == REQUIREMENT_MISSING:
				severity = IMPACT_SEVERITY_BREAK
			elif String(before.get("sufficiency", "")) != SUFFICIENCY_UNDER and String(after.get("sufficiency", "")) == SUFFICIENCY_UNDER:
				severity = IMPACT_SEVERITY_DEGRADE
			if severity != "":
				impacts.append({
					"node_id": String(node_id),
					"label": String(baseline.get("label", "")),
					"display_name": String(before.get("display_name", _format_resource_name(str(resource)))),
					"resource": resource,
					"severity": severity,
				})

	impacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a.get("severity", "")) != String(b.get("severity", "")):
			return String(a.get("severity", "")) < String(b.get("severity", ""))  # "break" sorts before "degrade"
		if String(a.get("label", "")) != String(b.get("label", "")):
			return String(a.get("label", "")) < String(b.get("label", ""))
		return String(a.get("resource", "")) < String(b.get("resource", ""))
	)
	return impacts


static func _own_supply_for_node(node: Dictionary) -> Dictionary:
	var supply := {}
	var outputs := _rate_map(node.get("outputs", {}))
	var output_names := _resource_display_names_from_stack_summaries(node.get("output_products", []))
	for resource in outputs.keys():
		_add_origin_to_supply(
			supply,
			resource,
			String(output_names.get(resource, _format_resource_name(str(resource)))),
			float(outputs[resource]),
			node
		)

	if _node_kind(node) == NODE_KIND_STORAGE:
		var inventory := _rate_map(node.get("inventory", node.get("initial_inventory", {})))
		for resource in inventory.keys():
			if outputs.has(resource):
				continue
			_add_origin_to_supply(
				supply,
				resource,
				String(output_names.get(resource, _format_resource_name(str(resource)))),
				float(inventory[resource]),
				node
			)

	return supply


static func _add_origin_to_supply(supply: Dictionary, resource, display_name: String, rate: float, node: Dictionary) -> void:
	var resource_key := StringName(str(resource))
	if resource_key == StringName(""):
		return

	var entry: Dictionary = supply.get(resource_key, {
		"resource": resource_key,
		"display_name": display_name,
		"rate": 0.0,
		"origins": [],
	})
	entry["rate"] = float(entry.get("rate", 0.0)) + maxf(rate, 0.0)
	if String(entry.get("display_name", "")).strip_edges() == "":
		entry["display_name"] = display_name

	var origins: Array = entry.get("origins", [])
	var origin := {
		"node_id": String(node.get("id", "")),
		"label": _node_label(node),
		"building_id": String(node.get("building_id", "")),
		"kind": _node_kind(node),
		"resource": resource_key,
		"display_name": display_name,
		"rate": maxf(rate, 0.0),
	}
	_append_unique_origin(origins, origin)
	entry["origins"] = origins
	supply[resource_key] = entry


static func _append_unique_origin(origins: Array, origin: Dictionary) -> void:
	var origin_key := "%s|%s" % [String(origin.get("node_id", "")), str(origin.get("resource", ""))]
	for existing_variant in origins:
		if not (existing_variant is Dictionary):
			continue
		var existing: Dictionary = existing_variant
		var existing_key := "%s|%s" % [String(existing.get("node_id", "")), str(existing.get("resource", ""))]
		if existing_key == origin_key:
			existing["rate"] = float(existing.get("rate", 0.0)) + float(origin.get("rate", 0.0))
			return
	origins.append(origin)


static func _merge_supply_maps(target: Dictionary, source: Dictionary) -> void:
	for resource in source.keys():
		var source_entry: Dictionary = source[resource]
		var target_entry: Dictionary = target.get(resource, {
			"resource": resource,
			"display_name": String(source_entry.get("display_name", _format_resource_name(str(resource)))),
			"rate": 0.0,
			"origins": [],
		})
		target_entry["rate"] = float(target_entry.get("rate", 0.0)) + float(source_entry.get("rate", 0.0))
		var origins: Array = target_entry.get("origins", [])
		for origin_variant in _as_array(source_entry.get("origins", [])):
			if origin_variant is Dictionary:
				_append_unique_origin(origins, origin_variant)
		target_entry["origins"] = origins
		target[resource] = target_entry


static func _duplicate_supply_map(value: Dictionary) -> Dictionary:
	return value.duplicate(true)


static func _make_edge_supply(edge: Dictionary, supply: Dictionary) -> Dictionary:
	var resources := _sorted_keys(supply.keys())
	var origin_count := 0
	for resource in resources:
		var entry: Dictionary = supply.get(resource, {})
		origin_count += _as_array(entry.get("origins", [])).size()

	return {
		"id": String(edge.get("id", "")),
		"from": String(edge.get("from", "")),
		"to": String(edge.get("to", "")),
		"from_port": String(edge.get("from_port", "")),
		"to_port": String(edge.get("to_port", "")),
		"resources": resources,
		"resource_facts": supply.duplicate(true),
		"is_shared": resources.size() > 1,
		"origin_count": origin_count,
	}


# Inverted index: resource -> { producers: [...], rails: [...] } so a missing requirement
# can look up the nearest place its resource is available in one pass.
static func _build_supplier_index(node_index: Dictionary, node_order: Array, edge_supply: Dictionary) -> Dictionary:
	var index := {}

	# Producers: any node that outputs a resource (or storage that holds it).
	for node_id_variant in node_order:
		var node_id := String(node_id_variant)
		var node: Dictionary = node_index.get(node_id, {})
		var pos := _node_position(node)
		var label := _node_label(node)
		var names := _resource_display_names_from_stack_summaries(node.get("output_products", []))
		var produced := _rate_map(node.get("outputs", {}))
		if _node_kind(node) == NODE_KIND_STORAGE:
			var inventory := _rate_map(node.get("inventory", node.get("initial_inventory", {})))
			for resource in inventory.keys():
				if not produced.has(resource):
					produced[resource] = inventory[resource]
		for resource in produced.keys():
			var resource_key := StringName(str(resource))
			var entry := _ensure_supplier_entry(index, resource_key)
			(entry["producers"] as Array).append({
				"node_id": node_id,
				"label": label,
				"display_name": String(names.get(resource_key, _format_resource_name(str(resource_key)))),
				"position": pos,
			})

	# Rails: any edge already carrying the resource (from edge_supply).
	for edge_id_variant in edge_supply.keys():
		var edge_id := String(edge_id_variant)
		var supply: Dictionary = edge_supply[edge_id]
		var from_pos := _node_position(node_index.get(String(supply.get("from", "")), {}))
		var to_pos := _node_position(node_index.get(String(supply.get("to", "")), {}))
		var facts: Dictionary = supply.get("resource_facts", {})
		for resource in _as_array(supply.get("resources", [])):
			var resource_key := StringName(str(resource))
			var fact = facts.get(resource_key, {})
			var display_name := String((fact as Dictionary).get("display_name", _format_resource_name(str(resource_key)))) if fact is Dictionary else _format_resource_name(str(resource_key))
			var entry := _ensure_supplier_entry(index, resource_key)
			(entry["rails"] as Array).append({
				"edge_id": edge_id,
				"positions": [from_pos, to_pos],
				"display_name": display_name,
			})

	return index


static func _ensure_supplier_entry(index: Dictionary, resource: StringName) -> Dictionary:
	if not index.has(resource):
		index[resource] = {"producers": [], "rails": []}
	return index[resource]


static func _attach_missing_supply_suggestions(building_assessments: Dictionary, node_index: Dictionary, supplier_index: Dictionary, options: Dictionary) -> void:
	var world_units_per_tile := float(options.get("world_units_per_tile", 0.0))
	var catalog_variant = options.get("catalog_lookup", null)
	var catalog_lookup: Callable = catalog_variant if catalog_variant is Callable else Callable()

	for node_id_variant in building_assessments.keys():
		var node_id := String(node_id_variant)
		var assessment: Dictionary = building_assessments[node_id]
		var node: Dictionary = node_index.get(node_id, {})
		var consumer_pos := _node_position(node)
		for requirement_variant in _as_array(assessment.get("requirements", [])):
			var requirement: Dictionary = requirement_variant
			if String(requirement.get("state", "")) != REQUIREMENT_MISSING:
				continue
			var resource := StringName(str(requirement.get("resource", "")))
			var display_name := String(requirement.get("display_name", _format_resource_name(str(resource))))
			requirement["suggestion"] = _suggest_supply(resource, display_name, consumer_pos, node_id, supplier_index, world_units_per_tile, catalog_lookup)


# Tiered, deterministic "where is this missing resource?" suggestion:
#   rail (tap an existing unconnected rail) -> producer (route from a placed source) -> catalog hint.
static func _suggest_supply(resource: StringName, display_name: String, consumer_pos: Vector2, consumer_node_id: String, supplier_index: Dictionary, world_units_per_tile: float, catalog_lookup: Callable) -> Dictionary:
	var entry: Dictionary = supplier_index.get(resource, {})

	var best_rail := _nearest_rail(_as_array(entry.get("rails", [])), consumer_pos)
	if not best_rail.is_empty():
		var dist := _tiles_phrase(float(best_rail.get("distance", 0.0)), world_units_per_tile)
		var parts: Array[String] = ["Nearest %s: unconnected rail" % display_name]
		if dist != "":
			parts.append(dist)
		return {
			"tier": "rail",
			"resource": resource,
			"target_edge_id": String(best_rail.get("edge_id", "")),
			"text": " ".join(parts),
		}

	var best_producer := _nearest_producer(_as_array(entry.get("producers", [])), consumer_pos, consumer_node_id)
	if not best_producer.is_empty():
		var dist := _tiles_phrase(float(best_producer.get("distance", 0.0)), world_units_per_tile)
		var parts: Array[String] = ["Nearest %s: %s" % [display_name, String(best_producer.get("label", ""))]]
		if dist != "":
			parts.append(dist)
		parts.append("(not connected)")
		return {
			"tier": "producer",
			"resource": resource,
			"target_node_id": String(best_producer.get("node_id", "")),
			"text": " ".join(parts),
		}

	var text := "No %s source in this plan" % display_name
	if catalog_lookup.is_valid():
		var building_variant = catalog_lookup.call(resource)
		var building_name := String(building_variant) if building_variant != null else ""
		if building_name.strip_edges() != "":
			text += " (produced by %s)" % building_name
	return {
		"tier": "none",
		"resource": resource,
		"text": text,
	}


static func _nearest_rail(rails: Array, consumer_pos: Vector2) -> Dictionary:
	var best := {}
	var best_dist := 0.0
	for rail_variant in rails:
		if not (rail_variant is Dictionary):
			continue
		var rail: Dictionary = rail_variant
		var dist := _min_distance_to_positions(consumer_pos, _as_array(rail.get("positions", [])))
		if best.is_empty() or dist < best_dist - SUFFICIENCY_EPSILON or (absf(dist - best_dist) <= SUFFICIENCY_EPSILON and String(rail.get("edge_id", "")) < String(best.get("edge_id", ""))):
			best = rail.duplicate()
			best_dist = dist
	if not best.is_empty():
		best["distance"] = best_dist
	return best


static func _nearest_producer(producers: Array, consumer_pos: Vector2, exclude_node_id: String) -> Dictionary:
	var best := {}
	var best_dist := 0.0
	for producer_variant in producers:
		if not (producer_variant is Dictionary):
			continue
		var producer: Dictionary = producer_variant
		if String(producer.get("node_id", "")) == exclude_node_id:
			continue
		var position = producer.get("position", Vector2.ZERO)
		var dist := _manhattan(consumer_pos, position if position is Vector2 else Vector2.ZERO)
		if best.is_empty() or dist < best_dist - SUFFICIENCY_EPSILON or (absf(dist - best_dist) <= SUFFICIENCY_EPSILON and String(producer.get("node_id", "")) < String(best.get("node_id", ""))):
			best = producer.duplicate()
			best_dist = dist
	if not best.is_empty():
		best["distance"] = best_dist
	return best


static func _min_distance_to_positions(from: Vector2, positions: Array) -> float:
	var best := -1.0
	for position_variant in positions:
		if not (position_variant is Vector2):
			continue
		var dist := _manhattan(from, position_variant)
		if best < 0.0 or dist < best:
			best = dist
	return best if best >= 0.0 else 0.0


static func _manhattan(a: Vector2, b: Vector2) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y)


static func _node_position(node: Dictionary) -> Vector2:
	var position = node.get("position", null)
	if position is Vector2:
		return position
	if position is Array and (position as Array).size() >= 2:
		return Vector2(float(position[0]), float(position[1]))
	return Vector2.ZERO


static func _tiles_phrase(distance_world: float, world_units_per_tile: float) -> String:
	if world_units_per_tile <= 0.0:
		return ""
	var tiles := int(round(distance_world / world_units_per_tile))
	if tiles <= 1:
		return "(adjacent)"
	return "(~%d tiles away)" % tiles


static func _build_building_assessments(node_index: Dictionary, node_order: Array, incoming_edges: Dictionary, edge_supply: Dictionary, edge_delivered: Dictionary, has_simulation: bool) -> Dictionary:
	var assessments := {}
	for node_id_variant in node_order:
		var node_id := String(node_id_variant)
		var node: Dictionary = node_index.get(node_id, {})
		var requirements := _requirements_for_node(node)
		if requirements.is_empty():
			continue

		var port_summaries := _build_port_summaries(_as_array(incoming_edges.get(node_id, [])), edge_supply, requirements, edge_delivered)
		var assignment := _assign_requirements_to_ports(requirements, port_summaries, has_simulation)
		var assigned_requirements: Array = assignment.get("requirements", [])
		assessments[node_id] = {
			"id": node_id,
			"node_label": _node_label(node),
			"requirements": assigned_requirements,
			"missing_requirements": assignment.get("missing_requirements", []),
			"port_summaries": port_summaries,
			"has_shared_rail": _has_shared_port(port_summaries),
			"has_under_supply": _requirements_have_under_supply(assigned_requirements),
		}
	return assessments


static func _requirements_for_node(node: Dictionary) -> Array:
	var requirements: Array = []
	var demand_rates := _rate_map(node.get("inputs", {}))
	var ordered = node.get("input_requirements", [])
	if ordered is Array and not (ordered as Array).is_empty():
		for entry_variant in ordered:
			if not (entry_variant is Dictionary):
				continue
			var entry: Dictionary = entry_variant
			var resource := StringName(str(entry.get("resource", entry.get("id", ""))))
			if resource == StringName(""):
				continue
			requirements.append({
				"resource": resource,
				"display_name": String(entry.get("display_name", _format_resource_name(str(resource)))),
				"qty": float(entry.get("qty", entry.get("rate", 0.0))),
				"demand_rate": float(demand_rates.get(resource, 0.0)),
				"index": int(entry.get("index", requirements.size())),
			})
		return _sort_requirement_entries_by_index(requirements)

	for resource in _sorted_keys(demand_rates.keys()):
		requirements.append({
			"resource": resource,
			"display_name": _format_resource_name(str(resource)),
			"qty": float(demand_rates[resource]),
			"demand_rate": float(demand_rates[resource]),
			"index": requirements.size(),
		})
	return requirements


static func _build_port_summaries(incoming_edges: Array, edge_supply: Dictionary, requirements: Array, edge_delivered: Dictionary) -> Dictionary:
	var port_summaries := {}
	var required_resources := {}
	for requirement_variant in requirements:
		var requirement: Dictionary = requirement_variant
		required_resources[requirement.get("resource", StringName(""))] = true

	for edge_variant in incoming_edges:
		var edge: Dictionary = edge_variant
		var port := String(edge.get("to_port", ""))
		if not _is_input_like_port(port):
			continue

		var edge_id := String(edge.get("id", ""))
		var supply: Dictionary = edge_supply.get(edge_id, {})
		var summary: Dictionary = port_summaries.get(port, {
			"port": port,
			"edges": [],
			"resources": [],
			"resource_facts": {},
			"delivered_rates": {},
			"used_resources": [],
			"extra_resources": [],
			"is_shared": false,
		})

		var edges: Array = summary.get("edges", [])
		edges.append(edge_id)
		summary["edges"] = edges

		var facts: Dictionary = summary.get("resource_facts", {})
		_merge_supply_maps(facts, supply.get("resource_facts", {}))
		summary["resource_facts"] = facts
		summary["resources"] = _sorted_keys(facts.keys())
		summary["is_shared"] = (summary["resources"] as Array).size() > 1

		# Actual delivered rates arriving at this port, summed across its rails.
		var delivered_rates: Dictionary = summary.get("delivered_rates", {})
		var edge_delivered_map: Dictionary = edge_delivered.get(edge_id, {}) if edge_delivered.get(edge_id, {}) is Dictionary else {}
		for resource in edge_delivered_map.keys():
			delivered_rates[resource] = float(delivered_rates.get(resource, 0.0)) + float(edge_delivered_map[resource])
		summary["delivered_rates"] = delivered_rates

		port_summaries[port] = summary

	for port in port_summaries.keys():
		var summary: Dictionary = port_summaries[port]
		var extra: Array = []
		for resource in _as_array(summary.get("resources", [])):
			if not required_resources.has(resource):
				extra.append(resource)
		summary["extra_resources"] = extra
		port_summaries[port] = summary

	return port_summaries


static func _assign_requirements_to_ports(requirements: Array, port_summaries: Dictionary, has_simulation: bool) -> Dictionary:
	var assessed_requirements: Array = []
	var missing_requirements: Array = []
	var ports := _sorted_ports(port_summaries.keys())

	for requirement_variant in requirements:
		var requirement: Dictionary = requirement_variant
		var resource = requirement.get("resource", StringName(""))
		var candidates: Array = []
		for port in ports:
			var summary: Dictionary = port_summaries.get(port, {})
			var facts: Dictionary = summary.get("resource_facts", {})
			if facts.has(resource):
				candidates.append(port)

		var assessed := requirement.duplicate(true)
		if candidates.is_empty():
			assessed["state"] = REQUIREMENT_MISSING
			assessed["port"] = ""
			assessed["sufficiency"] = SUFFICIENCY_UNKNOWN
			assessed["supply_rate"] = 0.0
			assessed["supply_basis"] = SUPPLY_BASIS_ESTIMATED
			missing_requirements.append(assessed)
		else:
			var selected_port := String(candidates[0])
			var selected_summary: Dictionary = port_summaries.get(selected_port, {})
			var selected_facts: Dictionary = selected_summary.get("resource_facts", {})
			var supply_fact: Dictionary = selected_facts.get(resource, {}) if selected_facts.get(resource, {}) is Dictionary else {}
			var delivered_rates: Dictionary = selected_summary.get("delivered_rates", {})
			assessed["state"] = REQUIREMENT_SUPPLIED
			assessed["port"] = selected_port
			assessed["supply"] = supply_fact.duplicate(true)
			assessed["estimated_supply_rate"] = float(supply_fact.get("rate", 0.0))
			assessed["delivered_supply_rate"] = float(delivered_rates.get(resource, 0.0))

			var used: Array = selected_summary.get("used_resources", [])
			if not used.has(resource):
				used.append(resource)
			selected_summary["used_resources"] = _sorted_keys(used)
			port_summaries[selected_port] = selected_summary

		assessed_requirements.append(assessed)

	# Delivered rates are gated by the machine's whole recipe: a fully-missing input
	# idles the machine and drives every other input's delivered rate to zero. In that
	# case delivered numbers are uninformative, so fall back to estimated upstream supply.
	var has_missing := not missing_requirements.is_empty()
	var use_delivered := has_simulation and not has_missing
	for assessed_variant in assessed_requirements:
		var assessed: Dictionary = assessed_variant
		if String(assessed.get("state", "")) != REQUIREMENT_SUPPLIED:
			continue
		var demand_rate := float(assessed.get("demand_rate", 0.0))
		if use_delivered:
			var delivered_rate := float(assessed.get("delivered_supply_rate", 0.0))
			assessed["supply_rate"] = delivered_rate
			assessed["supply_basis"] = SUPPLY_BASIS_DELIVERED
			assessed["sufficiency"] = _classify_sufficiency(delivered_rate, demand_rate)
		else:
			var estimated_rate := float(assessed.get("estimated_supply_rate", 0.0))
			assessed["supply_rate"] = estimated_rate
			assessed["supply_basis"] = SUPPLY_BASIS_ESTIMATED
			assessed["sufficiency"] = _classify_sufficiency(estimated_rate, demand_rate)

	return {
		"requirements": assessed_requirements,
		"missing_requirements": missing_requirements,
	}


static func _classify_sufficiency(supply_rate: float, demand_rate: float) -> String:
	# Demand rate can be 0 when the recipe metadata lacks a rate; treat as unknown
	# rather than falsely flagging a shortfall.
	if demand_rate <= SUFFICIENCY_EPSILON:
		return SUFFICIENCY_UNKNOWN
	if supply_rate + SUFFICIENCY_EPSILON < demand_rate:
		return SUFFICIENCY_UNDER
	return SUFFICIENCY_SUFFICIENT


static func _requirements_have_under_supply(requirements: Array) -> bool:
	for requirement_variant in requirements:
		if not (requirement_variant is Dictionary):
			continue
		if String((requirement_variant as Dictionary).get("sufficiency", "")) == SUFFICIENCY_UNDER:
			return true
	return false


static func _has_shared_port(port_summaries: Dictionary) -> bool:
	for port in port_summaries.keys():
		var summary: Dictionary = port_summaries[port]
		if bool(summary.get("is_shared", false)):
			return true
	return false


static func _apply_building_assessment(building: Node2D, assessment: Dictionary) -> void:
	var chips := _get_input_chips(building)
	if chips.is_empty():
		return

	_ensure_chip_home_data(building, chips)
	for chip_variant in chips:
		_restore_chip_home(chip_variant)

	var requirements := _sort_requirement_entries_by_index(_as_array(assessment.get("requirements", [])))
	var port_summaries: Dictionary = assessment.get("port_summaries", {})
	var chip_assignments := _assign_chips_to_requirements(chips, requirements)

	for assignment_variant in chip_assignments:
		var assignment: Dictionary = assignment_variant
		var chip: Dictionary = assignment.get("chip", {})
		var requirement: Dictionary = assignment.get("requirement", {})
		var port := String(requirement.get("port", ""))
		var summary: Dictionary = port_summaries.get(port, {})
		_apply_requirement_to_chip(chip, requirement, summary)

	var assigned_chips := {}
	for assignment_variant in chip_assignments:
		var assignment: Dictionary = assignment_variant
		var chip: Dictionary = assignment.get("chip", {})
		var box := chip.get("box") as ColorRect
		if box != null:
			assigned_chips[box.get_instance_id()] = true

	for chip_variant in chips:
		var chip: Dictionary = chip_variant
		var box := chip.get("box") as ColorRect
		if box == null or assigned_chips.has(box.get_instance_id()):
			continue
		_apply_unused_chip(chip)


static func _assign_chips_to_requirements(chips: Array, requirements: Array) -> Array:
	var assignments: Array = []
	var sorted_requirements := _sort_requirement_entries_by_index(requirements)
	var assignment_count = mini(chips.size(), sorted_requirements.size())
	for i in range(assignment_count):
		var chip: Dictionary = chips[i]
		var requirement: Dictionary = sorted_requirements[i]
		assignments.append({
			"chip": chip,
			"requirement": requirement,
		})
	return assignments


static func _apply_requirement_to_chip(chip: Dictionary, requirement: Dictionary, port_summary: Dictionary) -> void:
	var box := chip.get("box") as ColorRect
	var label := chip.get("label") as Label
	if box == null:
		return

	var state := String(requirement.get("state", REQUIREMENT_MISSING))
	var tooltip := _build_requirement_tooltip(requirement, port_summary)
	var color := COLOR_MISSING
	if state == REQUIREMENT_SUPPLIED:
		if String(requirement.get("sufficiency", "")) == SUFFICIENCY_UNDER:
			color = COLOR_UNDER_SUPPLIED
		elif bool(port_summary.get("is_shared", false)):
			color = COLOR_SHARED
		else:
			color = COLOR_SUPPLIED

	box.color = color
	box.tooltip_text = tooltip
	box.set_meta(META_OVERRIDE_ACTIVE, true)
	if label != null:
		label.text = _format_quantity(float(requirement.get("qty", 0.0)))
		label.tooltip_text = tooltip


static func _apply_unused_chip(chip: Dictionary) -> void:
	var box := chip.get("box") as ColorRect
	var label := chip.get("label") as Label
	if box == null:
		return
	_restore_chip_home(chip)
	box.color = COLOR_UNUSED
	box.tooltip_text = "Unused"
	box.set_meta(META_OVERRIDE_ACTIVE, true)
	if label != null:
		label.text = ""
		label.tooltip_text = "Unused"


static func _clear_building_intelligence(building: Node2D) -> void:
	for chip in _get_input_chips(building):
		_restore_chip_home(chip)
		var box := chip.get("box") as ColorRect
		if box != null:
			box.set_meta(META_OVERRIDE_ACTIVE, false)


static func _get_input_chips(building: Node2D) -> Array:
	var chips: Array = []
	if building == null:
		return chips

	for child in building.get_children():
		if not (child is ColorRect):
			continue
		var box := child as ColorRect
		var index := _input_chip_index(box.name)
		if index <= 0:
			continue
		chips.append({
			"index": index,
			"box": box,
			"label": _find_first_label(box),
		})

	chips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("index", 0)) < int(b.get("index", 0))
	)
	return chips


static func _find_first_label(node: Node) -> Label:
	if node == null:
		return null
	for child in node.get_children():
		if child is Label:
			return child as Label
		var nested := _find_first_label(child)
		if nested != null:
			return nested
	return null


static func _ensure_chip_home_data(building: Node2D, chips: Array) -> void:
	var layout_key := _building_layout_key(building)
	for chip_variant in chips:
		var chip: Dictionary = chip_variant
		var box := chip.get("box") as ColorRect
		if box == null:
			continue
		var known_key := String(box.get_meta(META_LAYOUT_KEY, ""))
		if not box.has_meta(META_HOME_POSITION) or known_key != layout_key:
			box.set_meta(META_HOME_POSITION, box.position)
			box.set_meta(META_HOME_COLOR, box.color)
			box.set_meta(META_LAYOUT_KEY, layout_key)


static func _restore_chip_home(chip: Dictionary) -> void:
	var box := chip.get("box") as ColorRect
	if box == null:
		return
	if box.has_meta(META_HOME_POSITION):
		var home_position = box.get_meta(META_HOME_POSITION)
		if home_position is Vector2:
			box.position = home_position
	if box.has_meta(META_HOME_COLOR):
		var home_color = box.get_meta(META_HOME_COLOR)
		if home_color is Color:
			box.color = home_color


static func _build_requirement_tooltip(requirement: Dictionary, port_summary: Dictionary) -> String:
	var display_name := String(requirement.get("display_name", _format_resource_name(str(requirement.get("resource", "")))))
	var qty_text := _format_quantity(float(requirement.get("qty", 0.0)))
	var state := String(requirement.get("state", REQUIREMENT_MISSING))
	var lines: Array[String] = ["%s x%s" % [display_name, qty_text]]

	if state == REQUIREMENT_SUPPLIED:
		var port := String(requirement.get("port", ""))
		lines.append("Supplied by %s" % _format_port_name(port))
		var demand_rate := float(requirement.get("demand_rate", 0.0))
		if demand_rate > SUFFICIENCY_EPSILON:
			var supply_rate := float(requirement.get("supply_rate", 0.0))
			var basis := String(requirement.get("supply_basis", SUPPLY_BASIS_ESTIMATED))
			# "Delivered" is measured/confident; "Estimated supply" is inferred upstream availability
			# (used when actual flow can't be measured, e.g. the machine is idle on another input).
			var basis_label := "Delivered" if basis == SUPPLY_BASIS_DELIVERED else "Estimated supply"
			lines.append("%s: %s / %s upm needed" % [basis_label, _format_quantity(supply_rate), _format_quantity(demand_rate)])
			if String(requirement.get("sufficiency", "")) == SUFFICIENCY_UNDER:
				lines.append("Under-supplied by %s upm" % _format_quantity(demand_rate - supply_rate))
			if basis == SUPPLY_BASIS_ESTIMATED:
				lines.append("Upstream estimate — actual flow not measured")
		if bool(port_summary.get("is_shared", false)):
			lines.append("Shared rail: %s" % _join_resource_names(_as_array(port_summary.get("resources", [])), port_summary.get("resource_facts", {})))
		var supply: Dictionary = requirement.get("supply", {})
		var origins := _join_origin_labels(_as_array(supply.get("origins", [])))
		if origins != "":
			lines.append("Origins: %s" % origins)
		var extra := _as_array(port_summary.get("extra_resources", []))
		if not extra.is_empty():
			lines.append("Available but unused: %s" % _join_resource_names(extra, port_summary.get("resource_facts", {})))
	else:
		lines.append("Missing from connected rails")
		var connected := _join_resource_names(_as_array(port_summary.get("resources", [])), port_summary.get("resource_facts", {}))
		if connected != "":
			lines.append("Connected supply: %s" % connected)
		var suggestion = requirement.get("suggestion", {})
		if suggestion is Dictionary:
			var suggestion_text := String((suggestion as Dictionary).get("text", ""))
			if suggestion_text != "":
				lines.append(suggestion_text)

	return "\n".join(lines)


static func _node_passes_through(node: Dictionary) -> bool:
	if bool(node.get("pass_through", false)):
		return true
	var kind := _node_kind(node)
	return kind == NODE_KIND_JUNCTION or kind == NODE_KIND_SUPPORT or kind == NODE_KIND_ROUTER or kind == NODE_KIND_STORAGE or kind == "rail_support"


static func _node_kind(node: Dictionary) -> String:
	return String(node.get("kind", NODE_KIND_MACHINE)).strip_edges().to_lower()


static func _node_label(node: Dictionary) -> String:
	var label := String(node.get("label", ""))
	if label.strip_edges() != "":
		return label
	var name := String(node.get("name", ""))
	if name.strip_edges() != "":
		return name
	return String(node.get("id", "Unknown"))


static func _rate_map(value) -> Dictionary:
	var result := {}
	if not (value is Dictionary):
		return result
	for resource in value.keys():
		var amount := float(value[resource])
		if amount > 0.0001:
			result[StringName(str(resource))] = amount
	return result


static func _resource_display_names_from_stack_summaries(value) -> Dictionary:
	var names := {}
	for entry_variant in _as_array(value):
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var resource := StringName(str(entry.get("resource", entry.get("id", ""))))
		if resource == StringName(""):
			continue
		names[resource] = String(entry.get("display_name", _format_resource_name(str(resource))))
	return names


static func _as_array(value) -> Array:
	return value if value is Array else []


static func _sorted_keys(keys) -> Array:
	var values: Array = []
	for key in keys:
		values.append(key)
	values.sort_custom(func(a, b) -> bool:
		return String(a) < String(b)
	)
	return values


static func _sorted_ports(ports) -> Array:
	var values: Array = []
	for port in ports:
		values.append(String(port))
	values.sort_custom(func(a: String, b: String) -> bool:
		var index_a := _port_index(a)
		var index_b := _port_index(b)
		if index_a != index_b:
			return index_a < index_b
		return a < b
	)
	return values


static func _sort_requirement_entries_by_index(requirements: Array) -> Array:
	var sorted := requirements.duplicate(true)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var index_a := int(a.get("index", 0))
		var index_b := int(b.get("index", 0))
		if index_a != index_b:
			return index_a < index_b
		return String(a.get("resource", "")) < String(b.get("resource", ""))
	)
	return sorted


static func _is_input_like_port(port: String) -> bool:
	var port_name := _format_port_name(port)
	return port_name.begins_with("Input") or port_name.begins_with("Universal")


static func _format_port_name(port: String) -> String:
	var port_name := port.get_file().strip_edges()
	return port_name if port_name != "" else port.strip_edges()


static func _port_index(port: String) -> int:
	var port_name := _format_port_name(port)
	var parts := port_name.split(" ")
	if parts.size() > 1:
		var last := String(parts[parts.size() - 1])
		if last.is_valid_int():
			return int(last)
	var digits := ""
	for i in range(port_name.length()):
		var character := port_name.substr(i, 1)
		if character.is_valid_int():
			digits += character
	return int(digits) if digits.is_valid_int() else 9999


static func _input_chip_index(node_name: String) -> int:
	var name := node_name.to_lower()
	if not name.begins_with("input") or not name.ends_with("box"):
		return -1
	var middle := name.trim_prefix("input").trim_suffix("box")
	# Single-input buildings (e.g. Smelter) name their chip "InputBox" with no
	# index digit; treat the bare form as the first input chip.
	if middle == "":
		return 1
	return int(middle) if middle.is_valid_int() else -1


static func _building_layout_key(building: Node2D) -> String:
	var alternate := "false"
	if building != null and "is_alternate" in building:
		alternate = str(bool(building.get("is_alternate")))
	var rotated_tick := "0"
	if building != null and "rotatedTick" in building:
		rotated_tick = str(int(building.get("rotatedTick")))
	return "%s|%s" % [alternate, rotated_tick]


static func _join_resource_names(resources: Array, facts_by_resource) -> String:
	if resources.is_empty():
		return ""
	var facts: Dictionary = facts_by_resource if facts_by_resource is Dictionary else {}
	var names: Array[String] = []
	for resource in resources:
		var fact: Dictionary = facts.get(resource, {})
		names.append(String(fact.get("display_name", _format_resource_name(str(resource)))))
	return ", ".join(names)


static func _join_origin_labels(origins: Array) -> String:
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


static func _format_quantity(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.2f" % value


static func _format_resource_name(value: String) -> String:
	return value.strip_edges().replace("_", " ").replace("-", " ").capitalize()
