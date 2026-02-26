extends Node
#BUildingRegistry holds the enumaeration for all buildings in the tool. This ensures enumeration IDs remain constant through the entire program.
class_name BuildRegistry
const BUILDINGS := {
	&"smelter": preload("res://Buildings/smelter.tscn"),
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
	&"dispatcher": preload("res://Buildings/Dispatcher.tscn")
}


static func get_scene(key: StringName) -> PackedScene:
	return BUILDINGS.get(key, null)
