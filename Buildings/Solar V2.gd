extends Building

@export var footprint_primary := Vector2i(3, 3)
@export var footprint_alt := Vector2i(3, 3)
@export var recipe : Recipe
@export var heat := 250
@export var power := 1000
@export var available_recipes: Array[Recipe] = []

var footprint := Vector2i(3, 3)

func _ready() -> void:
	add_to_group("buildings")

func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$TitleLabel.position = Vector2(24, 1)
		$outputBox.position = Vector2(27, 61)
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$TitleLabel.position = Vector2(24, 1)
		$outputBox.position = Vector2(27, 61)
		footprint = footprint_primary
		is_alternate = false
