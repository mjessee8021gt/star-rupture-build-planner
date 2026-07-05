extends RefCounted
class_name FlowSimulator

const NODE_KIND_SOURCE := "source"
const NODE_KIND_MACHINE := "machine"
const NODE_KIND_STORAGE := "storage"
const NODE_KIND_JUNCTION := "junction"
const NODE_KIND_SUPPORT := "support"
const NODE_KIND_ROUTER := "router"

const WARNING_LOOP_DETECTED := "loop_detected"

const KEY_NODES := "nodes"
const KEY_EDGES := "edges"
const KEY_STATE := "state"
const KEY_STORAGE_INVENTORY := "storage_inventory"

const RESOURCE_EPSILON := 0.0001
const DEFAULT_DELTA_SECONDS := 1.0
const UNLIMITED_CAPACITY_UPM := -1.0
const EFFECTIVE_INFINITY_UPM := 1000000000000.0


func simulate(graph: Dictionary, delta_seconds := DEFAULT_DELTA_SECONDS, previous_state: Dictionary = {}) -> Dictionary:
	var normalized_delta := maxf(float(delta_seconds), RESOURCE_EPSILON)
	var raw_nodes = graph.get(KEY_NODES, [])
	var raw_edges = graph.get(KEY_EDGES, [])
	var nodes: Array = raw_nodes if raw_nodes is Array else []
	var edges: Array = raw_edges if raw_edges is Array else []

	var node_index := _build_node_index(nodes)
	var node_ids := _get_node_ids(nodes, node_index)
	var edge_entries := _build_edge_entries(edges, node_index)
	var adjacency := _build_adjacency(node_ids, edge_entries)
	var warnings := _detect_loop_warnings(node_ids, adjacency)
	var order := _topological_order(node_ids, adjacency)
	var inventories := _prepare_storage_inventory(node_ids, node_index, previous_state)

	var node_incoming := {}
	var node_results := {}
	var edge_results := {}
	for node_id in node_ids:
		node_incoming[node_id] = {}

	for node_id in order:
		var node: Dictionary = node_index.get(node_id, {})
		var kind := _get_node_kind(node)
		var incoming := _duplicate_rate_map(node_incoming.get(node_id, {}))
		var resolved := _resolve_node_output(node_id, node, kind, incoming, inventories, normalized_delta)
		var available_out: Dictionary = resolved.get("available_out", {})
		var outgoing_edges: Array = adjacency.get(node_id, [])
		var outgoing_allocation := _allocate_outgoing_flow(available_out, outgoing_edges, node_index, node_incoming)
		var edge_flows: Dictionary = outgoing_allocation.get("edge_flows", {})
		var actual_outgoing := {}
		var blocked_outgoing: Dictionary = outgoing_allocation.get("unrouted_by_resource", {})

		for edge in outgoing_edges:
			var edge_id := String(edge.get("id", ""))
			var to_id := String(edge.get("to", ""))
			var clamped: Dictionary = edge_flows.get(edge_id, {})
			var delivered: Dictionary = clamped.get("delivered_by_resource", {})
			var blocked: Dictionary = clamped.get("blocked_by_resource", {})

			if not node_incoming.has(to_id):
				node_incoming[to_id] = {}
			_merge_rates(node_incoming[to_id], delivered)
			_merge_rates(actual_outgoing, delivered)
			_merge_rates(blocked_outgoing, blocked)

			edge_results[edge_id] = _build_edge_result(edge, clamped)

		if _is_storage_kind(kind):
			var current_inventory: Dictionary = inventories.get(node_id, {})
			inventories[node_id] = _update_storage_inventory(
				node,
				current_inventory,
				incoming,
				actual_outgoing,
				normalized_delta
			)

		node_results[node_id] = _build_node_result(
			node_id,
			kind,
			incoming,
			actual_outgoing,
			blocked_outgoing,
			resolved,
			inventories.get(node_id, {})
		)

	return {
		"delta_seconds": normalized_delta,
		"nodes": node_results,
		"edges": edge_results,
		"warnings": warnings,
		KEY_STATE: {
			KEY_STORAGE_INVENTORY: inventories
		}
	}


func _build_node_index(nodes: Array) -> Dictionary:
	var node_index := {}
	for i in range(nodes.size()):
		var node_variant = nodes[i]
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := _get_node_id(node, i)
		if node_id == "":
			continue
		node_index[node_id] = node
	return node_index


func _get_node_ids(nodes: Array, node_index: Dictionary) -> Array:
	var node_ids: Array = []
	for i in range(nodes.size()):
		var node_variant = nodes[i]
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := _get_node_id(node, i)
		if node_id == "" or not node_index.has(node_id):
			continue
		if not node_ids.has(node_id):
			node_ids.append(node_id)
	return node_ids


func _build_edge_entries(edges: Array, node_index: Dictionary) -> Array:
	var edge_entries: Array = []
	for i in range(edges.size()):
		var edge_variant = edges[i]
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if not node_index.has(from_id) or not node_index.has(to_id):
			continue

		edge_entries.append({
			"id": _get_edge_id(edge, i),
			"from": from_id,
			"to": to_id,
			"capacity_upm": _get_edge_capacity(edge),
			"data": edge
		})
	return edge_entries


func _build_adjacency(node_ids: Array, edge_entries: Array) -> Dictionary:
	var adjacency := {}
	for node_id in node_ids:
		adjacency[node_id] = []
	for edge in edge_entries:
		var from_id := String(edge.get("from", ""))
		if not adjacency.has(from_id):
			adjacency[from_id] = []
		adjacency[from_id].append(edge)
	return adjacency


func _prepare_storage_inventory(node_ids: Array, node_index: Dictionary, previous_state: Dictionary) -> Dictionary:
	var inventories := {}
	var previous_inventory := {}
	var state_inventory = previous_state.get(KEY_STORAGE_INVENTORY, previous_state.get(KEY_STATE, {}).get(KEY_STORAGE_INVENTORY, {}))
	if state_inventory is Dictionary:
		previous_inventory = state_inventory

	for node_id in node_ids:
		var node: Dictionary = node_index.get(node_id, {})
		var kind := _get_node_kind(node)
		if not _is_storage_kind(kind):
			continue

		if previous_inventory.has(node_id) and previous_inventory[node_id] is Dictionary:
			inventories[node_id] = _dict_to_rate_map(previous_inventory[node_id])
		else:
			inventories[node_id] = _dict_to_rate_map(node.get("inventory", node.get("initial_inventory", {})))
	return inventories


func _resolve_node_output(node_id: String, node: Dictionary, kind: String, incoming: Dictionary, inventories: Dictionary, delta_seconds: float) -> Dictionary:
	var consumed := {}
	var produced := {}
	var available_out := {}
	var starved := {}
	var production_scale := 1.0

	if _is_storage_kind(kind):
		var current_inventory: Dictionary = inventories.get(node_id, {})
		available_out = _add_rate_maps(incoming, _inventory_to_rate_map(current_inventory, delta_seconds))
	elif _node_passes_through(node, kind):
		available_out = incoming.duplicate(true)
	else:
		var required_inputs := _get_node_inputs(node)
		var configured_outputs := _get_node_outputs(node)
		production_scale = _compute_production_scale(required_inputs, incoming)
		consumed = _multiply_rates(required_inputs, production_scale)
		produced = _multiply_rates(configured_outputs, production_scale)
		available_out = produced.duplicate(true)
		starved = _get_starved_rates(required_inputs, incoming)

	return {
		"available_out": available_out,
		"consumed_by_resource": consumed,
		"produced_by_resource": produced,
		"production_scale": production_scale,
		"starved_by_resource": starved
	}


func _compute_production_scale(required_inputs: Dictionary, incoming: Dictionary) -> float:
	if required_inputs.is_empty():
		return 1.0

	var scale := 1.0
	for resource in required_inputs.keys():
		var required := float(required_inputs[resource])
		if required <= RESOURCE_EPSILON:
			continue
		var available := float(incoming.get(resource, 0.0))
		if available <= RESOURCE_EPSILON:
			return 0.0
		scale = minf(scale, clampf(available / required, 0.0, 1.0))
	return scale


func _get_starved_rates(required_inputs: Dictionary, incoming: Dictionary) -> Dictionary:
	var starved := {}
	for resource in required_inputs.keys():
		var required := float(required_inputs[resource])
		var available := float(incoming.get(resource, 0.0))
		var deficit = required - available
		if deficit > RESOURCE_EPSILON:
			starved[resource] = deficit
	return starved


func _distribute_evenly(available_out: Dictionary, outgoing_count: int) -> Dictionary:
	if outgoing_count <= 0:
		return {}

	var requested := {}
	for resource in available_out.keys():
		var rate := float(available_out[resource])
		if rate > RESOURCE_EPSILON:
			requested[resource] = rate / float(outgoing_count)
	return requested


func _allocate_outgoing_flow(available_out: Dictionary, outgoing_edges: Array, node_index: Dictionary, node_incoming: Dictionary) -> Dictionary:
	var edge_flows := {}
	var unrouted_by_resource := {}
	if outgoing_edges.is_empty():
		return {
			"edge_flows": edge_flows,
			"unrouted_by_resource": _positive_rate_map(available_out)
		}
	if outgoing_edges.size() == 1:
		return _allocate_single_edge_flow(available_out, outgoing_edges[0], node_index, node_incoming)

	var edge_remaining_capacity := {}
	var destination_allocated := {}

	for edge in outgoing_edges:
		var edge_id := String(edge.get("id", ""))
		var capacity := float(edge.get("capacity_upm", UNLIMITED_CAPACITY_UPM))
		edge_remaining_capacity[edge_id] = EFFECTIVE_INFINITY_UPM if _is_unlimited_capacity(capacity) else maxf(capacity, 0.0)
		edge_flows[edge_id] = {
			"requested_by_resource": {},
			"delivered_by_resource": {},
			"capacity_upm": capacity,
		}

	for resource in available_out.keys():
		var requested_rate := maxf(float(available_out[resource]), 0.0)
		if requested_rate <= RESOURCE_EPSILON:
			continue

		var resource_allocation := _allocate_resource_across_edges(
			resource,
			requested_rate,
			outgoing_edges,
			node_index,
			node_incoming,
			edge_remaining_capacity,
			destination_allocated
		)
		var delivered_by_edge: Dictionary = resource_allocation.get("delivered_by_edge", {})
		var pressure_by_edge: Dictionary = resource_allocation.get("pressure_by_edge", {})

		for edge_id in delivered_by_edge.keys():
			var delivered := float(delivered_by_edge[edge_id])
			if delivered <= RESOURCE_EPSILON:
				continue
			var edge_flow: Dictionary = edge_flows.get(edge_id, {})
			var delivered_map: Dictionary = edge_flow.get("delivered_by_resource", {})
			var requested_map: Dictionary = edge_flow.get("requested_by_resource", {})
			delivered_map[resource] = float(delivered_map.get(resource, 0.0)) + delivered
			requested_map[resource] = float(requested_map.get(resource, 0.0)) + delivered
			edge_flow["delivered_by_resource"] = delivered_map
			edge_flow["requested_by_resource"] = requested_map
			edge_flows[edge_id] = edge_flow
			edge_remaining_capacity[edge_id] = maxf(float(edge_remaining_capacity.get(edge_id, 0.0)) - delivered, 0.0)
			_add_destination_allocated(destination_allocated, outgoing_edges, String(edge_id), resource, delivered)

		for edge_id in pressure_by_edge.keys():
			var pressure := float(pressure_by_edge[edge_id])
			if pressure <= RESOURCE_EPSILON:
				continue
			var edge_flow: Dictionary = edge_flows.get(edge_id, {})
			var requested_map: Dictionary = edge_flow.get("requested_by_resource", {})
			requested_map[resource] = float(requested_map.get(resource, 0.0)) + pressure
			edge_flow["requested_by_resource"] = requested_map
			edge_flows[edge_id] = edge_flow

		var unrouted := float(resource_allocation.get("unrouted_upm", 0.0))
		if unrouted > RESOURCE_EPSILON:
			unrouted_by_resource[resource] = float(unrouted_by_resource.get(resource, 0.0)) + unrouted

	for edge in outgoing_edges:
		var edge_id := String(edge.get("id", ""))
		var edge_flow: Dictionary = edge_flows.get(edge_id, {})
		var capacity := float(edge_flow.get("capacity_upm", edge.get("capacity_upm", UNLIMITED_CAPACITY_UPM)))
		var requested_by_resource: Dictionary = edge_flow.get("requested_by_resource", {})
		var delivered_by_resource: Dictionary = edge_flow.get("delivered_by_resource", {})
		edge_flows[edge_id] = _make_edge_flow_result(requested_by_resource, delivered_by_resource, capacity)

	return {
		"edge_flows": edge_flows,
		"unrouted_by_resource": unrouted_by_resource
	}


func _allocate_single_edge_flow(available_out: Dictionary, edge: Dictionary, node_index: Dictionary, node_incoming: Dictionary) -> Dictionary:
	var edge_id := String(edge.get("id", ""))
	var capacity := float(edge.get("capacity_upm", UNLIMITED_CAPACITY_UPM))
	var accepted_by_resource := {}
	var unrouted_by_resource := {}
	var destination_allocated := {}

	for resource in available_out.keys():
		var source_rate := maxf(float(available_out[resource]), 0.0)
		if source_rate <= RESOURCE_EPSILON:
			continue
		var acceptance := _get_edge_resource_acceptance(edge, resource, node_index, node_incoming, destination_allocated)
		var accepted = minf(source_rate, acceptance)
		if accepted > RESOURCE_EPSILON:
			accepted_by_resource[resource] = accepted
		var demand_limited = source_rate - accepted
		if demand_limited > RESOURCE_EPSILON:
			unrouted_by_resource[resource] = demand_limited

	var delivered_by_resource := accepted_by_resource.duplicate(true)
	var accepted_total := _sum_rates(accepted_by_resource)
	if not _is_unlimited_capacity(capacity) and accepted_total > capacity + RESOURCE_EPSILON:
		delivered_by_resource = _multiply_rates(accepted_by_resource, capacity / accepted_total)

	return {
		"edge_flows": {
			edge_id: _make_edge_flow_result(accepted_by_resource, delivered_by_resource, capacity)
		},
		"unrouted_by_resource": unrouted_by_resource
	}


func _allocate_resource_across_edges(resource, requested_rate: float, outgoing_edges: Array, node_index: Dictionary, node_incoming: Dictionary, edge_remaining_capacity: Dictionary, destination_allocated: Dictionary) -> Dictionary:
	var edge_caps := {}
	var active_ids: Array = []

	for edge in outgoing_edges:
		var edge_id := String(edge.get("id", ""))
		var edge_capacity_remaining := float(edge_remaining_capacity.get(edge_id, 0.0))
		var destination_acceptance := _get_edge_resource_acceptance(edge, resource, node_index, node_incoming, destination_allocated)
		var cap = minf(edge_capacity_remaining, destination_acceptance)
		if cap > RESOURCE_EPSILON:
			edge_caps[edge_id] = cap
			active_ids.append(edge_id)

	var delivered_by_edge := _allocate_scalar_even_with_caps(requested_rate, active_ids, edge_caps)
	var delivered_total := 0.0
	for edge_id in delivered_by_edge.keys():
		delivered_total += float(delivered_by_edge[edge_id])

	var unrouted := maxf(requested_rate - delivered_total, 0.0)
	var pressure_by_edge := {}
	var demand_unrouted := unrouted
	if unrouted > RESOURCE_EPSILON:
		var pressure_edges := _get_capacity_pressure_edge_ids(resource, outgoing_edges, node_index, node_incoming, destination_allocated, edge_remaining_capacity, delivered_by_edge)
		if not pressure_edges.is_empty():
			var pressure_share := unrouted / float(pressure_edges.size())
			for edge_id in pressure_edges:
				pressure_by_edge[edge_id] = pressure_share
			demand_unrouted = 0.0

	return {
		"delivered_by_edge": delivered_by_edge,
		"pressure_by_edge": pressure_by_edge,
		"unrouted_upm": demand_unrouted,
	}


func _allocate_scalar_even_with_caps(requested_total: float, active_ids: Array, caps: Dictionary) -> Dictionary:
	var delivered := {}
	var remaining := maxf(requested_total, 0.0)
	var active := active_ids.duplicate()

	for edge_id in active:
		delivered[edge_id] = 0.0

	while remaining > RESOURCE_EPSILON and not active.is_empty():
		var share := remaining / float(active.size())
		var saturated_ids: Array = []
		var consumed_by_saturated := 0.0

		for edge_id in active:
			var cap := float(caps.get(edge_id, 0.0))
			if share >= cap - RESOURCE_EPSILON:
				delivered[edge_id] = float(delivered.get(edge_id, 0.0)) + cap
				consumed_by_saturated += cap
				saturated_ids.append(edge_id)

		if saturated_ids.is_empty():
			for edge_id in active:
				delivered[edge_id] = float(delivered.get(edge_id, 0.0)) + share
			break

		for edge_id in saturated_ids:
			active.erase(edge_id)
		remaining = maxf(remaining - consumed_by_saturated, 0.0)

	return delivered


func _get_edge_resource_acceptance(edge: Dictionary, resource, node_index: Dictionary, node_incoming: Dictionary, destination_allocated: Dictionary) -> float:
	var to_id := String(edge.get("to", ""))
	var to_node: Dictionary = node_index.get(to_id, {})
	var kind := _get_node_kind(to_node)
	if _node_accepts_unbounded_input(to_node, kind):
		return EFFECTIVE_INFINITY_UPM

	var required_inputs := _get_node_inputs(to_node)
	if required_inputs.is_empty():
		return EFFECTIVE_INFINITY_UPM
	if not required_inputs.has(resource):
		return 0.0

	var incoming: Dictionary = node_incoming.get(to_id, {})
	var allocated: Dictionary = destination_allocated.get(to_id, {})
	var already_incoming := float(incoming.get(resource, 0.0)) + float(allocated.get(resource, 0.0))
	return maxf(float(required_inputs.get(resource, 0.0)) - already_incoming, 0.0)


func _get_capacity_pressure_edge_ids(resource, outgoing_edges: Array, node_index: Dictionary, node_incoming: Dictionary, destination_allocated: Dictionary, edge_remaining_capacity: Dictionary, delivered_by_edge: Dictionary) -> Array:
	var pressure_edges: Array = []
	for edge in outgoing_edges:
		var edge_id := String(edge.get("id", ""))
		var delivered := float(delivered_by_edge.get(edge_id, 0.0))
		if float(edge_remaining_capacity.get(edge_id, 0.0)) - delivered > RESOURCE_EPSILON:
			continue
		var destination_acceptance_before := _get_edge_resource_acceptance(edge, resource, node_index, node_incoming, destination_allocated)
		if destination_acceptance_before - delivered <= RESOURCE_EPSILON:
			continue
		pressure_edges.append(edge_id)
	return pressure_edges


func _add_destination_allocated(destination_allocated: Dictionary, outgoing_edges: Array, edge_id: String, resource, amount: float) -> void:
	var to_id := ""
	for edge in outgoing_edges:
		if String(edge.get("id", "")) == edge_id:
			to_id = String(edge.get("to", ""))
			break
	if to_id == "":
		return
	var allocated: Dictionary = destination_allocated.get(to_id, {})
	allocated[resource] = float(allocated.get(resource, 0.0)) + amount
	destination_allocated[to_id] = allocated


func _node_accepts_unbounded_input(node: Dictionary, kind: String) -> bool:
	return _is_storage_kind(kind) or _node_passes_through(node, kind) or kind == NODE_KIND_SOURCE


func _allocate_total_flow_across_edges(requested_total: float, outgoing_edges: Array) -> Dictionary:
	var requested_by_edge := {}
	var delivered_by_edge := {}
	var capacities := {}
	var active_ids: Array = []

	for edge in outgoing_edges:
		var edge_id := String(edge.get("id", ""))
		var capacity := float(edge.get("capacity_upm", UNLIMITED_CAPACITY_UPM))
		requested_by_edge[edge_id] = 0.0
		delivered_by_edge[edge_id] = 0.0
		capacities[edge_id] = capacity
		active_ids.append(edge_id)

	var remaining_total := maxf(requested_total, 0.0)
	while remaining_total > RESOURCE_EPSILON and not active_ids.is_empty():
		var share := remaining_total / float(active_ids.size())
		var saturated_ids: Array = []
		var consumed_by_saturated := 0.0

		for edge_id in active_ids:
			var capacity := float(capacities.get(edge_id, UNLIMITED_CAPACITY_UPM))
			if _is_unlimited_capacity(capacity):
				continue
			if share >= capacity - RESOURCE_EPSILON:
				delivered_by_edge[edge_id] = capacity
				consumed_by_saturated += capacity
				saturated_ids.append(edge_id)

		if saturated_ids.is_empty():
			for edge_id in active_ids:
				delivered_by_edge[edge_id] = share
			remaining_total = 0.0
			break

		for edge_id in saturated_ids:
			active_ids.erase(edge_id)
		remaining_total = maxf(remaining_total - consumed_by_saturated, 0.0)

	var delivered_total := 0.0
	for edge_id in delivered_by_edge.keys():
		delivered_total += float(delivered_by_edge[edge_id])
		requested_by_edge[edge_id] = delivered_by_edge[edge_id]

	var blocked_total := maxf(requested_total - delivered_total, 0.0)
	if blocked_total > RESOURCE_EPSILON:
		var pressure_ids := _get_saturated_edge_ids(delivered_by_edge, capacities, outgoing_edges)
		if pressure_ids.is_empty():
			pressure_ids = requested_by_edge.keys()
		var blocked_share := blocked_total / float(maxi(pressure_ids.size(), 1))
		for edge_id in pressure_ids:
			requested_by_edge[edge_id] = float(requested_by_edge.get(edge_id, 0.0)) + blocked_share

	return {
		"requested_by_edge": requested_by_edge,
		"delivered_by_edge": delivered_by_edge,
		"blocked_upm": blocked_total,
	}


func _get_saturated_edge_ids(delivered_by_edge: Dictionary, capacities: Dictionary, outgoing_edges: Array) -> Array:
	var saturated_ids: Array = []
	for edge in outgoing_edges:
		var edge_id := String(edge.get("id", ""))
		var capacity := float(capacities.get(edge_id, UNLIMITED_CAPACITY_UPM))
		if _is_unlimited_capacity(capacity):
			continue
		if float(delivered_by_edge.get(edge_id, 0.0)) >= capacity - RESOURCE_EPSILON:
			saturated_ids.append(edge_id)
	return saturated_ids


func _rate_map_for_total(source_rates: Dictionary, target_total: float, source_total: float) -> Dictionary:
	if source_total <= RESOURCE_EPSILON or target_total <= RESOURCE_EPSILON:
		return {}
	return _multiply_rates(source_rates, target_total / source_total)


func _make_edge_flow_result(requested_by_resource: Dictionary, delivered_by_resource: Dictionary, capacity_upm: float) -> Dictionary:
	var requested := _positive_rate_map(requested_by_resource)
	var delivered := _positive_rate_map(delivered_by_resource)
	var requested_total := _sum_rates(requested)
	var used_total := _sum_rates(delivered)
	var blocked := _subtract_rate_maps(requested, delivered)
	var blocked_total := _sum_rates(blocked)
	var unlimited := _is_unlimited_capacity(capacity_upm)

	return {
		"requested_by_resource": requested,
		"delivered_by_resource": delivered,
		"blocked_by_resource": blocked,
		"requested_upm": requested_total,
		"used_upm": used_total,
		"blocked_upm": blocked_total,
		"available_upm": maxf(capacity_upm - used_total, 0.0) if not unlimited else UNLIMITED_CAPACITY_UPM,
		"saturation": clampf(used_total / capacity_upm, 0.0, 1.0) if not unlimited and capacity_upm > RESOURCE_EPSILON else 0.0,
		"unlimited": unlimited
	}


func _clamp_edge_flow(requested_by_resource: Dictionary, capacity_upm: float) -> Dictionary:
	var requested := _positive_rate_map(requested_by_resource)
	var requested_total := _sum_rates(requested)
	var unlimited := _is_unlimited_capacity(capacity_upm)
	var delivered := {}
	var blocked := {}

	if requested_total <= RESOURCE_EPSILON:
		return {
			"requested_by_resource": requested,
			"delivered_by_resource": delivered,
			"blocked_by_resource": blocked,
			"requested_upm": 0.0,
			"used_upm": 0.0,
			"blocked_upm": 0.0,
			"available_upm": capacity_upm if not unlimited else UNLIMITED_CAPACITY_UPM,
			"saturation": 0.0,
			"unlimited": unlimited
		}

	var flow_ratio := 1.0
	if not unlimited and requested_total > capacity_upm:
		flow_ratio = capacity_upm / requested_total

	for resource in requested.keys():
		var requested_rate := float(requested[resource])
		var delivered_rate := requested_rate * flow_ratio
		delivered[resource] = delivered_rate
		var blocked_rate := requested_rate - delivered_rate
		if blocked_rate > RESOURCE_EPSILON:
			blocked[resource] = blocked_rate

	var used_total := _sum_rates(delivered)
	return {
		"requested_by_resource": requested,
		"delivered_by_resource": delivered,
		"blocked_by_resource": blocked,
		"requested_upm": requested_total,
		"used_upm": used_total,
		"blocked_upm": requested_total - used_total,
		"available_upm": maxf(capacity_upm - used_total, 0.0) if not unlimited else UNLIMITED_CAPACITY_UPM,
		"saturation": clampf(used_total / capacity_upm, 0.0, 1.0) if not unlimited and capacity_upm > RESOURCE_EPSILON else 0.0,
		"unlimited": unlimited
	}


func _update_storage_inventory(node: Dictionary, current_inventory: Dictionary, incoming: Dictionary, outgoing: Dictionary, delta_seconds: float) -> Dictionary:
	var next_inventory := current_inventory.duplicate(true)
	var resources := _union_resource_keys([current_inventory, incoming, outgoing])
	var capacity_by_resource := _get_storage_capacity_by_resource(node)
	var default_capacity := float(node.get("storage_capacity", node.get("capacity", -1.0)))

	for resource in resources:
		var old_qty := float(current_inventory.get(resource, 0.0))
		var incoming_qty := float(incoming.get(resource, 0.0)) * delta_seconds / 60.0
		var outgoing_qty := float(outgoing.get(resource, 0.0)) * delta_seconds / 60.0
		var next_qty = maxf(old_qty + incoming_qty - outgoing_qty, 0.0)
		var resource_capacity := float(capacity_by_resource.get(resource, default_capacity))
		if resource_capacity >= 0.0:
			next_qty = minf(next_qty, resource_capacity)
		if next_qty <= RESOURCE_EPSILON:
			next_inventory.erase(resource)
		else:
			next_inventory[resource] = next_qty
	return next_inventory


func _build_edge_result(edge: Dictionary, clamped: Dictionary) -> Dictionary:
	return {
		"id": String(edge.get("id", "")),
		"from": String(edge.get("from", "")),
		"to": String(edge.get("to", "")),
		"capacity_upm": float(edge.get("capacity_upm", UNLIMITED_CAPACITY_UPM)),
		"requested_by_resource": clamped.get("requested_by_resource", {}),
		"delivered_by_resource": clamped.get("delivered_by_resource", {}),
		"blocked_by_resource": clamped.get("blocked_by_resource", {}),
		"requested_upm": float(clamped.get("requested_upm", 0.0)),
		"used_upm": float(clamped.get("used_upm", 0.0)),
		"blocked_upm": float(clamped.get("blocked_upm", 0.0)),
		"available_upm": float(clamped.get("available_upm", 0.0)),
		"saturation": float(clamped.get("saturation", 0.0)),
		"unlimited": bool(clamped.get("unlimited", false)),
		"data": edge.get("data", {})
	}


func _build_node_result(node_id: String, kind: String, incoming: Dictionary, outgoing: Dictionary, blocked: Dictionary, resolved: Dictionary, storage_inventory: Dictionary) -> Dictionary:
	return {
		"id": node_id,
		"kind": kind,
		"incoming_by_resource": incoming,
		"outgoing_by_resource": outgoing,
		"blocked_outgoing_by_resource": blocked,
		"consumed_by_resource": resolved.get("consumed_by_resource", {}),
		"produced_by_resource": resolved.get("produced_by_resource", {}),
		"starved_by_resource": resolved.get("starved_by_resource", {}),
		"production_scale": float(resolved.get("production_scale", 1.0)),
		"storage_inventory": storage_inventory,
		"total_incoming_upm": _sum_rates(incoming),
		"total_outgoing_upm": _sum_rates(outgoing),
		"total_blocked_outgoing_upm": _sum_rates(blocked),
		"total_throughput_upm": maxf(_sum_rates(incoming), _sum_rates(outgoing))
	}


func _topological_order(node_ids: Array, adjacency: Dictionary) -> Array:
	var indegree := {}
	for node_id in node_ids:
		indegree[node_id] = 0

	for from_id in adjacency.keys():
		for edge in adjacency[from_id]:
			var to_id := String(edge.get("to", ""))
			indegree[to_id] = int(indegree.get(to_id, 0)) + 1

	var queue: Array = []
	for node_id in node_ids:
		if int(indegree.get(node_id, 0)) == 0:
			queue.append(node_id)

	var order: Array = []
	var head := 0
	while head < queue.size():
		var node_id := String(queue[head])
		head += 1
		order.append(node_id)
		for edge in adjacency.get(node_id, []):
			var to_id := String(edge.get("to", ""))
			indegree[to_id] = int(indegree.get(to_id, 0)) - 1
			if int(indegree.get(to_id, 0)) == 0:
				queue.append(to_id)

	for node_id in node_ids:
		if not order.has(node_id):
			order.append(node_id)
	return order


func _detect_loop_warnings(node_ids: Array, adjacency: Dictionary) -> Array:
	var warnings: Array = []
	var visit_state := {}
	var stack: Array = []
	for node_id in node_ids:
		if int(visit_state.get(node_id, 0)) == 0:
			_detect_loop_from(String(node_id), adjacency, visit_state, stack, warnings)
	return warnings


func _detect_loop_from(node_id: String, adjacency: Dictionary, visit_state: Dictionary, stack: Array, warnings: Array) -> void:
	visit_state[node_id] = 1
	stack.append(node_id)

	for edge in adjacency.get(node_id, []):
		var next_id := String(edge.get("to", ""))
		var next_state := int(visit_state.get(next_id, 0))
		if next_state == 0:
			_detect_loop_from(next_id, adjacency, visit_state, stack, warnings)
		elif next_state == 1:
			var cycle_nodes := _cycle_nodes_from_stack(stack, next_id)
			warnings.append({
				"type": WARNING_LOOP_DETECTED,
				"message": "Ambiguous flow loop detected.",
				"nodes": cycle_nodes
			})

	stack.pop_back()
	visit_state[node_id] = 2


func _cycle_nodes_from_stack(stack: Array, start_node_id: String) -> Array:
	var cycle_nodes: Array = []
	var start_index := stack.find(start_node_id)
	if start_index < 0:
		return cycle_nodes
	for i in range(start_index, stack.size()):
		cycle_nodes.append(stack[i])
	cycle_nodes.append(start_node_id)
	return cycle_nodes


func _get_node_id(node: Dictionary, fallback_index: int) -> String:
	var raw_id := String(node.get("id", ""))
	if raw_id != "":
		return raw_id
	return "node_%d" % fallback_index


func _get_edge_id(edge: Dictionary, fallback_index: int) -> String:
	var raw_id := String(edge.get("id", ""))
	if raw_id != "":
		return raw_id
	return "edge_%d" % fallback_index


func _get_node_kind(node: Dictionary) -> String:
	return String(node.get("kind", NODE_KIND_MACHINE)).strip_edges().to_lower()


func _get_edge_capacity(edge: Dictionary) -> float:
	if edge.has("capacity_upm"):
		return float(edge.get("capacity_upm", 0.0))
	if edge.has("capacity"):
		return float(edge.get("capacity", 0.0))
	return UNLIMITED_CAPACITY_UPM


func _get_node_inputs(node: Dictionary) -> Dictionary:
	return _first_rate_map(node, ["inputs", "consume_upm", "demand_upm", "input_upm"])


func _get_node_outputs(node: Dictionary) -> Dictionary:
	return _first_rate_map(node, ["outputs", "produce_upm", "production_upm", "output_upm"])


func _first_rate_map(source: Dictionary, keys: Array) -> Dictionary:
	for key in keys:
		var value = source.get(key, null)
		if value is Dictionary:
			return _dict_to_rate_map(value)
	return {}


func _dict_to_rate_map(value: Dictionary) -> Dictionary:
	var rates := {}
	for resource in value.keys():
		var resource_key := StringName(str(resource))
		var amount := float(value[resource])
		if absf(amount) > RESOURCE_EPSILON:
			rates[resource_key] = amount
	return rates


func _positive_rate_map(value: Dictionary) -> Dictionary:
	var rates := {}
	for resource in value.keys():
		var amount := float(value[resource])
		if amount > RESOURCE_EPSILON:
			rates[resource] = amount
	return rates


func _duplicate_rate_map(value: Dictionary) -> Dictionary:
	return _dict_to_rate_map(value)


func _multiply_rates(value: Dictionary, multiplier: float) -> Dictionary:
	var rates := {}
	for resource in value.keys():
		var amount := float(value[resource]) * multiplier
		if absf(amount) > RESOURCE_EPSILON:
			rates[resource] = amount
	return rates


func _add_rate_maps(first: Dictionary, second: Dictionary) -> Dictionary:
	var result := first.duplicate(true)
	_merge_rates(result, second)
	return result


func _merge_rates(target: Dictionary, source: Dictionary) -> void:
	for resource in source.keys():
		var next_rate := float(target.get(resource, 0.0)) + float(source[resource])
		if absf(next_rate) <= RESOURCE_EPSILON:
			target.erase(resource)
		else:
			target[resource] = next_rate


func _subtract_rate_maps(first: Dictionary, second: Dictionary) -> Dictionary:
	var result := {}
	for resource in _union_resource_keys([first, second]):
		var amount := float(first.get(resource, 0.0)) - float(second.get(resource, 0.0))
		if amount > RESOURCE_EPSILON:
			result[resource] = amount
	return result


func _sum_rates(rates: Dictionary) -> float:
	var total := 0.0
	for resource in rates.keys():
		total += maxf(float(rates[resource]), 0.0)
	return total


func _is_unlimited_capacity(capacity_upm: float) -> bool:
	return capacity_upm <= 0.0


func _inventory_to_rate_map(inventory: Dictionary, delta_seconds: float) -> Dictionary:
	var rates := {}
	var multiplier := 60.0 / maxf(delta_seconds, RESOURCE_EPSILON)
	for resource in inventory.keys():
		var qty := float(inventory[resource])
		if qty > RESOURCE_EPSILON:
			rates[resource] = qty * multiplier
	return rates


func _union_resource_keys(rate_maps: Array) -> Array:
	var seen := {}
	var resources: Array = []
	for rate_map_variant in rate_maps:
		if not (rate_map_variant is Dictionary):
			continue
		var rate_map: Dictionary = rate_map_variant
		for resource in rate_map.keys():
			if seen.has(resource):
				continue
			seen[resource] = true
			resources.append(resource)
	return resources


func _get_storage_capacity_by_resource(node: Dictionary) -> Dictionary:
	var capacity = node.get("storage_capacity_by_resource", node.get("capacity_by_resource", {}))
	if capacity is Dictionary:
		return _dict_to_rate_map(capacity)
	return {}


func _is_storage_kind(kind: String) -> bool:
	return kind == NODE_KIND_STORAGE


func _node_passes_through(node: Dictionary, kind: String) -> bool:
	if node.has("pass_through"):
		return bool(node.get("pass_through", false))
	return kind == NODE_KIND_JUNCTION or kind == NODE_KIND_SUPPORT or kind == NODE_KIND_ROUTER or kind == "rail_support"
