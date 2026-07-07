extends SceneTree

# Headless regression tests for the rail-routing "no pass-through" guard
# (PathManager._route_enters_building_body). Vertical-normal compaction passes
# used to shortcut a rail straight through an endpoint building's body; the
# guard detects that so the router can fall back to the around-route.
#
# Result -> Tools/pathing_test_result.txt (matches the other runners).

const TILE := 64.0

var _failures: Array[String] = []
var _bm_stub: Node = null


func _initialize() -> void:
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar occupied_cells := {}\nvar tile_size := 64\nfunc world_to_cell(pos):\n\treturn Vector2i(int(floor(pos.x / tile_size)), int(floor(pos.y / tile_size)))\nfunc cell_to_world(cell):\n\treturn Vector2(cell) * float(tile_size)\n"
	stub_script.reload()
	_bm_stub = stub_script.new()
	root.add_child(_bm_stub)

	_run_bottom_port_tests()
	_run_top_port_tests()

	_finish()


func _make_pm() -> Node:
	var pm_script: GDScript = load("res://Scripts/path_manager.gd")
	var pm: Node = pm_script.new()
	pm._build_manager = _bm_stub
	return pm


func _register_footprint(building: Object, top_left: Vector2i, size: Vector2i) -> void:
	for y in range(size.y):
		for x in range(size.x):
			_bm_stub.occupied_cells[top_left + Vector2i(x, y)] = building


func _run_bottom_port_tests() -> void:
	# 3x3 footprint at cells (0,0)-(2,2); bottom input port (normal DOWN) sitting
	# inside the bottom row at ~(96, 175).
	var pm := _make_pm()
	var building := RefCounted.new()
	_register_footprint(building, Vector2i(0, 0), Vector2i(3, 3))
	var port := Vector2(96, 175)
	var bodies := [{"building": building, "port": port, "normal": Vector2(0, 1)}]

	# Straight drop from above the building down to the bottom port -> pass-through.
	var through: Array[Vector2] = [Vector2(96, -32), port]
	_expect_bool("bottom port: drop through body flagged", pm._route_enters_building_body(through, bodies), true)

	# Legitimate approach from below, stops at the port -> clean.
	var clean: Array[Vector2] = [Vector2(96, 320), port]
	_expect_bool("bottom port: approach from below clean", pm._route_enters_building_body(clean, bodies), false)

	# A rail routed entirely below/around the building -> clean.
	var around: Array[Vector2] = [Vector2(96, 320), Vector2(400, 320), Vector2(400, 175)]
	_expect_bool("bottom port: around route clean", pm._route_enters_building_body(around, bodies), false)

	_bm_stub.occupied_cells.clear()


func _run_top_port_tests() -> void:
	# Same footprint; top output port (normal UP) inside the top row at ~(96, 20).
	var pm := _make_pm()
	var building := RefCounted.new()
	_register_footprint(building, Vector2i(0, 0), Vector2i(3, 3))
	var port := Vector2(96, 20)
	var bodies := [{"building": building, "port": port, "normal": Vector2(0, -1)}]

	# Climb from below the building up through it to the top output -> pass-through.
	var through: Array[Vector2] = [Vector2(96, 320), port]
	_expect_bool("top port: climb through body flagged", pm._route_enters_building_body(through, bodies), true)

	# Departure straight up and away -> clean.
	var clean: Array[Vector2] = [port, Vector2(96, -128)]
	_expect_bool("top port: departure upward clean", pm._route_enters_building_body(clean, bodies), false)

	# Empty endpoint (preview to open space) is never a body crossing.
	var no_building := [{"building": null, "port": port, "normal": Vector2(0, -1)}]
	_expect_bool("null building never flagged", pm._route_enters_building_body(through, no_building), false)

	_bm_stub.occupied_cells.clear()


func _expect_bool(label: String, got: bool, want: bool) -> void:
	if got != want:
		_failures.append("%s: got %s want %s" % [label, got, want])


func _finish() -> void:
	var file := FileAccess.open("res://Tools/pathing_test_result.txt", FileAccess.WRITE)
	if _failures.is_empty():
		var msg := "Pathing guard smoke tests passed."
		print(msg)
		if file != null:
			file.store_string(msg + "\n")
			file.close()
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		if file != null:
			file.store_string("Pathing tests FAILED:\n" + "\n".join(_failures) + "\n")
			file.close()
		quit(1)
