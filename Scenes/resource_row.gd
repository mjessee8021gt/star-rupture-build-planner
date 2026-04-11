extends HBoxContainer

const PlannerPalette = preload("res://Scripts/palette.gd")


func _ready() -> void:
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
			label.add_theme_color_override("font_color", PlannerPalette.TEXT_PRIMARY)
		else:
			label.add_theme_color_override("font_color", PlannerPalette.TEXT_MUTED)

func set_label_values(resourceName : String, grossRate : float, netRate : float) -> void:
	$TextureRect/ResourceName.text = resourceName
	$TextureRect/GrossRateLabel.text = str(grossRate)
	$TextureRect/NetRateLabel.text = str(netRate)
	
