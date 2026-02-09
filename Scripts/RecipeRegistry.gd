extends Node

class_name RecipeRegistry

const RECIPES := {
	&"calcium_ore": preload("res://Recipes/mine_Calcium_impure.tres")
}


static func get_scene(key: StringName) -> PackedScene:
	return RECIPES.get(key, null)
