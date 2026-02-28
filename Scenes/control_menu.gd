extends MenuButton

@export var popup_path: NodePath   # Drag your PopupPanel here in inspector
@export var list_path: NodePath    # Drag the VBoxContainer (ActionsList) here
@export var hide_prefixes: Array[String] = ["ui_"]
@export var show_only_prefixes: Array[String] = [] # empty = show all

@onready var popup: PopupPanel = get_node(popup_path)
@onready var list_vbox: VBoxContainer = get_node(list_path)

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if popup.visible:
		popup.hide()
		return

	_refresh_list()
	_position_popup()
	popup.popup()

func _position_popup() -> void:
	# Position just below the button
	var rect := get_global_rect()
	popup.position = Vector2i(rect.position.x, rect.position.y + rect.size.y)

func _refresh_list() -> void:
	# Clear previous rows
	for child in list_vbox.get_children():
		child.queue_free()

	var actions := InputMap.get_actions()
	actions.sort()

	
	for action_name in actions:
		var events := InputMap.action_get_events(action_name)
		var binding_text := _events_to_string(events)
		var a := String(action_name)
		
		#SHOW-only filter (if it's engaged)
		if show_only_prefixes.size() > 0:
			var ok := false
			for prefix in show_only_prefixes:
				if a.begins_with(prefix):
					ok = true
					break
			if not ok:
				continue
		
		#HIDE filter
		for prefix in hide_prefixes:
			if a.begins_with(prefix):
				continue
		list_vbox.add_child(_make_row(String(action_name), binding_text))

func _make_row(action_name: String, bindings: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var left := Label.new()
	left.text = action_name
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var right := Label.new()
	right.text = bindings
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(left)
	row.add_child(right)

	return row

func _events_to_string(events: Array[InputEvent]) -> String:
	if events.is_empty():
		return "—"

	var parts: Array[String] = []
	for e in events:
		parts.append(e.as_text())

	return ", ".join(parts)
