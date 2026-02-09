extends Resource

class_name Recipe

@export var id: StringName
@export var display_name : String
var craft_time: float

#Item_id > Ammount
@export var inputs : Array[ItemStack] = []
@export var outputs : Array[ItemStack] = []
@export var variants : Array[RecipeVariant] = []
