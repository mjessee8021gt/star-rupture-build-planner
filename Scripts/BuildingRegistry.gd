extends Node
#BUildingRegistry holds the enumaeration for all buildings in the tool. This ensures enumeration IDs remain constant through the entire program.
class_name BuildRegistry
const BUILDINGS := {
	&"smelter": preload("res://Buildings/smelter.tscn"),
	&"ore_excavator": preload("res://Buildings/OreExcavator.tscn"),
	&"fabricator": preload("res://Buildings/Fabricator.tscn"),
	&"furnace": preload("res://Buildings/Furnace.tscn")
}


static func get_scene(key: StringName) -> PackedScene:
	return BUILDINGS.get(key, null)
