extends PanelContainer

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var rows_parent: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var _row_scene: PackedScene = preload("res://Scenes/ResourceRow.tscn")

const RESOURCE_ROW_DEFAULT_SCALE := 1.25
const RESOURCE_ROW_BASE_WIDTH := 398.0

# Resource_key (StringName) -> ResourceRow instance
var rows: Dictionary = {}
var _row_layout_refresh_queued := false

func _ready() -> void:
	if scroll_container != null:
		scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_container.resized.connect(_queue_row_layout_refresh)
	if rows_parent != null:
		rows_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows_parent.resized.connect(_queue_row_layout_refresh)
	resized.connect(_queue_row_layout_refresh)

	# ProdLedger is expected to be an autoload. If it's not present, fail loudly.
	if not get_tree().root.has_node("ProdLedger"):
		push_error("ProdLedger autoload not found at /root/ProdLedger. Production panel will not update.")
		return

	var ledger := get_node("/root/ProdLedger")
	ledger.totals_changed.connect(_on_totals_changed)
	_on_totals_changed(ledger.net_totals, ledger.gross_totals, ledger.gross_negative_totals)

func _on_totals_changed(net_totals: Dictionary, gross_totals: Dictionary, gross_negative_totals: Dictionary) -> void:
	# Remove rows that have a gross production of zero.
	var existing_keys := rows.keys()
	for key in existing_keys:
		var gross_positive_rate := float(gross_totals.get(key, 0.0))
		var gross_negative_rate := float(gross_negative_totals.get(key, 0.0))
		if is_equal_approx(gross_positive_rate, 0.0) and is_equal_approx(gross_negative_rate, 0.0):
			var row_to_remove = rows[key]
			if is_instance_valid(row_to_remove):
				row_to_remove.queue_free()
			rows.erase(key)

	# Add/update rows for present totals
	var display_keys: Dictionary = {}
	for key in gross_totals.keys():
		display_keys[key] = true
	for key in gross_negative_totals.keys():
		display_keys[key] = true
	for key in net_totals.keys():
		display_keys[key] = true
		
	for key in display_keys.keys():
		var gross_positive := float(gross_totals.get(key, 0.0))
		var gross_rate := gross_positive
		var net_rate := float(net_totals.get(key, 0.0))
		
		if is_equal_approx(gross_rate, 0.0) and is_equal_approx(net_rate, 0.0):
			continue

		var row
		if not rows.has(key) or not is_instance_valid(rows[key]):
			row = _row_scene.instantiate()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows_parent.add_child(row)
			rows[key] = row
			row.name = str(key)
		else:
			row = rows[key]

		_apply_row_layout(row)

		# Try a couple common APIs so ResourceRow can evolve without breaking this panel.
		if row.has_method("set_rate"):
			row.set_rate(net_rate)
		elif row.has_method("set_label_values"):
			# Convention: (resource_name, produced, consumed) OR (resource_name, in, out)
			# Pass gross and net separately so both labels can reflect true values.
			row.set_label_values(str(key), gross_rate, net_rate)
		elif row.has_method("set_value"):
			row.set_value(net_rate)

	_sort_rows()
	_queue_row_layout_refresh()

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

func refresh_row_layout() -> void:
	_row_layout_refresh_queued = false
	for row in rows.values():
		if is_instance_valid(row):
			_apply_row_layout(row)

func _queue_row_layout_refresh() -> void:
	if _row_layout_refresh_queued:
		return
	_row_layout_refresh_queued = true
	call_deferred("refresh_row_layout")

func _apply_row_layout(row: Node) -> void:
	if row == null:
		return

	var target_width := _get_row_target_width()
	var row_scale = max(target_width / RESOURCE_ROW_BASE_WIDTH, 0.001)
	if row is Control:
		(row as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if row.has_method("set_display_width"):
		row.set_display_width(target_width, row_scale)
	elif row.has_method("set_display_scale"):
		row.set_display_scale(Vector2(row_scale, row_scale))
	else:
		row.scale = Vector2(row_scale, row_scale)

func _get_row_target_width() -> float:
	var target_width := 0.0

	if size.x > 1.0:
		target_width = size.x
		var panel_style := get_theme_stylebox("panel")
		if panel_style != null:
			target_width -= max(panel_style.get_content_margin(SIDE_LEFT), 0.0)
			target_width -= max(panel_style.get_content_margin(SIDE_RIGHT), 0.0)

	if scroll_container != null:
		var vertical_scroll_bar := scroll_container.get_v_scroll_bar()
		if vertical_scroll_bar != null and vertical_scroll_bar.visible:
			target_width -= vertical_scroll_bar.size.x
		if target_width <= 1.0:
			target_width = scroll_container.size.x
	if target_width <= 1.0 and rows_parent != null:
		var rows_parent_parent := rows_parent.get_parent() as Control
		if rows_parent_parent != null:
			target_width = rows_parent_parent.size.x
	if target_width <= 1.0:
		target_width = RESOURCE_ROW_BASE_WIDTH * RESOURCE_ROW_DEFAULT_SCALE
	return max(target_width, 1.0)
