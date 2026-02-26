extends Node
class_name ProductionLedger

signal totals_changed(net_totals: Dictionary) # {Stringname: float}

# Net per-minute (or per tick) totals across the whole plan
var net_totals: Dictionary = {} #key: StringName, Value: Float

#track per-building contributions so removal of buildings is easy and debuggable
var by_source: Dictionary = {} # source_id -> {resource_key: delta}

func add_source(source_id: int, source: Object, deltas: Dictionary) -> void:
	if source == null or not source.has_method("get_production_deltas"):
		return
	
	# deltas: {&"titanium_ore": -30, &"titanium_bar": +30}
	if by_source.has(source_id):
		remove_source(source_id)
		
	by_source[source_id] = deltas.duplicate(true)
	
	for k in deltas.keys():
		net_totals[k] = float(net_totals.get(k, 0.0)) + float(deltas[k])
		
	totals_changed.emit(net_totals)

func remove_source(source_id: int) -> void:
	if not by_source.has(source_id):
		return
	
	var deltas: Dictionary = by_source[source_id]
	for k in deltas.keys():
		net_totals[k] = float(net_totals.get(k, 0.0)) - float(deltas[k])
		if is_equal_approx(float(net_totals[k]), 0.0):
			net_totals.erase(k)
		
	by_source.erase(source_id)
	totals_changed.emit(net_totals)
