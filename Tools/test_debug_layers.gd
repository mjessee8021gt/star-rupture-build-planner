extends SceneTree

# Headless smoke tests for the Visual Debug Layers derivation engine
# (Scripts/debug_layer_model.gd). The model is pure — it turns a flow graph plus a
# PathingIntelligence assessment into "which buildings/rails/ports each layer marks" —
# so these tests feed plain data dictionaries and assert the classification, with no
# scene. Scene geometry (world rects, rail polylines) lives in main.gd and is covered
# by interactive QA.
#
# Result is written to Tools/debug_layer_test_result.txt (matches the blueprint/
# flow-sim/save-versioning runner convention) and mirrored to stdout/stderr.

const Model = preload("res://Scripts/debug_layer_model.gd")

var _failures: Array[String] = []
var _checks := 0

const EXPECTED_CHECKS := 27


func _initialize() -> void:
	_test_health_state()
	_test_waste_sources()
	_test_orphans()
	_test_normalize()
	_test_port_leaf()
	_finish()


# --- health_state ------------------------------------------------------------

func _test_health_state() -> void:
	# No input requirements -> nothing to assess.
	_eq(Model.health_state({"requirements": []}), "", "no requirements -> empty")
	_eq(Model.health_state({}), "", "missing requirements key -> empty")

	# Requires inputs but nothing wired to any input port.
	_eq(Model.health_state({
		"requirements": [{"resource": "iron"}],
		"port_summaries": {},
	}), Model.HEALTH_DISCONNECTED, "requirements + no ports -> disconnected")

	# A required input is missing from every connected rail.
	_eq(Model.health_state({
		"requirements": [{"resource": "iron"}],
		"port_summaries": {"Input 1": {}},
		"missing_requirements": [{"resource": "iron"}],
	}), Model.HEALTH_MISSING, "missing requirement -> missing")

	# Present everywhere but under the demanded rate.
	_eq(Model.health_state({
		"requirements": [{"resource": "iron"}],
		"port_summaries": {"Input 1": {}},
		"missing_requirements": [],
		"has_under_supply": true,
	}), Model.HEALTH_UNDER, "under supply -> under")

	# Fully supplied.
	_eq(Model.health_state({
		"requirements": [{"resource": "iron"}],
		"port_summaries": {"Input 1": {}},
		"missing_requirements": [],
		"has_under_supply": false,
	}), Model.HEALTH_SUPPLIED, "supplied -> supplied")

	# Missing takes precedence over under-supply.
	_eq(Model.health_state({
		"requirements": [{"resource": "iron"}, {"resource": "copper"}],
		"port_summaries": {"Input 1": {}},
		"missing_requirements": [{"resource": "copper"}],
		"has_under_supply": true,
	}), Model.HEALTH_MISSING, "missing beats under")


# --- waste_sources -----------------------------------------------------------

func _test_waste_sources() -> void:
	var edge_supply := {
		"rail_1": {"from": "building_a", "to": "building_b", "unused_resources": ["scrap"]},
		"rail_2": {"from": "building_a", "to": "building_c", "unused_resources": []},
		"rail_3": {"from": "building_d", "to": "building_e", "unused_resources": ["gas", "oil"]},
	}
	var result := Model.waste_sources(edge_supply)
	var from_ids: Array = result.get("from_ids", [])
	var edge_ids: Array = result.get("edge_ids", [])

	_truth(edge_ids.has("rail_1"), "rail with unused resource is flagged")
	_truth(not edge_ids.has("rail_2"), "rail with no unused resource is skipped")
	_truth(edge_ids.has("rail_3"), "second wasteful rail is flagged")
	_truth(from_ids.has("building_a"), "waste producer is captured")
	_truth(from_ids.has("building_d"), "second waste producer is captured")
	_eq(from_ids.size(), 2, "producers are de-duplicated")


# --- orphans -----------------------------------------------------------------

func _test_orphans() -> void:
	var graph := {
		"nodes": [
			{"id": "building_a", "ports": {"input": [], "output": ["Output 1"], "universal": []}},
			{"id": "building_b", "ports": {"input": ["Input 1", "Input 2"], "output": [], "universal": []}},
			{"id": "building_c", "ports": {"input": ["Input 1"], "output": ["Output 1"], "universal": []}},
		],
		"edges": [
			# A/Output 1 -> B/Input 1 ; B/Input 2 and everything on C are unconnected.
			{"from": "building_a", "to": "building_b", "from_port": "Ports/Output 1", "to_port": "Ports/Input 1"},
		],
	}
	var result := Model.orphans(graph)
	var disconnected: Array = result.get("disconnected", [])
	var unconnected: Dictionary = result.get("unconnected_ports", {})

	_truth(disconnected.has("building_c"), "fully disconnected building detected")
	_truth(not disconnected.has("building_a"), "connected building not marked disconnected")
	_truth(not disconnected.has("building_b"), "connected building not marked disconnected")

	_truth(unconnected.has("building_b"), "partially connected building has free ports")
	var b_free: Array = unconnected.get("building_b", [])
	_truth(b_free.has("Input 2"), "unconnected port detected via leaf match")
	_truth(not b_free.has("Input 1"), "connected port excluded")
	# A's only port (Output 1) is used, so A should not appear in unconnected_ports.
	_truth(not unconnected.has("building_a"), "fully connected building has no free ports")


# --- normalize ---------------------------------------------------------------

func _test_normalize() -> void:
	var out := Model.normalize([10.0, 5.0, 0.0])
	_truth(is_equal_approx(float(out[0]), 1.0), "max normalizes to 1")
	_truth(is_equal_approx(float(out[1]), 0.5), "half normalizes to 0.5")
	_truth(is_equal_approx(float(out[2]), 0.0), "zero normalizes to 0")

	var zeros := Model.normalize([0.0, 0.0])
	_truth(is_equal_approx(float(zeros[0]), 0.0), "all-zero input stays zero (no divide by zero)")

	var neg := Model.normalize([-8.0, 4.0])
	_truth(is_equal_approx(float(neg[0]), 1.0), "magnitude uses absolute value")


# --- port_leaf ---------------------------------------------------------------

func _test_port_leaf() -> void:
	_eq(Model.port_leaf("Ports/Output 1"), "Output 1", "path leaf extracted")
	_eq(Model.port_leaf("Input 2"), "Input 2", "bare name preserved")


# --- harness -----------------------------------------------------------------

func _eq(actual, expected, label: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _truth(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: expected true" % label)


func _finish() -> void:
	var lines: Array[String] = []
	if _checks != EXPECTED_CHECKS:
		_failures.append("check count %d != expected %d (update EXPECTED_CHECKS if intended)" % [_checks, EXPECTED_CHECKS])

	if _failures.is_empty():
		lines.append("Debug layer tests passed (%d checks)." % _checks)
	else:
		lines.append("Debug layer tests FAILED (%d checks, %d failures):" % [_checks, _failures.size()])
		for failure in _failures:
			lines.append("  - " + failure)

	var text := "\n".join(lines)
	var file := FileAccess.open("res://Tools/debug_layer_test_result.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	print(text)
	if not _failures.is_empty():
		printerr(text)
	quit(0 if _failures.is_empty() else 1)
