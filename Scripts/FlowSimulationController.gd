class_name FlowSimulationController
extends RefCounted

# Owns the experimental flow-simulation view: the enabled toggle, the persisted
# simulator state cache, the per-frame refresh that re-runs the simulator and pushes
# the result to PathManager for rail-badge coloring, and the active flow-layer mode.
# Extracted from main.gd. The host (main) supplies the live scene refs; PathManager
# owns the actual badge rendering. main keeps the command->layer-mode bridge
# (FLOW_LAYER_COMMANDS) and thin delegates so menu commands and cross-controller
# callers (SaveLoadController) keep working.

const FLOW_GRAPH_BUILDER := preload("res://Scripts/FlowGraphBuilder.gd")
const FLOW_SIMULATOR := preload("res://Scripts/FlowSimulator.gd")

var _host: Node = null
var _enabled := false
var _refresh_queued := false
var _state: Dictionary = {}
var _last_result: Dictionary = {}


func _init(host: Node) -> void:
	_host = host


func setup() -> void:
	var path_manager: Node = _host.path_manager
	if path_manager != null:
		if path_manager.has_method("set_flow_simulation_enabled"):
			path_manager.call("set_flow_simulation_enabled", false)
		if path_manager.has_signal("rail_graph_changed"):
			var refresh_callable := Callable(self, "queue_refresh")
			if not path_manager.is_connected("rail_graph_changed", refresh_callable):
				path_manager.connect("rail_graph_changed", refresh_callable)


func is_enabled() -> bool:
	return _enabled


func toggle() -> void:
	_enabled = not _enabled
	var path_manager: Node = _host.path_manager
	if path_manager != null and path_manager.has_method("set_flow_simulation_enabled"):
		path_manager.call("set_flow_simulation_enabled", _enabled)
	if _enabled:
		_state.clear()
		refresh_view()
	elif path_manager != null and path_manager.has_method("clear_flow_simulation_result"):
		path_manager.call("clear_flow_simulation_result")


func select_layer(mode: int) -> void:
	if not _enabled:
		return
	var path_manager: Node = _host.path_manager
	if path_manager == null or not path_manager.has_method("set_flow_layer_mode"):
		return
	path_manager.call("set_flow_layer_mode", mode)


func get_active_layer_mode() -> int:
	var path_manager: Node = _host.path_manager
	if path_manager != null and path_manager.has_method("get_flow_layer_mode"):
		return int(path_manager.call("get_flow_layer_mode"))
	return 0


func queue_refresh() -> void:
	if not _enabled or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("refresh_view")


func refresh_view() -> void:
	_refresh_queued = false
	if not _enabled:
		return
	var simulation := _run_current_simulation()
	if not bool(simulation.get("ok", false)):
		push_warning(str(simulation.get("message", "Flow Sim failed.")))


func clear_cache() -> void:
	_state.clear()
	_last_result.clear()
	var path_manager: Node = _host.path_manager
	if path_manager != null and path_manager.has_method("clear_flow_simulation_result"):
		path_manager.call("clear_flow_simulation_result")


func _run_current_simulation() -> Dictionary:
	var graph: Dictionary = FLOW_GRAPH_BUILDER.build_from_scene(_host.buildings_root, _host.path_manager)
	var simulator: RefCounted = FLOW_SIMULATOR.new()
	var result = simulator.call("simulate", graph, 1.0, _state)
	if not (result is Dictionary):
		return {
			"ok": false,
			"graph": graph,
			"message": "Flow Sim: simulator returned an invalid result.",
		}

	_last_result = (result as Dictionary).duplicate(true)
	var next_state = _last_result.get("state", {})
	_state = next_state.duplicate(true) if next_state is Dictionary else {}
	var path_manager: Node = _host.path_manager
	if path_manager != null and path_manager.has_method("set_flow_simulation_result"):
		path_manager.call("set_flow_simulation_result", _last_result)

	return {
		"ok": true,
		"graph": graph,
		"result": _last_result,
	}
