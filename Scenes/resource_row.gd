extends HBoxContainer

func set_label_values(resourceName : String, grossRate : int, netRate : int) -> void:
	$TextureRect/ResourceName.text = resourceName
	$TextureRect/GrossRateLabel.text = str(grossRate)
	$TextureRect/NetRateLabel.text = str(netRate)
	
