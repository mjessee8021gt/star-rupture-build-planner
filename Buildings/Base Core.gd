extends Building

@export var footprint_primary := Vector2i(4, 4)
@export var footprint_alt := Vector2i(4, 4)
@export var recipe : Recipe
@export var heat := -1000
@export var power := 0
@export var available_recipes: Array[Recipe] = []

const CORE_LEVEL_HEAT_VALUES := [
	-1000,
	-2500,
	-4000,
	-6000,
	-10000,
]

var footprint := Vector2i(4, 4)

func _ready() -> void:
	add_to_group("buildings")
	_initialize_core_level()
	
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
	heat = _get_heat_for_core_level(index)
	_apply_heat_delta_to_plan(heat - old_heat)


func _initialize_core_level() -> void:
	var core_level := get_node_or_null("CoreLevel") as OptionButton
	if core_level == null or core_level.item_count <= 0:
		heat = _get_heat_for_core_level(0)
		return

	if core_level.selected < 0:
		core_level.select(0)
	heat = _get_heat_for_core_level(core_level.selected)


func _get_heat_for_core_level(index: int) -> int:
	if index >= 0 and index < CORE_LEVEL_HEAT_VALUES.size():
		return int(CORE_LEVEL_HEAT_VALUES[index])
	return int(CORE_LEVEL_HEAT_VALUES[CORE_LEVEL_HEAT_VALUES.size() - 1])


func _apply_heat_delta_to_plan(delta: int) -> void:
	if delta == 0:
		return
	if get_parent() == null or get_parent().name != "buildings":
		return
	var main_scene := get_tree().current_scene
	if main_scene == null:
		return
		
	var heat_label: Label = main_scene.get_node_or_null("./Camera2D/CanvasLayer/Panel/HeatLabel")
	if heat_label == null:
		return

	heat_label.text = str(int(heat_label.text) + delta)
	
