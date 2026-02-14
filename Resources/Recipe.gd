extends Resource

class_name Recipe

@export var id: StringName
@export var display_name : String
var craft_time: float

#Item_id > Ammount
@export var inputs : Array[ItemStack] = []
@export var outputs : Array[ItemStack] = []
@export var variants : Array[RecipeVariant] = []

func get_deltas() -> Dictionary:
	var deltas : Dictionary = {}
	
	for s in inputs:
		if s == null:
			continue
		var key: StringName = s.id
		deltas[key] = float(deltas.get(key, 0.0)) - float(s.qty)
		
	for s in outputs:
		if s == null:
			continue
		var key: StringName = s.id
		deltas[key] = float(deltas.get(key, 0.0)) + float(s.qty)
	return deltas
