extends Node
#BUildingRegistry holds the enumaeration for all buildings in the tool. This ensures enumeration IDs remain constant through the entire program.
class_name PatchRegistry
const PATCHES := {
	&"v0_1_0": preload("res://Patch Notes/0_1_0t.tres"),
	&"v0_1_1": preload("res://Patch Notes/0_1_1c.tres"),
	&"v0_1_2": preload("res://Patch Notes/0_1_2.tres"),
	&"v0_1_3": preload("res://Patch Notes/0_1_3.tres")
}

static func get_scene(key: StringName) -> PackedScene:
	return PATCHES.get(key, null)
