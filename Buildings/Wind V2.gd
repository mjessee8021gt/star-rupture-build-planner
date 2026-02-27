extends Building

var footprint := Vector2i(4, 4)
@export var footprint_primary := Vector2i(4,4)
@export var footprint_alt := Vector2i(4, 4)

@export var recipe : Recipe

@export var heat := 0
@export var power := 2000

@export var available_recipes: Array[Recipe] = []

func _ready() -> void:
	add_to_group("buildings")
	
func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		$TitleLabel.position = Vector2(40, 14)
		$outputBox.position = Vector2(46, 74)
		footprint = footprint_alt
		is_alternate = true
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		$TitleLabel.position = Vector2(40, 14)
		$outputBox.position = Vector2(46, 74)
		footprint = footprint_primary
		is_alternate = false
