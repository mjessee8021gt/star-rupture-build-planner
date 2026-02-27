extends "res://Scripts/Toolbox.gd"

# HTML5-specific toolbox behavior:
# - Resolve BuildManager dynamically if export/scene wiring differs.
# - Defer build start until after popup event processing.
func _ready() -> void:
	if BuildManager == null:
		BuildManager = get_node_or_null("../../../BuildManager") as Node2D
	super._ready()


func _on_build_selected(id: int, menu: PopupMenu) -> void:
	var idx := menu.get_item_index(id)
	var key: StringName = &""
	var metadata := menu.get_item_metadata(idx)
	if metadata is StringName:
		key = metadata
	elif metadata is String:
		key = StringName(metadata)

	if key == &"":
		push_warning("Selected toolbox item has no build key metadata: %s" % menu.get_item_text(idx))
		return

	var scene: PackedScene = BuildingRegistry.get_scene(key)
	if scene == null:
		push_warning("No building registered for key: %s" % key)
		return

	print("Submitting build request for: ", key)

	var manager: Node = BuildManager
	if manager == null:
		manager = get_node_or_null("../../../BuildManager")

	if manager != null and manager.has_method("start_build"):
		await get_tree().process_frame
		manager.call_deferred("start_build", scene)
	else:
		push_error("BuildManager missing or does not expose start_build; falling back to signal emit.")
		build_requested.emit(scene)
