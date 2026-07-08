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
