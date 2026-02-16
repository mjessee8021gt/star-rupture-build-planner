extends PanelContainer

@onready var rows_parent: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var _row_scene: PackedScene = preload("res://Scenes/ResourceRow.tscn")

# Resource_key (StringName) -> ResourceRow instance
var rows: Dictionary = {}

func _ready() -> void:
	# ProdLedger is expected to be an autoload. If it's not present, fail loudly.
	if not get_tree().root.has_node("ProdLedger"):
		push_error("ProdLedger autoload not found at /root/ProdLedger. Production panel will not update.")
		return

	var ledger := get_node("/root/ProdLedger")
	ledger.totals_changed.connect(_on_totals_changed)
	_on_totals_changed(ledger.net_totals)

func _on_totals_changed(net_totals: Dictionary) -> void:
	# Remove rows that are no longer present (or are effectively zero)
	var existing_keys := rows.keys()
	for key in existing_keys:
		var still_present := net_totals.has(key) and not is_equal_approx(float(net_totals[key]), 0.0)
		if not still_present:
			var row_to_remove = rows[key]
			if is_instance_valid(row_to_remove):
				row_to_remove.queue_free()
			rows.erase(key)

	# Add/update rows for present totals
	for key in net_totals.keys():
		var rate := float(net_totals[key])
		if is_equal_approx(rate, 0.0):
			continue

		var row
		if not rows.has(key) or not is_instance_valid(rows[key]):
			row = _row_scene.instantiate()
			rows_parent.add_child(row)
			rows[key] = row
			row.name = str(key)
		else:
			row = rows[key]

		# Try a couple common APIs so ResourceRow can evolve without breaking this panel.
		if row.has_method("set_rate"):
			row.set_rate(rate)
		elif row.has_method("set_label_values"):
			# Convention: (resource_name, produced, consumed) OR (resource_name, in, out)
			# We pass the signed rate in both slots so your ResourceRow can decide how to display it.
			row.set_label_values(str(key), rate, rate)
		elif row.has_method("set_value"):
			row.set_value(rate)

	_sort_rows()

func _sort_rows() -> void:
	if rows_parent == null:
		return

	var children := rows_parent.get_children()
	children.sort_custom(func(a, b):
		var ar = a.get_rate() if a.has_method("get_rate") else 0.0
		var br = b.get_rate() if b.has_method("get_rate") else 0.0
		if (ar < 0) != (br < 0):
			return ar < 0
		var an = a.get_resource_name() if a.has_method("get_resource_name") else a.name
		var bn = b.get_resource_name() if b.has_method("get_resource_name") else b.name
		return str(an) < str(bn)
	)

	for i in range(children.size()):
		rows_parent.move_child(children[i], i)
