extends RefCounted
class_name DebugLayerModel

# Pure derivation layer for the Visual Debug Layers system. Given the flow graph and a
# PathingIntelligence assessment (data the planner already computes), it classifies what
# each layer should mark — with no dependency on the scene, so it is unit-testable
# headless. main.gd owns the scene-bound geometry (world rects, rail polylines, port
# positions); this class owns the "which buildings/rails/ports and why".

const HEALTH_SUPPLIED := "supplied"
const HEALTH_UNDER := "under"
const HEALTH_MISSING := "missing"
const HEALTH_DISCONNECTED := "disconnected"

const SATURATION_SPARE := "spare"
const SATURATION_NEAR := "near"
const SATURATION_OVER := "over"
const SATURATION_NEAR_THRESHOLD := 0.85
const SATURATION_EPSILON := 0.001


# Classify one building's supply health from its PathingIntelligence building assessment.
# Returns "" for buildings with no input requirements (nothing to assess).
static func health_state(ba: Dictionary) -> String:
	var requirements = ba.get("requirements", [])
	if not (requirements is Array) or (requirements as Array).is_empty():
		return ""
	var port_summaries = ba.get("port_summaries", {})
	var has_ports := port_summaries is Dictionary and not (port_summaries as Dictionary).is_empty()
	if not has_ports:
		# Requires inputs but nothing is wired to any input port.
		return HEALTH_DISCONNECTED
	var missing = ba.get("missing_requirements", [])
	if missing is Array and not (missing as Array).is_empty():
		# At least one required input is absent from every connected rail.
		return HEALTH_MISSING
	if bool(ba.get("has_under_supply", false)):
		return HEALTH_UNDER
	return HEALTH_SUPPLIED


# From edge_supply, the producer node ids pushing unused resource onto a rail (waste
# sources to mark) and the edge ids carrying unused resource (dead-lengths to dash).
static func waste_sources(edge_supply: Dictionary) -> Dictionary:
	var from_ids: Array = []
	var edge_ids: Array = []
	var seen := {}
	for edge_id in edge_supply.keys():
		var es = edge_supply[edge_id]
		if not (es is Dictionary):
			continue
		var unused = (es as Dictionary).get("unused_resources", [])
		if not (unused is Array) or (unused as Array).is_empty():
			continue
		edge_ids.append(String(edge_id))
		var from_id := String((es as Dictionary).get("from", ""))
		if from_id != "" and not seen.has(from_id):
			seen[from_id] = true
			from_ids.append(from_id)
	return {"from_ids": from_ids, "edge_ids": edge_ids}


# From a flow graph: the fully-disconnected node ids (no rail touches them) and, per
# connected node, the port leaf-names that no edge attaches to.
static func orphans(graph: Dictionary) -> Dictionary:
	var nodes = graph.get("nodes", [])
	var edges = graph.get("edges", [])
	var connected := {}
	var used_ports := {}     # node_id -> { port_leaf: true }
	for edge_variant in (edges if edges is Array else []):
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		connected[from_id] = true
		connected[to_id] = true
		_mark_port(used_ports, from_id, String(edge.get("from_port", "")))
		_mark_port(used_ports, to_id, String(edge.get("to_port", "")))

	var disconnected: Array = []
	var unconnected_ports := {}     # node_id -> [port name]
	for node_variant in (nodes if nodes is Array else []):
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := String(node.get("id", ""))
		if node_id == "":
			continue
		if not connected.has(node_id):
			disconnected.append(node_id)
			continue
		var node_used: Dictionary = used_ports.get(node_id, {})
		var free_ports: Array = []
		for port_name in _all_ports(node):
			if not node_used.has(port_leaf(port_name)):
				free_ports.append(port_name)
		if not free_ports.is_empty():
			unconnected_ports[node_id] = free_ports
	return {"disconnected": disconnected, "unconnected_ports": unconnected_ports}


# Production-stage depth per node: how many production steps upstream sit on the
# longest supply chain feeding it. Sources = tier 0; a machine fed by a source = tier 1;
# supports/junctions/routers are transparent (they pass depth through without adding a
# stage). Cycle-guarded so flow loops don't recurse forever.
static func production_tiers(graph: Dictionary) -> Dictionary:
	var nodes = graph.get("nodes", [])
	var edges = graph.get("edges", [])
	var kind_by_id := {}
	var incoming := {}     # node_id -> [from_id]
	for node_variant in (nodes if nodes is Array else []):
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := String(node.get("id", ""))
		if node_id == "":
			continue
		kind_by_id[node_id] = String(node.get("kind", "machine")).to_lower()
		if not incoming.has(node_id):
			incoming[node_id] = []
	for edge_variant in (edges if edges is Array else []):
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if from_id == "" or to_id == "" or not incoming.has(to_id):
			continue
		(incoming[to_id] as Array).append(from_id)

	var depth := {}
	for node_id in kind_by_id.keys():
		_tier_depth(node_id, incoming, kind_by_id, depth, {})
	var max_tier := 0
	for node_id in depth.keys():
		max_tier = maxi(max_tier, int(depth[node_id]))
	return {"tiers": depth, "max_tier": max_tier}


static func _tier_depth(node_id: String, incoming: Dictionary, kind_by_id: Dictionary, depth: Dictionary, stack: Dictionary) -> int:
	if depth.has(node_id):
		return int(depth[node_id])
	if stack.has(node_id):
		return 0      # cycle: break without recursing
	stack[node_id] = true
	var best := 0
	var from_ids = incoming.get(node_id, [])
	for from_id in (from_ids if from_ids is Array else []):
		var from_depth := _tier_depth(String(from_id), incoming, kind_by_id, depth, stack)
		var step := 0 if _is_transparent(String(kind_by_id.get(from_id, "machine"))) else 1
		best = maxi(best, from_depth + step)
	stack.erase(node_id)
	depth[node_id] = best
	return best


static func _is_transparent(kind: String) -> bool:
	return kind == "support" or kind == "junction" or kind == "router"


# Per-rail saturation classification from a FlowSimulator result. spare (headroom),
# near (>= 85% of capacity), over (blocked or above capacity). Unlimited/uncapped rails
# report spare. Used for the static choropleth complement to the animated flow beads.
static func rail_saturations(sim_result: Dictionary) -> Dictionary:
	var out := {}
	var edges = sim_result.get("edges", {})
	if not (edges is Dictionary):
		return out
	for edge_id in edges.keys():
		var edge_result = edges[edge_id]
		if not (edge_result is Dictionary):
			continue
		var used := float((edge_result as Dictionary).get("used_upm", 0.0))
		var blocked := float((edge_result as Dictionary).get("blocked_upm", 0.0))
		var capacity := float((edge_result as Dictionary).get("capacity_upm", 0.0))
		var unlimited := bool((edge_result as Dictionary).get("unlimited", false))
		var ratio := 0.0
		if not unlimited and capacity > 0.0:
			ratio = used / capacity
		# At-capacity (zero headroom) reads as "over": a 120/120 rail is fully saturated
		# and can't take more, which is exactly what a saturation hunt wants flagged.
		var state := SATURATION_SPARE
		if blocked > SATURATION_EPSILON or ratio >= 1.0 - SATURATION_EPSILON:
			state = SATURATION_OVER
		elif ratio >= SATURATION_NEAR_THRESHOLD:
			state = SATURATION_NEAR
		out[String(edge_id)] = {"ratio": ratio, "state": state, "unlimited": unlimited}
	return out


# Normalize a list of magnitudes to 0..1 against the largest absolute value.
static func normalize(values: Array) -> Array:
	var max_value := 0.0
	for v in values:
		max_value = maxf(max_value, absf(float(v)))
	var out: Array = []
	for v in values:
		out.append((absf(float(v)) / max_value) if max_value > 0.0 else 0.0)
	return out


# Leaf name of a port reference. Rail metadata stores NodePaths like "Ports/Output 1";
# building port children are named "Output 1", so match on the trailing leaf.
static func port_leaf(port: String) -> String:
	return port.get_file().strip_edges() if port.contains("/") else port.strip_edges()


static func _mark_port(used_ports: Dictionary, node_id: String, port: String) -> void:
	var leaf := port_leaf(port)
	if node_id == "" or leaf == "":
		return
	if not used_ports.has(node_id):
		used_ports[node_id] = {}
	(used_ports[node_id] as Dictionary)[leaf] = true


static func _all_ports(node: Dictionary) -> Array:
	var names: Array = []
	var ports = node.get("ports", {})
	if not (ports is Dictionary):
		return names
	for group in ["input", "output", "universal"]:
		var group_ports = (ports as Dictionary).get(group, [])
		if not (group_ports is Array):
			continue
		for port_name in group_ports:
			names.append(String(port_name))
	return names
