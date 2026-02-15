extends PanelContainer

@onready var rows_parent: VBoxContainer = $ScrollContainer/VBoxContainer

var rows : Dictionary = {} #Resource_key -> resourceRow Instance

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	ProdLedger.totals_changed.connect(_on_totals_changed)
	_on_totals_changed(ProdLedger.net_totals)
	
func _on_totals_changed(net_totals: Dictionary) -> void:
	for key in rows.keys():
		if not net_totals.has(key):
			rows[key] = 0.0
			rows.erase(key)
			
	for key in net_totals.keys():
		if not rows.has(key):
			var row := preload("res://Scenes/ResourceRow.tscn").instantiate()
			rows_parent.add_child(row)
			rows[key] = row
			row.name = str(key)
			row.set_label_values(row.name, 123, 123)
			
		rows[key] = float(net_totals[key])
	_sort_rows()
	
func _sort_rows() -> void:
	if rows_parent == null:
		return
	
	var children := rows_parent.get_children()
	children.sort_custom(func(a, b):
		var ar = a.get_rate()
		var br = b.get_rate()
		if (ar < 0) != (br < 0):
			return ar < 0
		return a.get_resource_name() < b.get_resource_name()
	)
	
	for i in children.size():
		rows_parent.move_child(children[i], i)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
