extends SceneTree

const FlowSimulatorScript := preload("res://Scripts/FlowSimulator.gd")
const PathingIntelligenceScript := preload("res://Scripts/PathingIntelligence.gd")
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
	_test_pathing_bus_assigns_multiple_requirements_to_one_port()
	_test_pathing_reports_missing_requirements_and_extra_resources()
	_test_pathing_tracks_multi_origin_provenance()
	_test_pathing_flags_under_supplied_requirement()
	_test_pathing_marks_matched_supply_as_sufficient()
	_test_pathing_input_chip_index_naming()
	_test_pathing_delivered_rate_reveals_bus_contention()
	_test_pathing_missing_input_does_not_blame_supplied_input()
	_test_pathing_missing_supply_suggests_nearest_producer()
	_test_pathing_missing_supply_prefers_unconnected_rail()
	_test_pathing_missing_supply_falls_back_to_catalog()
	_test_pathing_confidence_wording_distinguishes_measured_from_estimated()
	_test_pathing_flags_dead_end_rail()
	_test_pathing_storage_is_not_a_dead_end()
	_test_pathing_flags_unconsumed_resource_on_shared_rail()


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


func _test_pathing_bus_assigns_multiple_requirements_to_one_port() -> void:
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "iron", "kind": "source", "label": "Iron Mine", "outputs": {&"iron": 60.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0}]},
			{"id": "copper", "kind": "source", "label": "Copper Mine", "outputs": {&"copper": 30.0}, "output_products": [{"resource": &"copper", "display_name": "Copper Ore", "qty": 30.0}]},
			{"id": "bus", "kind": "support", "label": "Main Bus"},
			{"id": "assembler", "kind": "machine", "label": "Assembler", "inputs": {&"iron": 60.0, &"copper": 30.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0, "index": 0},
				{"resource": &"copper", "display_name": "Copper Ore", "qty": 30.0, "index": 1},
			]},
		],
		"edges": [
			{"id": "iron_to_bus", "from": "iron", "to": "bus", "to_port": "Ports/Input 1"},
			{"id": "copper_to_bus", "from": "copper", "to": "bus", "to_port": "Ports/Input 2"},
			{"id": "bus_to_assembler", "from": "bus", "to": "assembler", "to_port": "Ports/Input 2"},
		]
	})

	var assembler: Dictionary = assessment["building_assessments"]["assembler"]
	_expect_equal(assembler["missing_requirements"].size(), 0, "bus rail satisfies all requirements")
	_expect_true(bool(assembler["has_shared_rail"]), "bus rail marks building as shared rail")
	for requirement in assembler["requirements"]:
		_expect_equal(requirement["state"], PathingIntelligenceScript.REQUIREMENT_SUPPLIED, "bus requirement supplied")
		_expect_equal(requirement["port"], "Ports/Input 2", "bus requirement assigned to connected input port")


func _test_pathing_reports_missing_requirements_and_extra_resources() -> void:
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "carbon", "kind": "source", "label": "Carbon Store", "outputs": {&"carbon": 40.0}, "output_products": [{"resource": &"carbon", "display_name": "Carbon", "qty": 40.0}]},
			{"id": "assembler", "kind": "machine", "label": "Assembler", "inputs": {&"iron": 60.0, &"copper": 30.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0, "index": 0},
				{"resource": &"copper", "display_name": "Copper Ore", "qty": 30.0, "index": 1},
			]},
		],
		"edges": [
			{"id": "carbon_to_assembler", "from": "carbon", "to": "assembler", "to_port": "Ports/Input 1"},
		]
	})

	var assembler: Dictionary = assessment["building_assessments"]["assembler"]
	_expect_equal(assembler["missing_requirements"].size(), 2, "missing requirements are reported")
	var port_summary: Dictionary = assembler["port_summaries"]["Ports/Input 1"]
	_expect_true((port_summary["extra_resources"] as Array).has(&"carbon"), "extra resources are available but unused")


func _test_pathing_tracks_multi_origin_provenance() -> void:
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "iron_a", "kind": "source", "label": "Iron Mine A", "outputs": {&"iron": 60.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0}]},
			{"id": "iron_b", "kind": "source", "label": "Iron Mine B", "outputs": {&"iron": 60.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0}]},
			{"id": "bus", "kind": "support", "label": "Iron Bus"},
			{"id": "smelter", "kind": "machine", "label": "Smelter", "inputs": {&"iron": 120.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 120.0, "index": 0},
			]},
		],
		"edges": [
			{"id": "a_to_bus", "from": "iron_a", "to": "bus", "to_port": "Ports/Input 1"},
			{"id": "b_to_bus", "from": "iron_b", "to": "bus", "to_port": "Ports/Input 2"},
			{"id": "bus_to_smelter", "from": "bus", "to": "smelter", "to_port": "Ports/Input 1"},
		]
	})

	var supply: Dictionary = assessment["edge_supply"]["bus_to_smelter"]
	var iron_fact: Dictionary = supply["resource_facts"][&"iron"]
	_expect_equal((iron_fact["origins"] as Array).size(), 2, "provenance preserves both upstream origins")
	_expect_close(iron_fact["rate"], 120.0, "provenance combines origin rates")


func _test_pathing_flags_under_supplied_requirement() -> void:
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "iron", "kind": "source", "label": "Iron Mine", "outputs": {&"iron": 60.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0}]},
			{"id": "smelter", "kind": "machine", "label": "Smelter", "inputs": {&"iron": 120.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 2.0, "index": 0},
			]},
		],
		"edges": [
			{"id": "iron_to_smelter", "from": "iron", "to": "smelter", "to_port": "Ports/Input 1"},
		]
	})

	var smelter: Dictionary = assessment["building_assessments"]["smelter"]
	_expect_true(bool(smelter["has_under_supply"]), "under-supplied building is flagged")
	var requirement: Dictionary = smelter["requirements"][0]
	_expect_equal(requirement["state"], PathingIntelligenceScript.REQUIREMENT_SUPPLIED, "under-supplied requirement is still present")
	_expect_equal(requirement["sufficiency"], PathingIntelligenceScript.SUFFICIENCY_UNDER, "supply below demand marks under_supplied")
	_expect_close(requirement["supply_rate"], 60.0, "under-supplied requirement records upstream supply rate")
	_expect_close(requirement["demand_rate"], 120.0, "under-supplied requirement records demand rate")


func _test_pathing_marks_matched_supply_as_sufficient() -> void:
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "iron", "kind": "source", "label": "Iron Mine", "outputs": {&"iron": 120.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 120.0}]},
			{"id": "smelter", "kind": "machine", "label": "Smelter", "inputs": {&"iron": 120.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 2.0, "index": 0},
			]},
		],
		"edges": [
			{"id": "iron_to_smelter", "from": "iron", "to": "smelter", "to_port": "Ports/Input 1"},
		]
	})

	var smelter: Dictionary = assessment["building_assessments"]["smelter"]
	_expect_true(not bool(smelter["has_under_supply"]), "matched supply is not flagged as under-supply")
	var requirement: Dictionary = smelter["requirements"][0]
	_expect_equal(requirement["sufficiency"], PathingIntelligenceScript.SUFFICIENCY_SUFFICIENT, "supply meeting demand marks sufficient")


func _test_pathing_input_chip_index_naming() -> void:
	# Indexed chips (Fabricator-style) parse their digit.
	_expect_equal(PathingIntelligenceScript._input_chip_index("Input1Box"), 1, "Input1Box maps to index 1")
	_expect_equal(PathingIntelligenceScript._input_chip_index("Input2Box"), 2, "Input2Box maps to index 2")
	# Bare single-input chip (Smelter-style) has no digit and must still be recognized.
	_expect_equal(PathingIntelligenceScript._input_chip_index("InputBox"), 1, "bare InputBox maps to index 1")
	# Non-input ColorRects must not be treated as chips.
	_expect_equal(PathingIntelligenceScript._input_chip_index("outputBox"), -1, "outputBox is not an input chip")
	_expect_equal(PathingIntelligenceScript._input_chip_index("InputPanel"), -1, "non-box input node is not a chip")


func _test_pathing_delivered_rate_reveals_bus_contention() -> void:
	# One 120 upm iron source feeds a bus shared by two smelters that each want 120.
	var graph := {
		"nodes": [
			{"id": "iron", "kind": "source", "label": "Iron Mine", "outputs": {&"iron": 120.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 120.0}]},
			{"id": "bus", "kind": "support", "label": "Iron Bus"},
			{"id": "smelter_a", "kind": "machine", "label": "Smelter A", "inputs": {&"iron": 120.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 2.0, "index": 0},
			]},
			{"id": "smelter_b", "kind": "machine", "label": "Smelter B", "inputs": {&"iron": 120.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 2.0, "index": 0},
			]},
		],
		"edges": [
			{"id": "iron_to_bus", "from": "iron", "to": "bus", "to_port": "Ports/Input 1", "capacity_upm": 480.0},
			{"id": "bus_to_a", "from": "bus", "to": "smelter_a", "to_port": "Ports/Input 1", "capacity_upm": 480.0},
			{"id": "bus_to_b", "from": "bus", "to": "smelter_b", "to_port": "Ports/Input 1", "capacity_upm": 480.0},
		]
	}

	# Estimated mode (no simulation) sees the full upstream 120 and misses the contention.
	var estimated := PathingIntelligenceScript.analyze_graph(graph)
	_expect_equal(estimated["building_assessments"]["smelter_a"]["requirements"][0]["sufficiency"], PathingIntelligenceScript.SUFFICIENCY_SUFFICIENT, "estimated mode does not see bus contention")

	# Delivered mode splits the shared 120 across two consumers, exposing the shortfall.
	var sim := FlowSimulatorScript.new()
	var simulation := sim.simulate(graph)
	var delivered := PathingIntelligenceScript.analyze_graph(graph, simulation)
	var smelter_a: Dictionary = delivered["building_assessments"]["smelter_a"]
	var requirement: Dictionary = smelter_a["requirements"][0]
	_expect_equal(requirement["supply_basis"], PathingIntelligenceScript.SUPPLY_BASIS_DELIVERED, "delivered basis is used when a simulation is present")
	_expect_equal(requirement["sufficiency"], PathingIntelligenceScript.SUFFICIENCY_UNDER, "delivered rate reveals bus contention shortfall")
	_expect_close(requirement["supply_rate"], 60.0, "delivered rate splits shared supply across consumers")
	_expect_true(bool(smelter_a["has_under_supply"]), "contended building is flagged as under-supplied")


func _test_pathing_missing_input_does_not_blame_supplied_input() -> void:
	# Iron is plentiful but copper is unconnected, so the machine idles and delivers no iron.
	var graph := {
		"nodes": [
			{"id": "iron", "kind": "source", "label": "Iron Mine", "outputs": {&"iron": 240.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 240.0}]},
			{"id": "assembler", "kind": "machine", "label": "Assembler", "inputs": {&"iron": 120.0, &"copper": 120.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 2.0, "index": 0},
				{"resource": &"copper", "display_name": "Copper Ore", "qty": 2.0, "index": 1},
			]},
		],
		"edges": [
			{"id": "iron_to_assembler", "from": "iron", "to": "assembler", "to_port": "Ports/Input 1", "capacity_upm": 480.0},
		]
	}

	var sim := FlowSimulatorScript.new()
	var simulation := sim.simulate(graph)
	var assessment := PathingIntelligenceScript.analyze_graph(graph, simulation)
	var assembler: Dictionary = assessment["building_assessments"]["assembler"]
	_expect_equal(assembler["missing_requirements"].size(), 1, "copper is reported missing")
	for requirement_variant in assembler["requirements"]:
		var requirement: Dictionary = requirement_variant
		if String(requirement["resource"]) == "iron":
			_expect_equal(requirement["supply_basis"], PathingIntelligenceScript.SUPPLY_BASIS_ESTIMATED, "supplied input falls back to estimated when a sibling input is missing")
			_expect_equal(requirement["sufficiency"], PathingIntelligenceScript.SUFFICIENCY_SUFFICIENT, "plentiful iron stays sufficient despite the idle machine")
	_expect_true(not bool(assembler["has_under_supply"]), "idle machine with a missing input is not mislabeled as under-supplied")


func _test_pathing_missing_supply_suggests_nearest_producer() -> void:
	# Copper exists in the plan (two mines, unrailed) but is not connected to the assembler.
	var graph := {
		"nodes": [
			{"id": "copper_near", "kind": "source", "label": "Copper Mine A", "position": [100.0, 0.0], "outputs": {&"copper": 60.0}, "output_products": [{"resource": &"copper", "display_name": "Copper Ore", "qty": 60.0}]},
			{"id": "copper_far", "kind": "source", "label": "Copper Mine B", "position": [900.0, 0.0], "outputs": {&"copper": 60.0}, "output_products": [{"resource": &"copper", "display_name": "Copper Ore", "qty": 60.0}]},
			{"id": "assembler", "kind": "machine", "label": "Assembler", "position": [0.0, 0.0], "inputs": {&"copper": 60.0}, "input_requirements": [
				{"resource": &"copper", "display_name": "Copper Ore", "qty": 1.0, "index": 0},
			]},
		],
		"edges": []
	}

	var assessment := PathingIntelligenceScript.analyze_graph(graph)
	var requirement: Dictionary = assessment["building_assessments"]["assembler"]["requirements"][0]
	_expect_equal(requirement["state"], PathingIntelligenceScript.REQUIREMENT_MISSING, "copper is missing")
	var suggestion: Dictionary = requirement["suggestion"]
	_expect_equal(suggestion["tier"], "producer", "unrailed copper suggests the producing building")
	_expect_equal(suggestion["target_node_id"], "copper_near", "suggestion picks the nearest copper producer")


func _test_pathing_missing_supply_prefers_unconnected_rail() -> void:
	# Copper is already on a rail feeding another machine, but not connected to the assembler.
	var graph := {
		"nodes": [
			{"id": "copper", "kind": "source", "label": "Copper Mine", "position": [200.0, 0.0], "outputs": {&"copper": 120.0}, "output_products": [{"resource": &"copper", "display_name": "Copper Ore", "qty": 120.0}]},
			{"id": "other", "kind": "machine", "label": "Other", "position": [300.0, 0.0], "inputs": {&"copper": 60.0}, "input_requirements": [{"resource": &"copper", "display_name": "Copper Ore", "qty": 1.0, "index": 0}]},
			{"id": "assembler", "kind": "machine", "label": "Assembler", "position": [0.0, 0.0], "inputs": {&"copper": 60.0}, "input_requirements": [{"resource": &"copper", "display_name": "Copper Ore", "qty": 1.0, "index": 0}]},
		],
		"edges": [
			{"id": "copper_to_other", "from": "copper", "to": "other", "to_port": "Ports/Input 1", "capacity_upm": 480.0},
		]
	}

	var assessment := PathingIntelligenceScript.analyze_graph(graph)
	var suggestion: Dictionary = assessment["building_assessments"]["assembler"]["requirements"][0]["suggestion"]
	_expect_equal(suggestion["tier"], "rail", "prefers tapping an existing unconnected rail over a raw producer")


func _test_pathing_missing_supply_falls_back_to_catalog() -> void:
	# Nothing in the plan produces the resource, so the catalog hint names the building type.
	var graph := {
		"nodes": [
			{"id": "assembler", "kind": "machine", "label": "Assembler", "position": [0.0, 0.0], "inputs": {&"exotic": 60.0}, "input_requirements": [
				{"resource": &"exotic", "display_name": "Exotic Matter", "qty": 1.0, "index": 0},
			]},
		],
		"edges": []
	}

	var catalog := func(resource): return "Fabricator" if String(resource) == "exotic" else ""
	var assessment := PathingIntelligenceScript.analyze_graph(graph, {}, {"catalog_lookup": catalog})
	var suggestion: Dictionary = assessment["building_assessments"]["assembler"]["requirements"][0]["suggestion"]
	_expect_equal(suggestion["tier"], "none", "no source in the plan yields the catalog tier")
	_expect_true(String(suggestion["text"]).contains("Fabricator"), "catalog hint names the producing building")


func _test_pathing_confidence_wording_distinguishes_measured_from_estimated() -> void:
	var base_requirement := {
		"resource": &"iron",
		"display_name": "Iron Ore",
		"state": PathingIntelligenceScript.REQUIREMENT_SUPPLIED,
		"port": "Ports/Input 1",
		"demand_rate": 120.0,
		"supply_rate": 120.0,
		"sufficiency": PathingIntelligenceScript.SUFFICIENCY_SUFFICIENT,
	}

	var delivered_requirement := base_requirement.duplicate(true)
	delivered_requirement["supply_basis"] = PathingIntelligenceScript.SUPPLY_BASIS_DELIVERED
	var delivered_tip := PathingIntelligenceScript._build_requirement_tooltip(delivered_requirement, {})
	_expect_true(delivered_tip.contains("Delivered:"), "measured supply reads as delivered")
	_expect_true(not delivered_tip.contains("not measured"), "measured supply carries no estimate caveat")

	var estimated_requirement := base_requirement.duplicate(true)
	estimated_requirement["supply_basis"] = PathingIntelligenceScript.SUPPLY_BASIS_ESTIMATED
	var estimated_tip := PathingIntelligenceScript._build_requirement_tooltip(estimated_requirement, {})
	_expect_true(estimated_tip.contains("Estimated supply:"), "inferred supply is labeled as an estimate")
	_expect_true(estimated_tip.contains("not measured"), "inferred supply carries the confidence caveat")


func _test_pathing_flags_dead_end_rail() -> void:
	# Iron flows onto a rail that terminates at a junction with nothing beyond it.
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "iron", "kind": "source", "label": "Iron Mine", "outputs": {&"iron": 60.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0}]},
			{"id": "junction", "kind": "junction", "label": "Junction"},
		],
		"edges": [
			{"id": "iron_to_junction", "from": "iron", "to": "junction", "to_port": "Ports/Input 1"},
		]
	})

	var rail: Dictionary = assessment["edge_supply"]["iron_to_junction"]
	_expect_true(bool(rail["is_dead_end"]), "a rail with no downstream consumer is a dead-end")
	_expect_true((rail["unused_resources"] as Array).has(&"iron"), "the dead-end resource is reported")


func _test_pathing_storage_is_not_a_dead_end() -> void:
	# A rail feeding storage always has a valid destination (stockpiling).
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "iron", "kind": "source", "label": "Iron Mine", "outputs": {&"iron": 60.0}, "output_products": [{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0}]},
			{"id": "store", "kind": "storage", "label": "Storage"},
		],
		"edges": [
			{"id": "iron_to_store", "from": "iron", "to": "store", "to_port": "Ports/Input 1"},
		]
	})

	var rail: Dictionary = assessment["edge_supply"]["iron_to_store"]
	_expect_true(not bool(rail["is_dead_end"]), "a rail into storage is not a dead-end")
	_expect_equal((rail["unused_resources"] as Array).size(), 0, "storage absorbs all delivered resources")


func _test_pathing_flags_unconsumed_resource_on_shared_rail() -> void:
	# A bus carries iron + copper into a machine that only consumes iron.
	var assessment := PathingIntelligenceScript.analyze_graph({
		"nodes": [
			{"id": "mixed", "kind": "source", "label": "Mixed Source", "outputs": {&"iron": 60.0, &"copper": 60.0}, "output_products": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 60.0},
				{"resource": &"copper", "display_name": "Copper Ore", "qty": 60.0},
			]},
			{"id": "smelter", "kind": "machine", "label": "Smelter", "inputs": {&"iron": 60.0}, "input_requirements": [
				{"resource": &"iron", "display_name": "Iron Ore", "qty": 1.0, "index": 0},
			]},
		],
		"edges": [
			{"id": "mixed_to_smelter", "from": "mixed", "to": "smelter", "to_port": "Ports/Input 1"},
		]
	})

	var rail: Dictionary = assessment["edge_supply"]["mixed_to_smelter"]
	_expect_true(not bool(rail["is_dead_end"]), "a rail with a consumed resource is not a full dead-end")
	_expect_true((rail["unused_resources"] as Array).has(&"copper"), "copper has no downstream consumer")
	_expect_true(not (rail["unused_resources"] as Array).has(&"iron"), "iron is consumed by the smelter")


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
