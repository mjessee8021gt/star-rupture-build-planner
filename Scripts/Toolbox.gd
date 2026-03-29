extends MenuButton

signal build_requested(scene: PackedScene)

@export var BuildManager : Node2D

var Idx

enum ExtractionItem {ORE_EXCAVATOR, HELIUM_3_EXTRACTOR, SULFUR_EXTRACTOR}
enum ProcessingItem {SMELTER, FURNACE, MEGA_PRESS, COMPOUNDER}

@onready var build_scenes := {
	ProcessingItem.SMELTER:preload("res://Buildings/Smelter.tscn")
}
# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	if BuildManager:
		build_requested.connect(BuildManager.start_build)
	else:
		push_error("BuildManager not assigned in inspector.")

	var popup := get_popup()
	var extractionMenu = PopupMenu.new()
	extractionMenu.name = "Extraction"
	extractionMenu.add_item("Ore Excavator")
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"ore_excavator")
	extractionMenu.add_item("Helium-3 Extractor")
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"helium_extractor")
	extractionMenu.add_item("Sulfur Extractor")
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"sulfur_extractor")
	extractionMenu.add_item("Oil Extractor") ## added in pre-release update 1
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"oil_extractor")
	extractionMenu.add_item("Laser Drill") ## added in pre-release update 1
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"laser_drill")
	extractionMenu.add_item("Deuterium Extractor") ## Datamined from Alpha release
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"deuterium_extractor")
	extractionMenu.id_pressed.connect(_on_build_selected.bind(extractionMenu))
	print("Extraction Menu Item Selected...")
	$"../Debug Panel/DebugFeed".text = "Extraction Menu Item Selected..."
	
	var craftingMenu = PopupMenu.new()
	craftingMenu.name = "Crafting"
	craftingMenu.add_item("Fabricator")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"fabricator")
	craftingMenu.add_item("Assembler")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"assembler")
	craftingMenu.add_item("Constructorizer")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"constructorizer")
	craftingMenu.add_item("Facturer")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"facturer")
	craftingMenu.id_pressed.connect(_on_build_selected.bind(craftingMenu))
	
	var processingMenu = PopupMenu.new()
	processingMenu.name = "Processing"
	processingMenu.add_item("Smelter")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"smelter")
	processingMenu.add_item("Furnace")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"furnace")
	processingMenu.add_item("Mega Press")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"mega_press")
	processingMenu.add_item("Compounder")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"compounder")
	processingMenu.add_item("Pressurizer")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"pressurizer")
	processingMenu.add_item("Refinery")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"refinery")
	processingMenu.add_item("Pyro Forge")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"pyro_forge")
	processingMenu.id_pressed.connect(_on_build_selected.bind(processingMenu))
	print("Processing Menu Item Selected...")
	
	var powerMenu = PopupMenu.new()
	powerMenu.name = "Power"
	powerMenu.add_item("Solar Mk1")
	powerMenu.set_item_metadata(powerMenu.item_count-1, &"solar_v1")
	powerMenu.add_item("Wind Mk1")
	powerMenu.set_item_metadata(powerMenu.item_count-1, &"wind_v1")
	powerMenu.add_item("Solar Mk2")
	powerMenu.set_item_metadata(powerMenu.item_count-1, &"solar_v2")
	powerMenu.add_item("Wind Mk2")
	powerMenu.set_item_metadata(powerMenu.item_count-1, &"wind_v2")
	powerMenu.add_item("Chemical Generator")
	powerMenu.set_item_metadata(powerMenu.item_count-1, &"chemical_generator")
	powerMenu.id_pressed.connect(_on_build_selected.bind(powerMenu))
	print("Power Menu Item Selected...")
	
	var railMenu = PopupMenu.new()
	railMenu.name = "Rails"
	railMenu.add_item("Rail Connector")
	railMenu.set_item_metadata(railMenu.item_count-1, &"rail_connector")
	railMenu.add_item("Rail Support")
	railMenu.set_item_metadata(railMenu.item_count-1, &"rail_support")
	railMenu.add_item("Multirail 3")
	railMenu.set_item_metadata(railMenu.item_count-1, &"multirail_3")
	railMenu.add_item("Rail Modulator 3")
	railMenu.set_item_metadata(railMenu.item_count-1, &"rail_modulator_3")
	railMenu.add_item("Multirail 5")
	railMenu.set_item_metadata(railMenu.item_count-1, &"multirail_5")
	railMenu.add_item("Rail Modulator 5")
	railMenu.set_item_metadata(railMenu.item_count-1, &"rail_modulator_5")
	railMenu.add_item("Radial Rail Connector")
	railMenu.set_item_metadata(railMenu.item_count-1, &"radial_rail")
	railMenu.id_pressed.connect(_on_build_selected.bind(railMenu))
	print("Rail Menu Item Selected...")
	
	var shipmentMenu = PopupMenu.new()
	shipmentMenu.name = "Shipment"
	shipmentMenu.add_item("Orbital Cargo Launcher")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"orbital_launcher")
	shipmentMenu.add_item("Cargo Dispatcher")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"dispatcher")
	shipmentMenu.add_item("Cargo Receiver")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"receiver")
	shipmentMenu.add_item("Teleporter")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"teleporter")
	shipmentMenu.id_pressed.connect(_on_build_selected.bind(shipmentMenu))
	print("Shipment Menu Item Selected...")
	
	var storageMenu = PopupMenu.new()
	storageMenu.name = "Storage"
	storageMenu.add_item("Storage Depot Mk1")
	storageMenu.set_item_metadata(storageMenu.item_count-1, &"storage_v1")
	storageMenu.add_item("Storage Depot Mk2")
	storageMenu.set_item_metadata(storageMenu.item_count-1, &"storage_v2")
	storageMenu.add_item("Multistorage")
	storageMenu.set_item_metadata(storageMenu.item_count-1, &"multistore")
	storageMenu.add_item("Expandable Storage")
	storageMenu.set_item_metadata(storageMenu.item_count-1, &"expandable_storage")
	storageMenu.id_pressed.connect(_on_build_selected.bind(storageMenu))
	
	var habitatMenu = PopupMenu.new()
	habitatMenu.add_item("Base Core")
	habitatMenu.set_item_metadata(habitatMenu.item_count-1, &"base_core")
	habitatMenu.add_item("Base Core Amplifier V1")
	habitatMenu.set_item_metadata(habitatMenu.item_count-1, &"core_amp_v1")
	habitatMenu.add_item("Base Core Amplifier V2")
	habitatMenu.set_item_metadata(habitatMenu.item_count-1, &"core_amp_v2")
	habitatMenu.add_item("Habitat")
	habitatMenu.set_item_metadata(habitatMenu.item_count-1, &"habitat")
	habitatMenu.add_item("Large Habitat")
	habitatMenu.set_item_metadata(habitatMenu.item_count-1, &"large_habitat")
	habitatMenu.id_pressed.connect(_on_build_selected.bind(habitatMenu))
	
	var transportMenu = PopupMenu.new()
	transportMenu.name = "Transport"
	transportMenu.add_child(railMenu)
	transportMenu.add_child(shipmentMenu)
	transportMenu.add_child(storageMenu)
	
	transportMenu.add_submenu_item("Rails", railMenu.name)
	transportMenu.add_submenu_item("Shipment", shipmentMenu.name)
	transportMenu.add_submenu_item("Storage", storageMenu.name)

	popup.add_child(extractionMenu)
	popup.add_child(craftingMenu)
	popup.add_child(processingMenu)
	popup.add_child(powerMenu)
	popup.add_child(transportMenu)
	popup.add_child(habitatMenu)

	popup.add_submenu_item("Extraction", extractionMenu.name)
	popup.add_submenu_item("Crafting", craftingMenu.name)
	popup.add_submenu_item("Processing", processingMenu.name)
	popup.add_submenu_item("Power", powerMenu.name)
	popup.add_submenu_item("Transport", transportMenu.name)
	popup.add_submenu_item("Habitat", habitatMenu.name)

func _on_build_selected(id: int, menu:PopupMenu) -> void:
	var idx := menu.get_item_index(id)
	var key := menu.get_item_metadata(idx) as StringName
	
	var scene = BuildingRegistry.get_scene(key)
	if scene:
		print("Submitting build reuqest...")
		$"../Debug Panel/DebugFeed".text = "Submitting build reuqest..."
		build_requested.emit(scene)
	else:
		push_warning("No registered for key: %s" % key)
		$"../Debug Panel/DebugFeed".text = "No registered for key: %s" % key
		return
