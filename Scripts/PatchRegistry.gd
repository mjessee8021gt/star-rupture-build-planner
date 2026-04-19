extends Node
# PatchRegistry holds the patch note resources shown in the patch notes panel.
class_name PatchRegistry
const PATCHES := {
	&"v0_1_0": preload("res://Patch Notes/0_1_0t.tres"),
	&"v0_1_1": preload("res://Patch Notes/0_1_1c.tres"),
	&"v0_1_2": preload("res://Patch Notes/0_1_2.tres"),
	&"v0_1_3": preload("res://Patch Notes/0_1_3.tres"),
	&"v0_2_0": preload("res://Patch Notes/0_2_0.tres"),
	&"v_0_3_0": preload("res://Patch Notes/0_3_0.tres"),
	&"v_0_4_0": preload("res://Patch Notes/0_4_0.tres")
}

static func get_scene(key: StringName) -> Resource:
	return PATCHES.get(key, null)
