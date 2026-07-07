extends SceneTree

# Headless smoke tests for the Building Alignment Tools layout engine
# (BuildManager.align_selected_buildings and its target math).
#
# The layout math is deterministic and grid-native, so these tests build a
# BuildManager with mock building nodes at known grid cells, run each command
# family, and assert the resulting top-left cells. They also cover reference
# modes, odd/even footprints, strict-vs-best-effort placement, and the
# port-alignment grid invariant (buildings never leave the grid).
#
# Result is written to Tools/alignment_test_result.txt (matches the flow-sim
# runner convention) and mirrored to stdout/stderr.

const TILE := 64.0

var _failures: Array[String] = []
var _building_script: GDScript = null


func _initialize() -> void:
	_building_script = GDScript.new()
	_building_script.source_code = "extends Node2D\nvar anchor := Vector2i.ZERO\nvar footprint := Vector2i.ONE\nvar rotatedTick := 0\n"
	_building_script.reload()

	_run_edge_alignment_tests()
	_run_center_alignment_tests()
	_run_reference_mode_tests()
	_run_distribution_tests()
	_run_pack_tests()
	_run_arrange_tests()
	_run_strict_vs_best_effort_tests()
	_run_port_alignment_test()
	_run_shift_selection_test()
	_run_panel_ui_test()

	_finish()


# --- Harness -----------------------------------------------------------------

func _make_manager() -> Node2D:
	# BuildManager resolves $"../TileMapLayer" via @onready, so give it a real
	# sibling to avoid a get_node error, then null the ref so all coordinate
	# math uses the pure grid fallback (tile_size stays 64).
	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)

	var tml := TileMapLayer.new()
	tml.name = "TileMapLayer"
	world.add_child(tml)

	var bm_script: GDScript = load("res://Scripts/buildManager.gd")
	var bm: Node2D = bm_script.new()
	bm.name = "BuildManager"
	world.add_child(bm)
	bm.tile_map_layer = null
	return bm


func _make_building(bm: Node2D, footprint: Vector2i, top_left: Vector2i) -> Node2D:
	var b: Node2D = _building_script.new()
	b.footprint = footprint
	b.anchor = Vector2i(int(floor(footprint.x / 2.0)), int(floor(footprint.y / 2.0)))
	bm.add_child(b)
	_place(bm, b, top_left)
	return b


func _place(bm: Node2D, b: Node2D, top_left: Vector2i) -> void:
	b.global_position = bm.cell_to_world(top_left) + Vector2(b.footprint) * (TILE * 0.5)


func _top_left(bm: Node2D, b: Node2D) -> Vector2i:
	return bm._anchor_cell_from_building_position(b, b.global_position) - Vector2i(b.anchor)


func _select(bm: Node2D, buildings: Array) -> void:
	var typed: Array[Node2D] = []
	for b in buildings:
		typed.append(b)
	bm.selected_buildings = typed


func _register_occupied(bm: Node2D, b: Node2D, top_left: Vector2i) -> void:
	var cells: Array = bm.get_building_cells(b, top_left + Vector2i(b.anchor))
	bm.occupy_cells(cells, b)


# --- Tests -------------------------------------------------------------------

func _run_edge_alignment_tests() -> void:
	# Three 2x2 buildings, spaced apart on both axes so aligning them to a
	# shared edge never makes their footprints legitimately overlap.
	var start := [Vector2i(0, 0), Vector2i(5, 3), Vector2i(10, 6)]
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(2, 2), start[0])
	var b := _make_building(bm, Vector2i(2, 2), start[1])
	var c := _make_building(bm, Vector2i(2, 2), start[2])
	_select(bm, [a, b, c])

	bm.align_selected_buildings("align_left")
	_expect_cell("align_left A", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("align_left B", _top_left(bm, b), Vector2i(0, 3))
	_expect_cell("align_left C", _top_left(bm, c), Vector2i(0, 6))

	_reset(bm, [a, b, c], start)
	bm.align_selected_buildings("align_right")
	_expect_cell("align_right A", _top_left(bm, a), Vector2i(10, 0))
	_expect_cell("align_right B", _top_left(bm, b), Vector2i(10, 3))
	_expect_cell("align_right C", _top_left(bm, c), Vector2i(10, 6))

	_reset(bm, [a, b, c], start)
	bm.align_selected_buildings("align_top")
	_expect_cell("align_top A", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("align_top B", _top_left(bm, b), Vector2i(5, 0))
	_expect_cell("align_top C", _top_left(bm, c), Vector2i(10, 0))

	_reset(bm, [a, b, c], start)
	bm.align_selected_buildings("align_bottom")
	_expect_cell("align_bottom A", _top_left(bm, a), Vector2i(0, 6))
	_expect_cell("align_bottom B", _top_left(bm, b), Vector2i(5, 6))
	_expect_cell("align_bottom C", _top_left(bm, c), Vector2i(10, 6))

	_free(bm)


func _run_center_alignment_tests() -> void:
	# Even/even center: three 2x2, centers land cleanly.
	var start := [Vector2i(0, 0), Vector2i(5, 3), Vector2i(10, 6)]
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(2, 2), start[0])
	var b := _make_building(bm, Vector2i(2, 2), start[1])
	var c := _make_building(bm, Vector2i(2, 2), start[2])
	_select(bm, [a, b, c])

	bm.align_selected_buildings("align_hcenter")
	_expect_cell("align_hcenter A", _top_left(bm, a), Vector2i(5, 0))
	_expect_cell("align_hcenter B", _top_left(bm, b), Vector2i(5, 3))
	_expect_cell("align_hcenter C", _top_left(bm, c), Vector2i(5, 6))

	_reset(bm, [a, b, c], start)
	bm.align_selected_buildings("align_vcenter")
	_expect_cell("align_vcenter A", _top_left(bm, a), Vector2i(0, 3))
	_expect_cell("align_vcenter B", _top_left(bm, b), Vector2i(5, 3))
	_expect_cell("align_vcenter C", _top_left(bm, c), Vector2i(10, 3))
	_free(bm)

	# Odd/even center: a 3x1 and a 1x1 should end perfectly co-centered.
	var bm2 := _make_manager()
	var wide := _make_building(bm2, Vector2i(3, 1), Vector2i(0, 0))
	var small := _make_building(bm2, Vector2i(1, 1), Vector2i(10, 5))
	_select(bm2, [wide, small])
	bm2.align_selected_buildings("align_hcenter")
	_expect_cell("odd/even hcenter wide", _top_left(bm2, wide), Vector2i(4, 0))
	_expect_cell("odd/even hcenter small", _top_left(bm2, small), Vector2i(5, 5))
	_free(bm2)


func _run_reference_mode_tests() -> void:
	var start := [Vector2i(0, 0), Vector2i(5, 3), Vector2i(10, 6)]
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(2, 2), start[0])
	var b := _make_building(bm, Vector2i(2, 2), start[1])
	var c := _make_building(bm, Vector2i(2, 2), start[2])
	_select(bm, [a, b, c])

	# reference = last -> align to C's left edge (x=10).
	bm.align_selected_buildings("align_left", {"reference_mode": "last"})
	_expect_cell("ref=last A", _top_left(bm, a), Vector2i(10, 0))
	_expect_cell("ref=last C", _top_left(bm, c), Vector2i(10, 6))

	# reference = anchor (B) -> align to B's left edge (x=5).
	_reset(bm, [a, b, c], start)
	bm.set_alignment_anchor(b)
	bm.align_selected_buildings("align_left", {"reference_mode": "anchor"})
	_expect_cell("ref=anchor A", _top_left(bm, a), Vector2i(5, 0))
	_expect_cell("ref=anchor B", _top_left(bm, b), Vector2i(5, 3))
	_expect_cell("ref=anchor C", _top_left(bm, c), Vector2i(5, 6))
	_free(bm)


func _run_distribution_tests() -> void:
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(2, 2), Vector2i(0, 0))
	var b := _make_building(bm, Vector2i(2, 2), Vector2i(3, 0))
	var c := _make_building(bm, Vector2i(2, 2), Vector2i(12, 0))
	_select(bm, [a, b, c])

	# gap metric: even empty space between footprints; middle lands at x=6.
	bm.align_selected_buildings("distribute_horizontal", {"metric": "gap"})
	_expect_cell("distribute gap A", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("distribute gap B", _top_left(bm, b), Vector2i(6, 0))
	_expect_cell("distribute gap C", _top_left(bm, c), Vector2i(12, 0))

	# centers metric: equal center spacing; middle center at x=7 -> top-left 6.
	_reset(bm, [a, b, c], [Vector2i(0, 0), Vector2i(3, 0), Vector2i(12, 0)])
	bm.align_selected_buildings("distribute_horizontal", {"metric": "center"})
	_expect_cell("distribute centers B", _top_left(bm, b), Vector2i(6, 0))
	_free(bm)

	# fixed spacing: keep the first fixed, respace the rest to exactly `gap`
	# tiles between facing surfaces (2x2 footprints, gap=2 -> stride 4).
	var bm2 := _make_manager()
	var a2 := _make_building(bm2, Vector2i(2, 2), Vector2i(0, 0))
	var b2 := _make_building(bm2, Vector2i(2, 2), Vector2i(5, 0))
	var c2 := _make_building(bm2, Vector2i(2, 2), Vector2i(12, 0))
	_select(bm2, [a2, b2, c2])
	bm2.align_selected_buildings("distribute_horizontal", {"metric": "fixed_gap", "gap": 2})
	_expect_cell("distribute fixed_gap A", _top_left(bm2, a2), Vector2i(0, 0))
	_expect_cell("distribute fixed_gap B", _top_left(bm2, b2), Vector2i(4, 0))
	_expect_cell("distribute fixed_gap C", _top_left(bm2, c2), Vector2i(8, 0))
	_free(bm2)


func _run_pack_tests() -> void:
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(2, 2), Vector2i(0, 0))
	var b := _make_building(bm, Vector2i(2, 2), Vector2i(5, 1))
	var c := _make_building(bm, Vector2i(2, 2), Vector2i(10, 2))
	_select(bm, [a, b, c])

	bm.align_selected_buildings("pack_horizontal", {"gap": 0})
	_expect_cell("pack gap0 A", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("pack gap0 B", _top_left(bm, b), Vector2i(2, 1))
	_expect_cell("pack gap0 C", _top_left(bm, c), Vector2i(4, 2))

	_reset(bm, [a, b, c], [Vector2i(0, 0), Vector2i(5, 1), Vector2i(10, 2)])
	bm.align_selected_buildings("pack_horizontal", {"gap": 1})
	_expect_cell("pack gap1 A", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("pack gap1 B", _top_left(bm, b), Vector2i(3, 1))
	_expect_cell("pack gap1 C", _top_left(bm, c), Vector2i(6, 2))
	_free(bm)


func _run_arrange_tests() -> void:
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(2, 2), Vector2i(0, 0))
	var b := _make_building(bm, Vector2i(2, 2), Vector2i(5, 1))
	var c := _make_building(bm, Vector2i(2, 2), Vector2i(10, 2))
	_select(bm, [a, b, c])

	bm.align_selected_buildings("arrange_row", {"gap": 0})
	_expect_cell("arrange_row A", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("arrange_row B", _top_left(bm, b), Vector2i(2, 0))
	_expect_cell("arrange_row C", _top_left(bm, c), Vector2i(4, 0))

	_reset(bm, [a, b, c], [Vector2i(0, 0), Vector2i(5, 1), Vector2i(10, 2)])
	bm.align_selected_buildings("arrange_column", {"gap": 0})
	_expect_cell("arrange_column A", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("arrange_column B", _top_left(bm, b), Vector2i(0, 2))
	_expect_cell("arrange_column C", _top_left(bm, c), Vector2i(0, 4))
	_free(bm)


func _run_strict_vs_best_effort_tests() -> void:
	# pack_vertical of A(0,0) + B(0,5) targets A->(0,0), B->(0,1).
	# Obstacle occupies (0,1): strict blocks everything, best-effort skips B.
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(1, 1), Vector2i(0, 0))
	var b := _make_building(bm, Vector2i(1, 1), Vector2i(0, 5))
	var obstacle := _make_building(bm, Vector2i(1, 1), Vector2i(0, 1))
	_register_occupied(bm, a, Vector2i(0, 0))
	_register_occupied(bm, b, Vector2i(0, 5))
	_register_occupied(bm, obstacle, Vector2i(0, 1))
	_select(bm, [a, b])

	var strict_result: Dictionary = bm.align_selected_buildings("pack_vertical", {"gap": 0, "strict": true})
	_expect_bool("strict blocked ok=false", bool(strict_result.get("ok", true)), false)
	_expect_cell("strict A unchanged", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("strict B unchanged", _top_left(bm, b), Vector2i(0, 5))

	var best_result: Dictionary = bm.align_selected_buildings("pack_vertical", {"gap": 0, "strict": false})
	_expect_bool("best-effort ok=true", bool(best_result.get("ok", false)), true)
	_expect_num("best-effort skipped=1", float(best_result.get("skipped", -1)), 1.0, 0.01)
	_expect_cell("best-effort A moved", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("best-effort B skipped stays", _top_left(bm, b), Vector2i(0, 5))
	_free(bm)


func _run_port_alignment_test() -> void:
	# Two 1x1 buildings with identical fixed "input" ports. Aligning port X
	# must translate the whole building and keep its origin on the grid.
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(1, 1), Vector2i(0, 0))
	var b := _make_building(bm, Vector2i(1, 1), Vector2i(3, 4))
	_add_input_port(a)
	_add_input_port(b)
	_register_occupied(bm, a, Vector2i(0, 0))
	_register_occupied(bm, b, Vector2i(3, 4))
	_select(bm, [a, b])

	var result: Dictionary = bm.align_selected_buildings("port_align_x", {"port_role": "input"})
	_expect_bool("port_align_x ok=true", bool(result.get("ok", false)), true)
	_expect_cell("port_align_x A anchor unchanged", _top_left(bm, a), Vector2i(0, 0))
	_expect_cell("port_align_x B moved to A column", _top_left(bm, b), Vector2i(0, 4))
	# Grid invariant: B origin lands exactly on a cell (integral world / TILE).
	var origin := b.global_position - Vector2(b.footprint) * (TILE * 0.5)
	_expect_num("port_align_x B origin on grid x", origin.x - round(origin.x / TILE) * TILE, 0.0, 0.01)
	_expect_num("port_align_x B origin on grid y", origin.y - round(origin.y / TILE) * TILE, 0.0, 0.01)
	_free(bm)


func _run_shift_selection_test() -> void:
	# Shift-click additive/toggle selection helpers: adding builds up the
	# selection, toggling removes and restores the original tint, and the anchor
	# is kept valid (reassigned when removed, cleared below 2 selected).
	var bm := _make_manager()
	var a := _make_building(bm, Vector2i(1, 1), Vector2i(0, 0))
	var b := _make_building(bm, Vector2i(1, 1), Vector2i(2, 0))
	var c := _make_building(bm, Vector2i(1, 1), Vector2i(4, 0))
	var white := Color(1, 1, 1, 1)

	var initial: Array[Node2D] = [a]
	bm._add_buildings_to_selection(initial)
	bm._toggle_building_in_selection(b)
	bm._toggle_building_in_selection(c)
	_expect_num("shift add count=3", float(bm.get_selected_building_count()), 3.0, 0.01)
	_expect_bool("shift anchor set to first", bm.get_alignment_anchor() == a, true)

	bm._toggle_building_in_selection(b)
	_expect_num("shift toggle-off count=2", float(bm.get_selected_building_count()), 2.0, 0.01)
	_expect_bool("b removed", bm.selected_buildings.has(b), false)
	_expect_bool("b tint restored", b.modulate.is_equal_approx(white), true)
	_expect_bool("anchor unchanged (a)", bm.get_alignment_anchor() == a, true)

	bm._toggle_building_in_selection(a)
	_expect_num("toggle anchor off count=1", float(bm.get_selected_building_count()), 1.0, 0.01)
	_expect_bool("anchor cleared under 2", bm.get_alignment_anchor() == null, true)
	_expect_bool("a tint restored", a.modulate.is_equal_approx(white), true)
	_free(bm)


func _run_panel_ui_test() -> void:
	# Contextual panel: hidden below 2 selection, visible at 2+, and its quick
	# actions forward the chosen command + advanced options to the backend.
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar last_command := \"\"\nvar last_options := {}\nfunc align_selected_buildings(command, options):\n\tlast_command = command\n\tlast_options = options\n\treturn {\"ok\": true, \"message\": \"done\"}\n"
	stub_script.reload()
	var stub: Node = stub_script.new()
	root.add_child(stub)

	var panel_script: GDScript = load("res://Scripts/alignment_panel.gd")
	var panel: Control = panel_script.new()
	root.add_child(panel)
	panel.call("setup", stub)

	panel.call("on_selection_changed", 1, null)
	_expect_bool("panel hidden at 1 selection", panel.visible, false)
	panel.call("on_selection_changed", 3, null)
	_expect_bool("panel visible at 3 selection", panel.visible, true)

	# Set advanced options then fire a command; backend should receive them.
	panel._reference_option.selected = 2 # "last"
	panel._gap_spin.value = 2
	panel._strict_check.button_pressed = false
	panel._run("pack_horizontal")
	_expect_str("panel forwards command", stub.last_command, "pack_horizontal")
	_expect_str("panel forwards reference", String(stub.last_options.get("reference_mode", "")), "last")
	_expect_num("panel forwards gap", float(stub.last_options.get("gap", -1)), 2.0, 0.01)
	_expect_bool("panel forwards strict=false", bool(stub.last_options.get("strict", true)), false)

	# Distribute defaults to fixed spacing so it honors the shared Spacing field.
	panel._run("distribute_horizontal")
	_expect_str("panel forwards distribute", stub.last_command, "distribute_horizontal")
	_expect_str("panel default metric fixed_gap", String(stub.last_options.get("metric", "")), "fixed_gap")
	_expect_num("panel distribute uses spacing", float(stub.last_options.get("gap", -1)), 2.0, 0.01)

	panel.queue_free()
	stub.queue_free()


func _add_input_port(building: Node2D) -> void:
	var ports := Control.new()
	ports.name = "Ports"
	building.add_child(ports)
	var port := Button.new()
	port.name = "input"
	port.position = Vector2(10, 5)
	port.custom_minimum_size = Vector2(8, 8)
	port.size = Vector2(8, 8)
	ports.add_child(port)


# --- Assertions --------------------------------------------------------------

func _reset(bm: Node2D, buildings: Array, cells: Array) -> void:
	# A successful command records occupancy at the moved cells. The harness
	# teleports buildings back via global_position (something real gameplay never
	# does), so clear occupancy too or stale cells trigger false collisions.
	bm.occupied_cells.clear()
	for i in range(buildings.size()):
		_place(bm, buildings[i], cells[i])


func _free(bm: Node2D) -> void:
	var world := bm.get_parent()
	if world != null:
		world.queue_free()


func _expect_cell(label: String, got: Vector2i, want: Vector2i) -> void:
	if got != want:
		_fail("%s: got %s want %s" % [label, got, want])


func _expect_bool(label: String, got: bool, want: bool) -> void:
	if got != want:
		_fail("%s: got %s want %s" % [label, got, want])


func _expect_str(label: String, got: String, want: String) -> void:
	if got != want:
		_fail("%s: got '%s' want '%s'" % [label, got, want])


func _expect_num(label: String, got: float, want: float, tol := 1.0) -> void:
	if abs(got - want) > tol:
		_fail("%s: got %s want %s" % [label, got, want])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	var result_path := "res://Tools/alignment_test_result.txt"
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if _failures.is_empty():
		var msg := "Alignment layout engine smoke tests passed."
		print(msg)
		if file != null:
			file.store_string(msg + "\n")
			file.close()
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		if file != null:
			file.store_string("Alignment tests FAILED:\n" + "\n".join(_failures) + "\n")
			file.close()
		quit(1)
