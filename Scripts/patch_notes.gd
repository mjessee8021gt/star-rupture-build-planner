extends MenuButton

@export var panel_scene: PackedScene

var _panel: PopupPanel

func _ready() -> void:
	# Make the MenuButton act like a toggle button for the panel.
	pressed.connect(_toggle_panel)

func _toggle_panel() -> void:
	if _panel == null:
		if panel_scene == null:
			push_warning("MenuButton: panel_scene not set.")
			return

		_panel = panel_scene.instantiate() as PopupPanel
		get_tree().root.add_child(_panel)
		
		_panel.hide()
	
	if _panel.visible:
		_panel.hide()
	else:
		call_deferred("_open_panel")

func _open_panel() -> void:
	if _panel == null:
		return
	_panel.popup_centered(Vector2i(900, 650))
	if _panel.has_method("refresh"):
		_panel.call("refresh")
