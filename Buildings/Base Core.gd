extends Building

@export var footprint_primary := Vector2i(4, 4)
@export var footprint_alt := Vector2i(4, 4)
@export var recipe : Recipe
@export var heat := -1000
@export var power := 0
@export var available_recipes: Array[Recipe] = []

var footprint := Vector2i(4, 4)

func _ready() -> void:
	add_to_group("buildings")
	
func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		footprint = footprint_primary
		is_alternate = false


func _on_core_level_item_selected(index: int) -> void:
	var old_heat := heat
	
	if index == 0:
		heat = -1000
	elif index == 1:
		heat = -2500
	elif index == 2:
		heat = -4000
	elif index == 3:
		heat = -6000
	else:
		heat = -10000
		
	if get_parent() == null or get_parent().name != "buildings":
		return
	var main_scene := get_tree().current_scene
	if main_scene == null:
		return
		
	var heat_label: Label = main_scene.get_node_or_null("./Camera2D/CanvasLayer/Panel/HeatLabel")
	if heat_label == null:
		return

	heat_label.text = str(int(heat_label.text) + (heat - old_heat))
	
