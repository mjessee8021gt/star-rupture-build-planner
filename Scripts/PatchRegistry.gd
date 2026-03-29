extends Resource
#BUildingRegistry holds the enumaeration for all buildings in the tool. This ensures enumeration IDs remain constant through the entire program.
class_name PatchRegistry
@export var patch_notes: Array[PatchNote] = []

func get_patch_notes() ->Array[PatchNote]:
	var out : Array[PatchNote] = []
	for note in patch_notes:
		if note != null:
			out.append(note)
	return out
