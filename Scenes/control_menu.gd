extends MenuButton

##------OnReady variables------##
@onready var popup: PopupPanel = get_node(popup_path)
@onready var list_vbox: VBoxContainer = get_node(list_path)

##------Exported Variables-----##
@export var popup_path: NodePath   # Drag your PopupPanel here in inspector
@export var list_path: NodePath    # Drag the VBoxContainer (ActionsList) here
@export var hide_prefixes: Array[String] = ["ui_", "Show"]
@export var show_only_prefixes: Array[String] = [] # empty = show all

##------Object Variables-------##
var rect := get_global_rect()

func _ready() -> void:
	pressed.connect(_on_pressed)
	popup.hide()

func _on_pressed() -> void:
	if popup.visible:
		popup.hide()
		return

	_refresh_list()
	_position_popup()
	popup.popup()

func _position_popup() -> void:
	# We are adjusting the position of the actual display window to be just off to the right of the button
	popup.position = Vector2i(rect.position.x + 50, rect.position.y - (4.45 * rect.size.y))

func _refresh_list() -> void:
	# As we open the window, we're going to clear all previous rows
	for child in list_vbox.get_children():
		child.queue_free()

	#grabbing a full list of inputs from the input map
	var actions := InputMap.get_actions()
	actions.sort()

	#we're going to walk through each of the inputs 1 by 1 and compare them against our display filter parameters.
	for action_name in actions:
		var events := InputMap.action_get_events(action_name)
		var binding_text := _events_to_string(events)
		var a := String(action_name)
		
		#This is our blacklist logic. we're excluding everything that matches our filtered prefixes in the blacklist.
		if _starts_with_any_prefix(a, hide_prefixes):
			continue
		list_vbox.add_child(_make_row(String(action_name), binding_text))
		
func _starts_with_any_prefix(value: String, prefixes: Array[String]) -> bool:
	#This method's sole purpose is to check the blacklist and say "yes this matches" or "no this does not match"
	for prefix in prefixes:
		if value.begins_with(prefix):
			return true
	return false

func _make_row(action_name: String, bindings: String) -> Control:
	#we are populating rows on demand in the menu as we open it, once we identify what passes through the filter.
	var row := HBoxContainer.new()
	var left := Label.new()
	var right := Label.new()
	
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	left.text = action_name
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	right.text = bindings
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(left)
	row.add_child(right)

	return row

func _events_to_string(events: Array[InputEvent]) -> String:
	#we are building out the list of inputs in this function in preparation for the population
	var parts: Array[String] = []
	
	if events.is_empty():
		return "—"

	for e in events:
		parts.append(e.as_text())

	return ", ".join(parts)
