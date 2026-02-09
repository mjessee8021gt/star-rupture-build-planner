extends Resource

class_name RecipeVariant

@export var id : StringName
@export var display_name : String
@export var output_qty : int

@export var inputs: Array[ItemStack] = []
@export var outputs: Array[ItemStack] = []
