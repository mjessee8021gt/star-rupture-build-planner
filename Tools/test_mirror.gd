extends SceneTree

# Headless smoke tests for the eyedropper group-mirror layout math
# (BuildManager._mirror_top_left_cells and BuildManager.mirror_group_layout).
#
# The reflection is deterministic, grid-native cell math, so these tests exercise
# the pure static helper directly with known cell rects, plus a small integration
# case that drives mirror_group_layout against mock ghost entries and asserts the
# recomputed per-building anchor offsets.
#
# Result is written to Tools/mirror_test_result.txt (matches the flow-sim/
# alignment runner convention) and mirrored to stdout/stderr.

const TILE := 64.0

var _failures: Array[String] = []
var _bm_script: GDScript = null
var _building_script: GDScript = null


func _initialize() -> void:
	_bm_script = load("res://Scripts/buildManager.gd")
	_building_script = GDScript.new()
	_building_script.source_code = "extends Node2D\nvar anchor := Vector2i.ZERO\nvar footprint := Vector2i.ONE\nvar rotatedTick := 0\n"
	_building_script.reload()

	_run_static_horizontal_tests()
	_run_static_vertical_tests()
	_run_static_sizing_tests()
	_run_static_single_and_empty_tests()
	_run_integration_tests()
	_run_rotation_parity_tests()

	_finish()


# --- Static reflection math --------------------------------------------------

func _rect(top_left: Vector2i, size: Vector2i) -> Dictionary:
	return {"top_left": top_left, "size": size}


func _mirror(rects: Array, axis: String) -> Array:
	return _bm_script.call("_mirror_top_left_cells", rects, axis)


func _run_static_horizontal_tests() -> void:
	# Three 1x1 buildings in a row: reflect columns about [0..3].
	var rects := [
		_rect(Vector2i(0, 0), Vector2i(1, 1)),
		_rect(Vector2i(1, 0), Vector2i(1, 1)),
		_rect(Vector2i(3, 0), Vector2i(1, 1)),
	]
	var out := _mirror(rects, "horizontal")
	_expect_cell("H row A", out[0], Vector2i(3, 0))
	_expect_cell("H row B", out[1], Vector2i(2, 0))
	_expect_cell("H row C", out[2], Vector2i(0, 0))


func _run_static_vertical_tests() -> void:
	# Same three buildings stacked: reflect rows about [0..3], columns untouched.
	var rects := [
		_rect(Vector2i(2, 0), Vector2i(1, 1)),
		_rect(Vector2i(2, 1), Vector2i(1, 1)),
		_rect(Vector2i(2, 3), Vector2i(1, 1)),
	]
	var out := _mirror(rects, "vertical")
	_expect_cell("V col A", out[0], Vector2i(2, 3))
	_expect_cell("V col B", out[1], Vector2i(2, 2))
	_expect_cell("V col C", out[2], Vector2i(2, 0))


func _run_static_sizing_tests() -> void:
	# Wide 2x1 on the left, 1x1 on the right. Horizontal mirror must reflect the
	# *span* of each building, not just its anchor, so the 2-wide block lands on
	# the right and the 1-wide lands on the left with no overlap.
	var rects := [
		_rect(Vector2i(0, 0), Vector2i(2, 1)),  # cols 0..1
		_rect(Vector2i(3, 0), Vector2i(1, 1)),  # col 3
	]
	var out := _mirror(rects, "horizontal")
	_expect_cell("H sized wide", out[0], Vector2i(2, 0))  # now cols 2..3
	_expect_cell("H sized narrow", out[1], Vector2i(0, 0))  # now col 0

	# A vertical mirror of the same layout leaves both untouched (single row).
	var out_v := _mirror(rects, "vertical")
	_expect_cell("V sized wide", out_v[0], Vector2i(0, 0))
	_expect_cell("V sized narrow", out_v[1], Vector2i(3, 0))

	# 2D block: horizontal mirror keeps y, reflects x about [0..3].
	var rects2d := [
		_rect(Vector2i(0, 5), Vector2i(2, 2)),  # cols 0..1
		_rect(Vector2i(2, 5), Vector2i(2, 2)),  # cols 2..3
	]
	var out2d := _mirror(rects2d, "horizontal")
	_expect_cell("H 2D left->right", out2d[0], Vector2i(2, 5))
	_expect_cell("H 2D right->left", out2d[1], Vector2i(0, 5))


func _run_static_single_and_empty_tests() -> void:
	# A single building mirrors in place (bounds equal its own span).
	var single := [_rect(Vector2i(4, 7), Vector2i(2, 3))]
	var out_h := _mirror(single, "horizontal")
	_expect_cell("single H no-op", out_h[0], Vector2i(4, 7))
	var out_v := _mirror(single, "vertical")
	_expect_cell("single V no-op", out_v[0], Vector2i(4, 7))

	# Empty input returns empty (no crash).
	var empty := _mirror([], "horizontal")
	if empty.size() != 0:
		_failures.append("empty input should return empty, got size %d" % empty.size())

	# Unknown axis leaves top-lefts unchanged.
	var noop := _mirror([_rect(Vector2i(1, 1), Vector2i(1, 1))], "diagonal")
	_expect_cell("unknown axis no-op", noop[0], Vector2i(1, 1))

	# Reflection is an involution: mirroring twice returns the original.
	var rects := [
		_rect(Vector2i(0, 0), Vector2i(2, 1)),
		_rect(Vector2i(3, 0), Vector2i(1, 1)),
	]
	var once := _mirror(rects, "horizontal")
	var twice := _mirror([_rect(once[0], Vector2i(2, 1)), _rect(once[1], Vector2i(1, 1))], "horizontal")
	_expect_cell("involution A", twice[0], Vector2i(0, 0))
	_expect_cell("involution B", twice[1], Vector2i(3, 0))


# --- Integration: mirror_group_layout updates per-entry anchor offsets --------

func _run_integration_tests() -> void:
	var bm := _make_manager()

	var a := _make_building(bm, Vector2i(1, 1))
	var b := _make_building(bm, Vector2i(1, 1))
	# Two 1x1 ghosts two cells apart. anchor_offset == top-left because anchor==0.
	var entries: Array[Dictionary] = [
		{"ghost": a, "source": a, "anchor_offset": Vector2i(0, 0)},
		{"ghost": b, "source": b, "anchor_offset": Vector2i(2, 0)},
	]
	bm.group_build_entries = entries

	# _apply_group_mirror is the pure offset-recompute step (no ghost placement,
	# so no viewport/cursor dependency to fight in a headless run).
	var applied: bool = bm._apply_group_mirror("horizontal")
	if not applied:
		_failures.append("integration H: _apply_group_mirror returned false")
	_expect_cell("integration H A offset", bm.group_build_entries[0]["anchor_offset"], Vector2i(2, 0))
	_expect_cell("integration H B offset", bm.group_build_entries[1]["anchor_offset"], Vector2i(0, 0))

	# Mirroring back restores the original arrangement.
	bm._apply_group_mirror("horizontal")
	_expect_cell("integration H A restored", bm.group_build_entries[0]["anchor_offset"], Vector2i(0, 0))
	_expect_cell("integration H B restored", bm.group_build_entries[1]["anchor_offset"], Vector2i(2, 0))

	# Vertical mirror of a stacked pair swaps their rows.
	var c := _make_building(bm, Vector2i(1, 1))
	var d := _make_building(bm, Vector2i(1, 1))
	var stacked: Array[Dictionary] = [
		{"ghost": c, "source": c, "anchor_offset": Vector2i(0, 0)},
		{"ghost": d, "source": d, "anchor_offset": Vector2i(0, 3)},
	]
	bm.group_build_entries = stacked
	bm._apply_group_mirror("vertical")
	_expect_cell("integration V C offset", bm.group_build_entries[0]["anchor_offset"], Vector2i(0, 3))
	_expect_cell("integration V D offset", bm.group_build_entries[1]["anchor_offset"], Vector2i(0, 0))

	_free(bm)


# Mirror spins 180 degrees only the buildings whose facing crosses the mirror
# axis: horizontal -> ticks 1/3, vertical -> ticks 0/2. The rotation helper is
# viewport-free, so we exercise it directly across all four orientations.
func _run_rotation_parity_tests() -> void:
	var bm := _make_manager()
	var b0 := _make_building(bm, Vector2i(1, 1))
	var b1 := _make_building(bm, Vector2i(1, 1))
	var b2 := _make_building(bm, Vector2i(1, 1))
	var b3 := _make_building(bm, Vector2i(1, 1))
	b0.rotatedTick = 0
	b1.rotatedTick = 1
	b2.rotatedTick = 2
	b3.rotatedTick = 3
	var entries: Array[Dictionary] = [
		{"ghost": b0, "source": b0, "anchor_offset": Vector2i(0, 0)},
		{"ghost": b1, "source": b1, "anchor_offset": Vector2i(1, 0)},
		{"ghost": b2, "source": b2, "anchor_offset": Vector2i(2, 0)},
		{"ghost": b3, "source": b3, "anchor_offset": Vector2i(3, 0)},
	]
	bm.group_build_entries = entries

	# Horizontal mirror parity: rotate ticks 1/3, leave 0/2.
	bm._rotate_group_ghosts_180_for_tick_parity(1)
	_expect_int("H parity tick0 stays", b0.rotatedTick, 0)
	_expect_int("H parity tick1 -> 3", b1.rotatedTick, 3)
	_expect_int("H parity tick2 stays", b2.rotatedTick, 2)
	_expect_int("H parity tick3 -> 1", b3.rotatedTick, 1)

	# Vertical mirror parity: rotate ticks 0/2, leave 1/3.
	b0.rotatedTick = 0
	b1.rotatedTick = 1
	b2.rotatedTick = 2
	b3.rotatedTick = 3
	bm._rotate_group_ghosts_180_for_tick_parity(0)
	_expect_int("V parity tick0 -> 2", b0.rotatedTick, 2)
	_expect_int("V parity tick1 stays", b1.rotatedTick, 1)
	_expect_int("V parity tick2 -> 0", b2.rotatedTick, 0)
	_expect_int("V parity tick3 stays", b3.rotatedTick, 3)

	_free(bm)


# --- Harness -----------------------------------------------------------------

func _make_manager() -> Node2D:
	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)

	var tml := TileMapLayer.new()
	tml.name = "TileMapLayer"
	world.add_child(tml)

	var bm: Node2D = _bm_script.new()
	bm.name = "BuildManager"
	world.add_child(bm)
	bm.tile_map_layer = null
	return bm


func _make_building(bm: Node2D, footprint: Vector2i) -> Node2D:
	var b: Node2D = _building_script.new()
	b.footprint = footprint
	b.anchor = Vector2i.ZERO
	bm.add_child(b)
	return b


func _free(bm: Node2D) -> void:
	var world := bm.get_parent()
	if world != null:
		world.queue_free()


func _expect_int(label: String, actual, expected: int) -> void:
	if int(actual) != expected:
		_failures.append("%s: expected %d, got %s" % [label, expected, str(actual)])


func _expect_cell(label: String, actual, expected: Vector2i) -> void:
	if not (actual is Vector2i):
		_failures.append("%s: expected Vector2i %s, got non-vector %s" % [label, expected, str(actual)])
		return
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _finish() -> void:
	var result_text: String
	if _failures.is_empty():
		result_text = "Mirror layout smoke tests passed."
		print(result_text)
	else:
		result_text = "Mirror layout smoke tests FAILED:\n- " + "\n- ".join(_failures)
		printerr(result_text)

	var file := FileAccess.open("res://Tools/mirror_test_result.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(result_text)
		file.close()

	quit(0 if _failures.is_empty() else 1)
