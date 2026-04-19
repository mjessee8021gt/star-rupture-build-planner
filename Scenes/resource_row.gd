extends Control

const Palette = preload("res://Scripts/palette.gd")
const BASE_ROW_SIZE := Vector2(398.0, 99.0)

var _display_scale := Vector2.ONE

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_display_scale()

	for label_path in [
		"TextureRect/ResourceName",
		"TextureRect/GrossProd",
		"TextureRect/NetProd",
		"TextureRect/GrossRateLabel",
		"TextureRect/NetRateLabel",
	]:
		var label := get_node_or_null(label_path) as Label
		if label == null:
			continue

		if label_path.ends_with("ResourceName"):
			label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		else:
			label.add_theme_color_override("font_color", Palette.TEXT_MUTED)

func set_display_scale(display_scale: Vector2) -> void:
	_display_scale = display_scale
	_apply_display_scale()

func set_display_width(display_width: float, vertical_scale: float) -> void:
	_display_scale = Vector2(max(display_width / BASE_ROW_SIZE.x, 0.001), max(vertical_scale, 0.001))
	_apply_display_scale()

func _apply_display_scale() -> void:
	var texture_rect := get_node_or_null("TextureRect") as TextureRect
	if texture_rect == null:
		return

	custom_minimum_size = Vector2(
		BASE_ROW_SIZE.x * _display_scale.x,
		BASE_ROW_SIZE.y * _display_scale.y
	)
	texture_rect.position = Vector2.ZERO
	texture_rect.size = BASE_ROW_SIZE
	texture_rect.scale = _display_scale
	update_minimum_size()

func set_label_values(resourceName : String, grossRate : float, netRate : float) -> void:
	$TextureRect/ResourceName.text = resourceName
	$TextureRect/GrossRateLabel.text = str(grossRate)
	$TextureRect/NetRateLabel.text = str(netRate)
	
