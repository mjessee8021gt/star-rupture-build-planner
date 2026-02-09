extends Node
#BUildingRegistry holds the enumaeration for all buildings in the tool. This ensures enumeration IDs remain constant through the entire program.

const BUILDINGS := {
	&"smelter": preload("res://Buildings/smelter.tscn"),
	&"ore_excavator": preload("res://Buildings/OreExcavator.tscn")
}


static func get_scene(key: StringName) -> PackedScene:
	return BUILDINGS.get(key, null)
