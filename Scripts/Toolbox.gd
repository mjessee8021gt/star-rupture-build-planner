extends MenuButton

signal build_requested(scene: PackedScene)
@export var BuildManager : Node2D

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
	extractionMenu.add_item("Helium-3 Extractor")
	extractionMenu.add_item("Sulfur Extractor")
	extractionMenu.id_pressed.connect(_on_build_selected)
	
	var craftingMenu = PopupMenu.new()
	craftingMenu.name = "Crafting"
	craftingMenu.add_item("Fabricator")
	craftingMenu.add_item("Assembler")
	
	var processingMenu = PopupMenu.new()
	processingMenu.name = "Processing"
	processingMenu.add_item("Smelter", ProcessingItem.SMELTER)
	processingMenu.add_item("Furnace")
	processingMenu.add_item("Mega Press")
	processingMenu.add_item("Compounder")
	processingMenu.id_pressed.connect(_on_build_selected)
	print("Menu Item Selected...")
	
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


func _on_build_selected(id: int) -> void:
	print("Menu Item Selected: ", id)
	if build_scenes.has(id):
		print("Submitting build reuqest...")
		build_requested.emit(build_scenes[id])
	else:
		push_warning("No scene mapped for menu ID %s" % id)
		return
