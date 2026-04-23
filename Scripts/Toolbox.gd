extends Button

signal build_requested(scene: PackedScene)

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

@export var BuildManager : Node2D

var keep_open_after_selection := true
var _popup: PopupMenu
var _popup_menus: Array[PopupMenu] = []
var _suppress_next_restore := false
var _ui_scale := 1.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pressed.connect(toggle_toolbox)
	if BuildManager:
		build_requested.connect(BuildManager.start_build)
	else:
		push_error("BuildManager not assigned in inspector.")

	_popup = PopupMenu.new()
	_popup.name = "ToolboxPopup"
	_popup.popup_hide.connect(_on_toolbox_popup_hidden)
	add_child(_popup)

	var popup := _popup
	var extractionMenu = PopupMenu.new()
	extractionMenu.name = "Extraction"
	extractionMenu.add_item("Ore Excavator")
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"ore_excavator")
	extractionMenu.add_item("Ore Excavator V2")
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"ore_excavator_v2")
	extractionMenu.add_item("Helium-3 Extractor")
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"helium_extractor")
	extractionMenu.add_item("Sulfur Extractor")
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"sulfur_extractor")
	extractionMenu.add_item("Oil Extractor") ## added in pre-release update 1
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"oil_extractor")
	extractionMenu.add_item("Laser Drill") ## added in pre-release update 1
	extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"laser_drill")
	##extractionMenu.add_item("Deuterium Extractor") ## Datamined from Alpha release
	##extractionMenu.set_item_metadata(extractionMenu.item_count-1, &"deuterium_extractor")
	extractionMenu.id_pressed.connect(_on_build_selected.bind(extractionMenu))
	
	var craftingMenu = PopupMenu.new()
	craftingMenu.name = "Crafting"
	craftingMenu.add_item("Fabricator")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"fabricator")
	craftingMenu.add_item("Fabricator V2")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"fabricator_v2")
	craftingMenu.add_item("Assembler")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"assembler")
	craftingMenu.add_item("Constructorizer")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"constructorizer")
	craftingMenu.add_item("Constructorizer V2")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"constructorizer_v2")
	craftingMenu.add_item("Facturer")
	craftingMenu.set_item_metadata(craftingMenu.item_count-1, &"facturer")
	craftingMenu.id_pressed.connect(_on_build_selected.bind(craftingMenu))
	
	var processingMenu = PopupMenu.new()
	processingMenu.name = "Processing"
	processingMenu.add_item("Smelter")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"smelter")
	processingMenu.add_item("Furnace")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"furnace")
	processingMenu.add_item("Furnace V2")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"furnace_v2")
	processingMenu.add_item("Mega Press")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"mega_press")
	processingMenu.add_item("Compounder")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"compounder")
	processingMenu.add_item("Compounder V2")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"compounder_v2")
	processingMenu.add_item("Pressurizer")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"pressurizer")
	processingMenu.add_item("Refinery")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"refinery")
	processingMenu.add_item("Pyro Forge")
	processingMenu.set_item_metadata(processingMenu.item_count-1, &"pyro_forge")
	processingMenu.id_pressed.connect(_on_build_selected.bind(processingMenu))
	
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
	railMenu.add_item("Zipline")
	railMenu.set_item_metadata(railMenu.item_count-1, &"zipline")
	railMenu.id_pressed.connect(_on_build_selected.bind(railMenu))
	
	var shipmentMenu = PopupMenu.new()
	shipmentMenu.name = "Shipment"
	shipmentMenu.add_item("Orbital Cargo Launcher")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"orbital_launcher")
	shipmentMenu.add_item("Orbital Cargo Launcher V2")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"orbital_launcher_v2")
	shipmentMenu.add_item("Cargo Dispatcher")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"dispatcher")
	shipmentMenu.add_item("Cargo Receiver")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"receiver")
	shipmentMenu.add_item("Teleporter")
	shipmentMenu.set_item_metadata(shipmentMenu.item_count-1, &"teleporter")
	shipmentMenu.id_pressed.connect(_on_build_selected.bind(shipmentMenu))
	
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
	habitatMenu.name = "Habitat"
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
	habitatMenu.add_item("Defense Turret")
	habitatMenu.set_item_metadata(habitatMenu.item_count-1, &"defense_turret")
	habitatMenu.add_item("Defense Tower")
	habitatMenu.set_item_metadata(habitatMenu.item_count-1, &"defense_tower")
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
	_collect_popup_menus(popup)
	_apply_popup_persistence()
	_apply_popup_theme()

func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	_apply_popup_theme()

func toggle_toolbox() -> void:
	if _popup == null:
		return
	if _popup.visible:
		_suppress_next_restore = true
		_popup.hide()
	else:
		open_toolbox()

func open_toolbox() -> void:
	if _popup == null:
		return

	var rect := get_global_rect()
	_popup.position = Vector2i(int(rect.position.x), int(rect.position.y + rect.size.y + _scaled(4.0)))
	_popup.popup()

func close_toolbox() -> void:
	if _popup != null:
		_suppress_next_restore = true
		_popup.hide()

func set_keep_open_after_selection(enabled: bool) -> void:
	keep_open_after_selection = enabled
	_apply_popup_persistence()

func get_keep_open_after_selection() -> bool:
	return keep_open_after_selection

func toggle_keep_open_after_selection() -> bool:
	set_keep_open_after_selection(not keep_open_after_selection)
	return keep_open_after_selection

func preserve_for_build_confirm_click() -> void:
	if keep_open_after_selection:
		call_deferred("_restore_toolbox_popup")

func _collect_popup_menus(menu: PopupMenu) -> void:
	if menu == null:
		return
	_popup_menus.append(menu)
	for child in menu.get_children():
		if child is PopupMenu:
			_collect_popup_menus(child as PopupMenu)

func _apply_popup_persistence() -> void:
	for menu in _popup_menus:
		if not is_instance_valid(menu):
			continue
		_set_popup_property_if_present(menu, "hide_on_item_selection", not keep_open_after_selection)
		_set_popup_property_if_present(menu, "hide_on_checkable_item_selection", not keep_open_after_selection)
		_set_popup_property_if_present(menu, "hide_on_state_item_selection", not keep_open_after_selection)

func _apply_popup_theme() -> void:
	for menu in _popup_menus:
		if not is_instance_valid(menu):
			continue
		if UiScale.is_small(_ui_scale):
			_clear_popup_theme(menu)
			continue
		menu.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(6), _scaled_int(1)))
		menu.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(4), _scaled_int(1)))
		menu.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		menu.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
		menu.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
		menu.add_theme_font_size_override("font_size", UiScale.font_size(13, _ui_scale))
		menu.add_theme_constant_override("v_separation", _scaled_int(4))
		menu.add_theme_constant_override("item_start_padding", _scaled_int(12))
		menu.add_theme_constant_override("item_end_padding", _scaled_int(18))

func _clear_popup_theme(menu: PopupMenu) -> void:
	menu.remove_theme_stylebox_override("panel")
	menu.remove_theme_stylebox_override("hover")
	menu.remove_theme_color_override("font_color")
	menu.remove_theme_color_override("font_hover_color")
	menu.remove_theme_color_override("font_disabled_color")
	menu.remove_theme_font_size_override("font_size")
	menu.remove_theme_constant_override("v_separation")
	menu.remove_theme_constant_override("item_start_padding")
	menu.remove_theme_constant_override("item_end_padding")

func _set_popup_property_if_present(menu: PopupMenu, property_name: String, value: bool) -> void:
	for property in menu.get_property_list():
		if str(property.get("name", "")) == property_name:
			menu.set(property_name, value)
			return

func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)

func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)

func _on_build_selected(id: int, menu:PopupMenu) -> void:
	var idx := menu.get_item_index(id)
	var key := menu.get_item_metadata(idx) as StringName
	
	var scene = BuildRegistry.get_scene(key)
	if scene:
		build_requested.emit(scene)
		if keep_open_after_selection:
			call_deferred("_restore_toolbox_popup")
	else:
		push_warning("No registered for key: %s" % key)
		return

func _restore_toolbox_popup() -> void:
	if keep_open_after_selection and _popup != null and not _popup.visible:
		open_toolbox()

func _on_toolbox_popup_hidden() -> void:
	if _suppress_next_restore:
		_suppress_next_restore = false
		return
	if keep_open_after_selection and _is_build_mode_active():
		call_deferred("_restore_toolbox_popup")

func _is_build_mode_active() -> bool:
	if BuildManager == null:
		return false
	if BuildManager.has_method("is_build_mode_active"):
		return bool(BuildManager.call("is_build_mode_active"))
	if "is_building" in BuildManager:
		return bool(BuildManager.is_building)
	return false
