extends MenuButton

signal build_requested(scene: PackedScene)

@export var BuildManager: Node2D

func _debug(message: String) -> void:
	var feed := get_node_or_null("../Debug Panel/DebugFeed")
	if feed:
		feed.text = feed.text + "\n" + message


func _get_building_registry() -> Node:
	var registry := get_node_or_null("/root/BuildingRegistry")
	if registry == null:
		var msg := "Autoload '/root/BuildingRegistry' not found. Check Project Settings > Autoload name/path."
		push_warning(msg)
		_debug(msg)
		return null

	if not registry.has_method("get_scene"):
		var msg := "Autoload '/root/BuildingRegistry' is missing get_scene(key)."
		push_warning(msg)
		_debug(msg)
		return null

	return registry

func _ready() -> void:
	if BuildManager and BuildManager.has_method("start_build"):
		var start_build_callable := Callable(BuildManager, "start_build")
		if not build_requested.is_connected(start_build_callable):
			build_requested.connect(start_build_callable)
	else:
		push_error("BuildManager not assigned in inspector.")
		_debug("BuildManager not assigned in inspector.")


	var popup: PopupMenu = get_popup()
	popup.clear()

	# One connection only (HTML5-safe)
	if not popup.id_pressed.is_connected(_on_build_selected):
		popup.id_pressed.connect(_on_build_selected)

	# Helper: add an item + metadata key
	var add_entry := func(label: String, key: StringName) -> void:
		popup.add_item(label)
		popup.set_item_metadata(popup.item_count - 1, key)

	# Helper: labeled separator (category header)
	var add_cat := func(title: String) -> void:
		popup.add_separator(title)

	# =========================
	# Categories + Items
	# =========================

	add_cat.call("Extraction")
	add_entry.call("Ore Excavator", &"ore_excavator")
	add_entry.call("Helium-3 Extractor", &"helium_extractor")
	add_entry.call("Sulfur Extractor", &"sulfur_extractor")

	add_cat.call("Crafting")
	add_entry.call("Fabricator", &"fabricator")
	add_entry.call("Assembler", &"assembler")

	add_cat.call("Processing")
	add_entry.call("Smelter", &"smelter")
	add_entry.call("Furnace", &"furnace")
	add_entry.call("Mega Press", &"mega_press")
	add_entry.call("Compounder", &"compounder")

	add_cat.call("Power")
	add_entry.call("Solar Mk1", &"solar_v1")
	add_entry.call("Wind Mk1", &"wind_v1")
	add_entry.call("Solar Mk2", &"solar_v2")
	add_entry.call("Wind Mk2", &"wind_v2")

	add_cat.call("Transport — Rails")
	add_entry.call("Rail Connector", &"rail_connector")
	add_entry.call("Rail Support", &"rail_support")
	add_entry.call("Multirail 3", &"multirail_3")
	add_entry.call("Rail Modulator 3", &"rail_modulator_3")
	add_entry.call("Multirail 5", &"multirail_5")
	add_entry.call("Rail Modulator 5", &"rail_modulator_5")

	add_cat.call("Transport — Shipment")
	add_entry.call("Orbital Cargo Launcher", &"orbital_cargo_launcher")
	add_entry.call("Cargo Dispatcher", &"cargo_dispatcher")
	add_entry.call("Cargo Receiver", &"cargo_receiver")
	add_entry.call("Teleporter", &"teleporter")

	add_cat.call("Transport — Storage")
	add_entry.call("Storage Depot Mk1", &"storage_depot_mk1")
	add_entry.call("Storage Depot Mk2", &"storage_depot_mk2")
	add_entry.call("Multistorage", &"multistorage")
	add_entry.call("Expandable Storage", &"expandable_storage")
	$"../Debug Panel/DebugFeed".text = $"../Debug Panel/DebugFeed".text + "\n" + "Toolbox Menu initialized."

func _on_build_selected(id: int) -> void:
	_debug("_on_build_selected function triggered")
	var popup: PopupMenu = get_popup()

	# Convert pressed item id -> index, then read metadata for the scene key
	var idx := popup.get_item_index(id)
	_debug(str(idx))
	if idx < 0:
		return

	var key := popup.get_item_metadata(idx) as StringName
	_debug(str(key))
	if key == &"":
		push_warning("Menu item missing metadata (no build key). idx=%d id=%d" % [idx, id])
		_debug("Menu item missing metadata (no build key). idx=%d id=%d" % [idx, id])
		return
		
	var registry := _get_building_registry()
	if registry == null:
		return

	var scene_value: Variant = registry.call("get_scene", key)
	_debug("lookup(" + String(key) + "): " + str(scene_value))

	
	if scene_value is PackedScene:
		var scene := scene_value as PackedScene
		print("Submitting build request for:", key)
		_debug("Submitting build request for:" + str(key))
		
		if BuildManager and BuildManager.has_method("start_build"):
			BuildManager.call_deferred("start_build", scene)
			_debug("Dispatch: direct BuildManager.start_build(" + str(key) + ")")
		else:
			build_requested.emit(scene)
			_debug("Dispatch: build_requested.emit (" + str(key) + ")")
	else:
		var msg := "No PackedScene registered for key: %s (value=%s)" %[String(key), str(scene_value)]
		push_warning(msg)
		_debug(msg)
