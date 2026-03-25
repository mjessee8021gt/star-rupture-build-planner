extends Node
#BUildingRegistry holds the enumaeration for all buildings in the tool. This ensures enumeration IDs remain constant through the entire program.
class_name BuildRegistry
const BUILDINGS := {
	&"smelter": preload("res://Buildings/Smelter.tscn"),
	&"ore_excavator": preload("res://Buildings/OreExcavator.tscn"),
	&"fabricator": preload("res://Buildings/Fabricator.tscn"),
	&"furnace": preload("res://Buildings/Furnace.tscn"),
	&"mega_press": preload("res://Buildings/MegaPress.tscn"),
	&"assembler": preload("res://Buildings/Assembler.tscn"),
	&"compounder": preload("res://Buildings/Compounder.tscn"),
	&"refinery": preload("res://Buildings/Refinery.tscn"),
	&"rail_support": preload("res://Buildings/rail_support.tscn"),
	&"rail_connector": preload("res://Buildings/rail_connector.tscn"),
	&"rail_modulator_3": preload("res://Buildings/rail_modulator_3.tscn"),
	&"receiver":preload("res://Buildings/Receiver.tscn"),
	&"dispatcher": preload("res://Buildings/Dispatcher.tscn"),
	&"helium_extractor": preload("res://Buildings/Helium Extractor.tscn"),
	&"sulfur_extractor": preload("res://Buildings/Sulfur Extractor.tscn"),
	&"solar_v1": preload("res://Buildings/Solar V1.tscn"),
	&"wind_v1": preload("res://Buildings/Wind V1.tscn"),
	&"solar_v2": preload("res://Buildings/Solar V2.tscn"),
	&"wind_v2": preload("res://Buildings/Wind V2.tscn"),
	&"multirail_3": preload("res://Buildings/Multirail_3.tscn"),
	&"multirail_5": preload("res://Buildings/Multirail_5.tscn"),
	&"rail_modulator_5": preload("res://Buildings/rail_modulator_5.tscn"),
	&"orbital_launcher": preload("res://Buildings/Orbital_launcher.tscn"),
	&"storage_v1": preload("res://Buildings/Storage_v1.tscn"),
	&"storage_v2": preload("res://Buildings/Storage_v2.tscn"),
	&"teleporter": preload("res://Buildings/Teleporter.tscn"),
	&"habitat": preload("res://Buildings/Habitat.tscn"),
	&"large_habitat": preload("res://Buildings/Large Habitat.tscn")
}

static func get_scene(key: StringName) -> PackedScene:
	return BUILDINGS.get(key, null)
