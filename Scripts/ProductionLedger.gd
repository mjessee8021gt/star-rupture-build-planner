extends Node
class_name ProductionLedger

signal totals_changed(net_totals: Dictionary, gross_totals: Dictionary, gross_negative_totals: Dictionary) # {Stringname: float}

# Net per-minute (or per tick) totals across the whole plan
var net_totals: Dictionary = {} #key: StringName, Value: Float

#Gross production totals (Only positive production rates)
var gross_totals: Dictionary = {} #key: StringName, value: float

#gross consumption totals (Negative rates only)
var gross_negative_totals: Dictionary = {} #key: StringName, value: float

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
		var delta := float(deltas[k])
		net_totals[k] = float(net_totals.get(k, 0.0)) + delta
		if is_equal_approx(float(net_totals[k]), 0.0):
			net_totals.erase(k)
		
		if delta > 0.0:
			gross_totals[k] = float(gross_totals.get(k, 0.0)) + delta
		elif delta < 0.0:
			gross_negative_totals[k] = float(gross_negative_totals.get(k, 0.0)) - delta
			
	totals_changed.emit(net_totals, gross_totals, gross_negative_totals)

func remove_source(source_id: int) -> void:
	if not by_source.has(source_id):
		return
	
	var deltas: Dictionary = by_source[source_id]
	for k in deltas.keys():
		var delta := float(deltas[k])
		net_totals[k] = float(net_totals.get(k, 0.0)) - delta
		if is_equal_approx(float(net_totals[k]), 0.0):
			net_totals.erase(k)
			
		if delta > 0.0:
			gross_totals[k] = float(gross_totals.get(k, 0.0)) - delta
			if is_equal_approx(float(gross_totals[k]), 0.0):
				gross_totals.erase(k)
		elif delta < 0.0:
			gross_negative_totals[k] = float(gross_negative_totals.get(k, 0.0)) + delta
			if gross_negative_totals[k] <= 0.0 or is_equal_approx(float(gross_negative_totals[k]), 0.0):
				gross_negative_totals.erase(k)
		
	by_source.erase(source_id)
	totals_changed.emit(net_totals, gross_totals, gross_negative_totals)
