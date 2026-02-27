extends MenuButton

signal build_requested(scene: PackedScene)

@export var BuildManager: Node2D


func _ready() -> void:
	var start_build_callable := Callable(BuildManager, "start_build")
	if not build_requested.is_connected(start_build_callable):
		build_requested.connect(start_build_callable)


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


func _on_build_selected(id: int) -> void:
	$"../Debug Panel/DebugFeed".text = "_on_build_selected function triggered"
	var popup: PopupMenu = get_popup()

	# Convert pressed item id -> index, then read metadata for the scene key
	var idx := popup.get_item_index(id)
	$"../Debug Panel/DebugFeed".text = str(idx)
	if idx < 0:
		return

	var key := popup.get_item_metadata(idx) as StringName
	$"../Debug Panel/DebugFeed".text = str(key)
	if key == &"":
		push_warning("Menu item missing metadata (no build key). idx=%d id=%d" % [idx, id])
		$"../Debug Panel/DebugFeed".text = "Menu item missing metadata (no build key). idx=%d id=%d" % [idx, id]
		return

	var scene: PackedScene = BuildingRegistry.get_scene(key)
	$"../Debug Panel/DebugFeed".text = str(scene)
	
	if scene:
		print("Submitting build request for:", key)
		$"../Debug Panel/DebugFeed".text = "Submitting build request for:" + str(key)
		
		if BuildManager and BuildManager.has_method("start_build"):
			BuildManager.call_deferred("Start_build", scene)
		else:
			build_requested.emit(scene)
	else:
		push_warning("No building registered for key: %s" % String(key))
		$"../Debug Panel/DebugFeed".text = "No building registered for key: %s" % String(key)
