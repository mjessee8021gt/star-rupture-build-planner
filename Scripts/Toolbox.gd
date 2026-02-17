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
	extractionMenu.add_item("Sulfur Extractor")
	extractionMenu.id_pressed.connect(_on_build_selected.bind(extractionMenu))
	print("Extraction Menu Item Selected...")
	
	var craftingMenu = PopupMenu.new()
	craftingMenu.name = "Crafting"
	craftingMenu.add_item("Fabricator")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"fabricator")
	craftingMenu.add_item("Assembler")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"assembler")
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
	processingMenu.add_item("Refinery")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"refinery")
	processingMenu.id_pressed.connect(_on_build_selected.bind(processingMenu))
	print("Processing Menu Item Selected...")
	
	var powerMenu = PopupMenu.new()
	powerMenu.name = "Power"
	powerMenu.add_item("Solar Mk1")
	powerMenu.add_item("Wind Mk1")
	powerMenu.add_item("Solar Mk2")
	powerMenu.add_item("Wind Mk2")
	
	var railMenu = PopupMenu.new()
	railMenu.name = "Rails"
	railMenu.add_item("Rail Mk1")
	railMenu.add_item("Rail Mk2")
	railMenu.add_item("Rail Mk3")
	railMenu.add_item("Rail Connector")
	railMenu.add_item("Rail Support")
	railMenu.add_item("Multirail 3")
	railMenu.add_item("Rail Modulator 3")
	railMenu.add_item("Multirail 5")
	railMenu.add_item("Rail Modulator 5")
	
	var shipmentMenu = PopupMenu.new()
	shipmentMenu.name = "Shipment"
	shipmentMenu.add_item("Orbital Cargo Launcher")
	shipmentMenu.add_item("Cargo Dispatcher")
	shipmentMenu.add_item("Cargo Receiver")
	shipmentMenu.add_item("Teleporter")
	
	var storageMenu = PopupMenu.new()
	storageMenu.name = "Storage"
	storageMenu.add_item("Storage Depot Mk1")
	storageMenu.add_item("Storage Depot Mk2")
	storageMenu.add_item("Multistorage")
	storageMenu.add_item("Expandable Storage")
	
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

	popup.add_submenu_item("Extraction", extractionMenu.name)
	popup.add_submenu_item("Crafting", craftingMenu.name)
	popup.add_submenu_item("Processing", processingMenu.name)
	popup.add_submenu_item("Power", powerMenu.name)
	popup.add_submenu_item("Transport", transportMenu.name)


func _on_build_selected(id: int, menu:PopupMenu) -> void:
	var idx := menu.get_item_index(id)
	var key := menu.get_item_metadata(idx) as StringName
	
	var scene = BuildingRegistry.get_scene(key)
	if scene:
		print("Submitting build reuqest...")
		build_requested.emit(scene)
	else:
		push_warning("No registered for key: %s" % key)
		return
