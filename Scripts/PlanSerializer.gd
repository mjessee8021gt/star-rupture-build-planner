class_name PlanSerializer
extends RefCounted

# Pure serialization helpers for turning placed buildings / rails into the
# plain-data dictionaries used by saves, blueprints, the version log and PDF
# export. Extracted from main.gd; scene-specific coordinators (build_manager,
# path_manager) are passed in so these stay free of node lookups on `main`.

# Meta key stamped on each building so saves, annotations and paths can refer to
# a stable building identity across reloads.
const BUILDING_UID_META := &"srbp_building_uid"


static func serialize_option_button(node: Node) -> Dictionary:
	if node == null or not (node is OptionButton):
		return {}

	var ob := node as OptionButton
	var selected := ob.selected
	var metadata_path := ""

	if selected >= 0 and selected < ob.item_count:
		var metadata = ob.get_item_metadata(selected)
		if metadata is Resource:
			metadata_path = (metadata as Resource).resource_path
		elif metadata != null:
			metadata_path = str(metadata)

	return {
		"selected": selected,
		"metadata_path": metadata_path,
	}


static func ensure_building_uid(building: Node) -> String:
	if building == null:
		return ""
	if building.has_meta(BUILDING_UID_META):
		var existing := String(building.get_meta(BUILDING_UID_META))
		if existing != "":
			return existing
	var uid := "bldg_%d_%d" % [Time.get_ticks_usec(), randi()]
	building.set_meta(BUILDING_UID_META, uid)
	return uid


static func serialize_building(building: Node2D, build_manager: Node) -> Dictionary:
	var recipe_selection := serialize_option_button(building.get_node_or_null("Recipe"))
	var purity_selection := serialize_option_button(building.get_node_or_null("Purity"))
	var core_level_selection := serialize_option_button(building.get_node_or_null("CoreLevel"))
	var saved_anchor_cell := Vector2i.ZERO
	if build_manager != null and build_manager.has_method("_anchor_cell_from_building_position"):
		saved_anchor_cell = build_manager._anchor_cell_from_building_position(building, building.global_position)
	elif build_manager != null and build_manager.has_method("world_to_cell"):
		saved_anchor_cell = build_manager.world_to_cell(building.global_position)

	var saved_footprint := Vector2i.ONE
	if build_manager != null and build_manager.has_method("get_rotated_footprint"):
		saved_footprint = build_manager.get_rotated_footprint(building)
	elif "footprint" in building and building.get("footprint") is Vector2i:
		saved_footprint = building.get("footprint")

	return {
		"uid": ensure_building_uid(building),
		"id": str(building.get("id")) if building.has_method("get") else "",
		"scene_path": building.scene_file_path,
		"position": [building.global_position.x, building.global_position.y],
		"rotation_degrees": building.rotation_degrees,
		"rotated_tick": int(building.get("rotatedTick")) if "rotatedTick" in building else 0,
		"is_alternate": bool(building.get("is_alternate")) if "is_alternate" in building else false,
		"anchor_cell": [int(saved_anchor_cell.x), int(saved_anchor_cell.y)],
		"footprint": [max(1, int(saved_footprint.x)), max(1, int(saved_footprint.y))],
		"recipe": recipe_selection,
		"purity": purity_selection,
		"core_level": core_level_selection,
	}


static func serialize_paths(path_manager: Node, building_index: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if path_manager == null:
		return out

	for child in path_manager.get_children():
		if not (child is Path2D):
			continue
		if not child.has_meta("from_building") or not child.has_meta("to_building"):
			continue

		var from_building: Node = child.get_meta("from_building")
		var to_building: Node = child.get_meta("to_building")

		if not building_index.has(from_building) or not building_index.has(to_building):
			continue

		var rail_version := -1
		if path_manager.has_method("get_path_rail_version"):
			rail_version = int(path_manager.get_path_rail_version(child))
		elif child.has_meta("rail_version"):
			rail_version = int(child.get_meta("rail_version"))

		out.append({
			"from_index": int(building_index[from_building]),
			"to_index": int(building_index[to_building]),
			"from_port": str(child.get_meta("from_port")),
			"to_port": str(child.get_meta("to_port")),
			"rail_version": rail_version,
		})

	return out


static func sum_building_stat(buildings: Array[Node2D], stat_name: String) -> int:
	var total := 0
	for building in buildings:
		if stat_name in building:
			total += int(building.get(stat_name))
	return total


static func sum_building_costs(buildings: Array[Node2D]) -> Dictionary:
	var totals := {
		"bbm": 0,
		"ibm": 0,
		"meteor_cores": 0,
	}

	for building in buildings:
		if not ("build_cost_amount" in building):
			continue

		var amount := int(building.get("build_cost_amount"))
		var cost_type := int(building.get("build_cost_type")) if "build_cost_type" in building else 0

		match cost_type:
			Building.BuildCostType.BBM:
				totals["bbm"] += amount
			Building.BuildCostType.IBM:
				totals["ibm"] += amount
			Building.BuildCostType.METEOR_CORE:
				totals["meteor_cores"] += amount

	return totals
