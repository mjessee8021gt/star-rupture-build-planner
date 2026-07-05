extends SceneTree

const FlowSimulatorScript := preload("res://Scripts/FlowSimulator.gd")
const RESULT_PATH := "res://Tools/flow_simulator_test_result.txt"

var _failures := 0
var _failure_messages: Array[String] = []


func _init() -> void:
	print("Running FlowSimulator smoke tests...")
	_run_all()
	if _failures > 0:
		print("FlowSimulator smoke tests failed: %d failure(s)." % _failures)
	else:
		print("FlowSimulator smoke tests passed.")
	_write_result_file()
	quit(1 if _failures > 0 else 0)


func _run_all() -> void:
	_test_capacity_clamps_multi_resource_flow()
	_test_split_distribution_is_even()
	_test_split_overflow_redistributes_to_available_capacity()
	_test_split_only_blocks_after_all_outputs_saturate()
	_test_machine_input_demand_limits_delivered_flow()
	_test_merge_chokepoint_blocks_excess_flow()
	_test_machine_starvation_and_partial_production()
	_test_storage_inventory_updates_over_time()
	_test_loop_detection_warns_without_stopping()


func _test_capacity_clamps_multi_resource_flow() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "source", "kind": "source", "outputs": {&"iron": 120.0, &"copper": 120.0}},
			{"id": "sink", "kind": "machine", "inputs": {&"iron": 120.0, &"copper": 120.0}}
		],
		"edges": [
			{"id": "rail", "from": "source", "to": "sink", "capacity_upm": 120.0}
		]
	})

	var rail: Dictionary = result["edges"]["rail"]
	_expect_close(rail["used_upm"], 120.0, "capacity clamp used flow")
	_expect_close(rail["blocked_upm"], 120.0, "capacity clamp blocked flow")
	_expect_close(rail["delivered_by_resource"][&"iron"], 60.0, "capacity clamp proportional iron")
	_expect_close(rail["delivered_by_resource"][&"copper"], 60.0, "capacity clamp proportional copper")


func _test_split_distribution_is_even() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "source", "kind": "source", "outputs": {&"iron": 120.0}},
			{"id": "a", "kind": "machine", "inputs": {&"iron": 60.0}},
			{"id": "b", "kind": "machine", "inputs": {&"iron": 60.0}}
		],
		"edges": [
			{"id": "rail_a", "from": "source", "to": "a", "capacity_upm": 120.0},
			{"id": "rail_b", "from": "source", "to": "b", "capacity_upm": 120.0}
		]
	})

	_expect_close(result["edges"]["rail_a"]["used_upm"], 60.0, "even split rail a")
	_expect_close(result["edges"]["rail_b"]["used_upm"], 60.0, "even split rail b")


func _test_split_overflow_redistributes_to_available_capacity() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "source", "kind": "source", "outputs": {&"iron": 180.0}},
			{"id": "small_sink", "kind": "machine", "inputs": {&"iron": 60.0}},
			{"id": "large_sink", "kind": "machine", "inputs": {&"iron": 120.0}}
		],
		"edges": [
			{"id": "small_rail", "from": "source", "to": "small_sink", "capacity_upm": 60.0},
			{"id": "large_rail", "from": "source", "to": "large_sink", "capacity_upm": 120.0}
		]
	})

	_expect_close(result["edges"]["small_rail"]["used_upm"], 60.0, "redistribution saturates small rail")
	_expect_close(result["edges"]["small_rail"]["blocked_upm"], 0.0, "small rail overflow redistributes")
	_expect_close(result["edges"]["large_rail"]["used_upm"], 120.0, "redistribution fills large rail")
	_expect_close(result["edges"]["large_rail"]["blocked_upm"], 0.0, "large rail receives redistributed overflow without blocking")


func _test_split_only_blocks_after_all_outputs_saturate() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "source", "kind": "source", "outputs": {&"iron": 300.0}},
			{"id": "left_sink", "kind": "machine", "inputs": {&"iron": 300.0}},
			{"id": "right_sink", "kind": "machine", "inputs": {&"iron": 300.0}}
		],
		"edges": [
			{"id": "left_rail", "from": "source", "to": "left_sink", "capacity_upm": 120.0},
			{"id": "right_rail", "from": "source", "to": "right_sink", "capacity_upm": 120.0}
		]
	})

	_expect_close(result["edges"]["left_rail"]["used_upm"], 120.0, "all-output saturation left used")
	_expect_close(result["edges"]["right_rail"]["used_upm"], 120.0, "all-output saturation right used")
	_expect_close(result["edges"]["left_rail"]["requested_upm"], 150.0, "all-output saturation left pressure")
	_expect_close(result["edges"]["right_rail"]["requested_upm"], 150.0, "all-output saturation right pressure")
	_expect_close(result["edges"]["left_rail"]["blocked_upm"], 30.0, "all-output saturation left blocked")
	_expect_close(result["edges"]["right_rail"]["blocked_upm"], 30.0, "all-output saturation right blocked")


func _test_machine_input_demand_limits_delivered_flow() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "source", "kind": "source", "outputs": {&"iron": 120.0}},
			{"id": "smelter", "kind": "machine", "inputs": {&"iron": 60.0}, "outputs": {&"bar": 60.0}}
		],
		"edges": [
			{"id": "input_rail", "from": "source", "to": "smelter", "capacity_upm": 120.0}
		]
	})

	var rail: Dictionary = result["edges"]["input_rail"]
	_expect_close(rail["used_upm"], 60.0, "machine demand caps delivered rail flow")
	_expect_close(rail["requested_upm"], 60.0, "machine demand caps requested rail flow")
	_expect_close(rail["blocked_upm"], 0.0, "machine demand cap is not rail capacity overflow")
	_expect_close(result["nodes"]["smelter"]["total_incoming_upm"], 60.0, "machine receives only recipe demand")


func _test_merge_chokepoint_blocks_excess_flow() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "left", "kind": "source", "outputs": {&"iron": 120.0}},
			{"id": "right", "kind": "source", "outputs": {&"iron": 120.0}},
			{"id": "junction", "kind": "junction"},
			{"id": "sink", "kind": "machine", "inputs": {&"iron": 240.0}}
		],
		"edges": [
			{"id": "left_in", "from": "left", "to": "junction", "capacity_upm": 120.0},
			{"id": "right_in", "from": "right", "to": "junction", "capacity_upm": 120.0},
			{"id": "out", "from": "junction", "to": "sink", "capacity_upm": 120.0}
		]
	})

	_expect_close(result["nodes"]["junction"]["total_incoming_upm"], 240.0, "junction sums incoming flow")
	_expect_close(result["edges"]["out"]["used_upm"], 120.0, "merge output clamps to downstream capacity")
	_expect_close(result["edges"]["out"]["blocked_upm"], 120.0, "merge output records blocked backup")


func _test_machine_starvation_and_partial_production() -> void:
	var sim := FlowSimulatorScript.new()
	var missing := sim.simulate({
		"nodes": [
			{"id": "iron", "kind": "source", "outputs": {&"iron": 60.0}},
			{"id": "assembler", "kind": "machine", "inputs": {&"iron": 60.0, &"copper": 60.0}, "outputs": {&"parts": 60.0}},
			{"id": "sink", "kind": "machine", "inputs": {&"parts": 60.0}}
		],
		"edges": [
			{"id": "iron_in", "from": "iron", "to": "assembler", "capacity_upm": 120.0},
			{"id": "parts_out", "from": "assembler", "to": "sink", "capacity_upm": 120.0}
		]
	})
	_expect_close(missing["nodes"]["assembler"]["production_scale"], 0.0, "missing ingredient stops production")
	_expect_close(missing["edges"]["parts_out"]["used_upm"], 0.0, "missing ingredient produces no output")

	var partial := sim.simulate({
		"nodes": [
			{"id": "iron", "kind": "source", "outputs": {&"iron": 60.0}},
			{"id": "copper", "kind": "source", "outputs": {&"copper": 30.0}},
			{"id": "assembler", "kind": "machine", "inputs": {&"iron": 60.0, &"copper": 60.0}, "outputs": {&"parts": 60.0}},
			{"id": "sink", "kind": "machine", "inputs": {&"parts": 60.0}}
		],
		"edges": [
			{"id": "iron_in", "from": "iron", "to": "assembler", "capacity_upm": 120.0},
			{"id": "copper_in", "from": "copper", "to": "assembler", "capacity_upm": 120.0},
			{"id": "parts_out", "from": "assembler", "to": "sink", "capacity_upm": 120.0}
		]
	})
	_expect_close(partial["nodes"]["assembler"]["production_scale"], 0.5, "partial ingredients diminish production")
	_expect_close(partial["edges"]["parts_out"]["used_upm"], 30.0, "partial ingredients produce scaled output")


func _test_storage_inventory_updates_over_time() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "storage", "kind": "storage", "inventory": {&"iron": 60.0}},
			{"id": "sink", "kind": "machine", "inputs": {&"iron": 120.0}}
		],
		"edges": [
			{"id": "out", "from": "storage", "to": "sink", "capacity_upm": 120.0}
		]
	}, 30.0)

	_expect_close(result["edges"]["out"]["used_upm"], 120.0, "storage can output from inventory")
	_expect_close(result["state"]["storage_inventory"]["storage"].get(&"iron", 0.0), 0.0, "storage inventory depletes over time")


func _test_loop_detection_warns_without_stopping() -> void:
	var sim := FlowSimulatorScript.new()
	var result := sim.simulate({
		"nodes": [
			{"id": "a", "kind": "junction"},
			{"id": "b", "kind": "junction"}
		],
		"edges": [
			{"id": "ab", "from": "a", "to": "b", "capacity_upm": 120.0},
			{"id": "ba", "from": "b", "to": "a", "capacity_upm": 120.0}
		]
	})

	_expect_true(not result["warnings"].is_empty(), "loop detection emits warning")
	_expect_equal(result["warnings"][0]["type"], FlowSimulatorScript.WARNING_LOOP_DETECTED, "loop warning type")


func _expect_close(actual: Variant, expected: float, label: String) -> void:
	if absf(float(actual) - expected) <= 0.01:
		return
	_failures += 1
	_record_failure("%s: expected %.3f, got %.3f" % [label, expected, float(actual)])


func _expect_true(value: bool, label: String) -> void:
	if value:
		return
	_failures += 1
	_record_failure("%s: expected true" % label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	_record_failure("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _record_failure(message: String) -> void:
	_failure_messages.append(message)
	push_error(message)


func _write_result_file() -> void:
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write FlowSimulator test result to %s" % RESULT_PATH)
		return

	if _failures > 0:
		file.store_line("FlowSimulator smoke tests failed: %d failure(s)." % _failures)
		for message in _failure_messages:
			file.store_line("- %s" % message)
	else:
		file.store_line("FlowSimulator smoke tests passed.")
