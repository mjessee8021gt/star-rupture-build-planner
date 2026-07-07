extends SceneTree

# Headless smoke tests for the Save Engine V2 version store
# (Scripts/save_version_store.gd).
#
# The store is a pure data library, so these tests build normalized/raw save
# states as plain Dictionaries, then assert normalization, diffing, forward
# delta round-trips, reconstruction, version app(no-op vs change), cap/prune
# folding, migration, and JSON int/float drift tolerance.
#
# Result is written to Tools/save_versioning_test_result.txt (matches the
# alignment/flow-sim runner convention) and mirrored to stdout/stderr.

const Store = preload("res://Scripts/save_version_store.gd")

var _failures: Array[String] = []
var _checks := 0


const EXPECTED_CHECKS := 30

func _initialize() -> void:
	_test_normalize_roundtrip()
	_test_diff_basic()
	_test_delta_roundtrip()
	_test_reconstruct_chain()
	_test_append_noop_and_change()
	_test_cap_prune()
	_test_migration_and_restore()
	_test_json_numeric_drift()
	_test_document_json_roundtrip()
	_finish()


# --- Fixtures ----------------------------------------------------------------

func _building(uid: String, x: float, y: float, recipe := "none", rot := 0.0) -> Dictionary:
	return {
		"uid": uid,
		"id": "smelter",
		"scene_path": "res://Buildings/Smelter.tscn",
		"position": [x, y],
		"rotation_degrees": rot,
		"rotated_tick": 0,
		"is_alternate": false,
		"anchor_cell": [int(x), int(y)],
		"footprint": [2, 2],
		"recipe": {"selected": 0, "metadata_path": recipe},
		"purity": {},
		"core_level": {}
	}


func _annotation(id: String, text: String) -> Dictionary:
	return {
		"id": id,
		"target_type": "cell",
		"anchor_cell": [1, 1],
		"target_building_uid": "",
		"text": text,
		"format": "bbcode",
		"created_at_unix": 100.0,
		"updated_at_unix": 100.0
	}


func _raw_state(buildings: Array, paths: Array, annotations: Array, heat := 10) -> Dictionary:
	# Mimics main.gd._collect_save_state output (index-referenced paths, volatile
	# view fields present so normalization must strip them).
	return {
		"version": 4,
		"saved_at_unix": 123456.0,
		"heat": heat,
		"power": 5,
		"cost_bbm": 1,
		"cost_ibm": 2,
		"cost_meteor_cores": 3,
		"camera": {"position": [9, 9], "zoom": [1, 1]},
		"production_panel_visible": true,
		"buildings": buildings,
		"occupied_cells": ["0,0", "1,1"],
		"paths": paths,
		"annotations": annotations
	}


# --- Tests -------------------------------------------------------------------

func _test_normalize_roundtrip() -> void:
	var b0 := _building("a", 0, 0)
	var b1 := _building("b", 5, 5)
	var paths := [{"from_index": 0, "to_index": 1, "from_port": "out", "to_port": "in", "rail_version": 2}]
	var raw := _raw_state([b0, b1], paths, [_annotation("n1", "hi")])

	var norm := Store.normalize_state(raw)
	_expect_bool("normalize strips volatile camera", norm.has("camera"), false)
	_expect_bool("normalize strips occupied_cells", norm.has("occupied_cells"), false)
	_expect_num("normalize keeps heat scalar", float(norm.get("heat", -1)), 10.0)
	_expect_str("normalize path uses from_uid", String(norm["paths"][0]["from_uid"]), "a")
	_expect_str("normalize path uses to_uid", String(norm["paths"][0]["to_uid"]), "b")

	# Idempotence: normalizing an already-normalized state is stable.
	var norm2 := Store.normalize_state(norm)
	_expect_bool("normalize idempotent", Store.values_equal(norm, norm2), true)

	# to_apply_state re-resolves uid paths back to indices against buildings.
	var applied := Store.to_apply_state(norm)
	_expect_num("to_apply from_index resolved", float(applied["paths"][0]["from_index"]), 0.0)
	_expect_num("to_apply to_index resolved", float(applied["paths"][0]["to_index"]), 1.0)


func _test_diff_basic() -> void:
	var before := Store.normalize_state(_raw_state(
		[_building("a", 0, 0, "ore"), _building("b", 5, 5)],
		[], [_annotation("n1", "keep")], 10))
	var after := Store.normalize_state(_raw_state(
		[_building("a", 0, 0, "ore"), _building("c", 9, 9), _building("b", 5, 6)],
		[], [_annotation("n1", "keep")], 12))

	var diff := Store.diff_states(before, after)
	_expect_bool("diff detects added building c", diff["buildings"]["added"].has("c"), true)
	_expect_bool("diff no false-add for a", diff["buildings"]["added"].has("a"), false)
	_expect_bool("diff detects modified b (moved)", diff["buildings"]["modified"].has("b"), true)
	_expect_bool("diff modified b reports position field", diff["buildings"]["modified"]["b"]["fields"].has("position"), true)
	_expect_bool("diff scalars heat changed", diff["scalars"].has("heat"), true)
	_expect_bool("diff not empty", Store.diff_is_empty(diff), false)

	var same := Store.diff_states(before, before)
	_expect_bool("diff of identical is empty", Store.diff_is_empty(same), true)


func _test_delta_roundtrip() -> void:
	# A single forward delta must transform `before` into exactly `after`,
	# covering building add/remove/modify, path change, and scalar change.
	var before := Store.normalize_state(_raw_state(
		[_building("a", 0, 0), _building("b", 5, 5)],
		[{"from_index": 0, "to_index": 1, "from_port": "o", "to_port": "i", "rail_version": 1}],
		[_annotation("n1", "one")], 10))
	var after := Store.normalize_state(_raw_state(
		[_building("a", 0, 1), _building("c", 8, 8)],
		[{"from_index": 0, "to_index": 1, "from_port": "o", "to_port": "i", "rail_version": 3}],
		[_annotation("n2", "two")], 20))

	var delta := Store.make_delta(before, after)
	var result := Store.apply_delta(before, delta)
	_expect_bool("delta round-trip reproduces after", Store.values_equal(result, after), true)

	# Empty delta between identical states.
	_expect_bool("delta of identical is empty", Store.make_delta(after, after).is_empty(), true)


func _test_reconstruct_chain() -> void:
	var v1 := Store.normalize_state(_raw_state([_building("a", 0, 0)], [], [], 1))
	var v2 := Store.normalize_state(_raw_state([_building("a", 0, 0), _building("b", 2, 2)], [], [], 2))
	var v3 := Store.normalize_state(_raw_state([_building("b", 2, 2)], [], [], 3))

	var deltas: Array = [
		{"version_id": 2, "ops": Store.make_delta(v1, v2)},
		{"version_id": 3, "ops": Store.make_delta(v2, v3)}
	]
	_expect_bool("reconstruct with no deltas == v1", Store.values_equal(Store.reconstruct(v1, [], -1), v1), true)
	_expect_bool("reconstruct up_to 0 == v2", Store.values_equal(Store.reconstruct(v1, deltas, 0), v2), true)
	_expect_bool("reconstruct all == v3", Store.values_equal(Store.reconstruct(v1, deltas, -1), v3), true)


func _test_append_noop_and_change() -> void:
	var v1_raw := _raw_state([_building("a", 0, 0)], [], [], 1)
	var hist := Store.new_history(v1_raw, "Imported", 100.0)
	_expect_num("new history has head v1", float(hist["head_version_id"]), 1.0)
	_expect_num("new history single version", float(Store.list_versions(hist).size()), 1.0)

	# Appending the identical state is a no-op.
	var noop := Store.append_version(hist, v1_raw, "auto", Store.KIND_AUTO, 101.0)
	_expect_bool("append identical is no-op", bool(noop["added"]), false)

	# Appending a changed state adds a version and advances head.
	var v2_raw := _raw_state([_building("a", 0, 0), _building("b", 3, 3)], [], [], 1)
	var res := Store.append_version(hist, v2_raw, "Added b", Store.KIND_MANUAL, 102.0)
	_expect_bool("append change adds version", bool(res["added"]), true)
	var hist2: Dictionary = res["history"]
	_expect_num("head advanced to v2", float(hist2["head_version_id"]), 2.0)
	_expect_num("two versions listed", float(Store.list_versions(hist2).size()), 2.0)

	# Head state matches what we appended.
	var head_state := Store.state_at(hist2, int(hist2["head_version_id"]))
	_expect_bool("head state == appended v2", Store.values_equal(head_state, Store.normalize_state(v2_raw)), true)


func _test_cap_prune() -> void:
	# cap=3 keeps base + 2 deltas; older versions fold into base but the folded
	# result must still reconstruct the head correctly.
	var hist := Store.new_history(_raw_state([_building("a", 0, 0)], [], [], 0), "Imported", 0.0, 3)
	var expected_head: Dictionary = {}
	for i in range(1, 6):
		var raw := _raw_state([_building("a", 0, 0)], [], [], i)
		var res := Store.append_version(hist, raw, "v%d" % i, Store.KIND_AUTO, float(i))
		hist = res["history"]
		expected_head = Store.normalize_state(raw)

	var versions := Store.list_versions(hist)
	_expect_num("cap enforced: 3 versions retained", float(versions.size()), 3.0)
	var head_state := Store.state_at(hist, int(hist["head_version_id"]))
	_expect_bool("head still correct after folding", Store.values_equal(head_state, expected_head), true)
	# Oldest retained version (folded base) is reconstructable.
	var oldest_id := int(versions[0]["version_id"])
	_expect_bool("folded base reconstructable", not Store.state_at(hist, oldest_id).is_empty(), true)


func _test_migration_and_restore() -> void:
	# Legacy v4 save wrapped as history == single imported baseline.
	var legacy := _raw_state([_building("a", 0, 0), _building("b", 5, 5)], [], [], 7)
	var hist := Store.new_history(legacy, "Imported", 50.0)
	_expect_bool("migrated base == legacy state", Store.values_equal(Store.state_at(hist, 1), Store.normalize_state(legacy)), true)

	# Make an edit, then restore the original: head should equal v1 again.
	var edited := _raw_state([_building("a", 0, 0)], [], [], 7)  # deleted b
	hist = Store.append_version(hist, edited, "delete b", Store.KIND_MANUAL, 51.0)["history"]
	var restored_state := Store.state_at(hist, 1)
	var restore_res := Store.append_version(hist, Store.to_apply_state(restored_state), "Restored v1", Store.KIND_RESTORE, 52.0)
	_expect_bool("restore creates a new version", bool(restore_res["added"]), true)
	var hist3: Dictionary = restore_res["history"]
	var new_head := Store.state_at(hist3, int(hist3["head_version_id"]))
	_expect_bool("restored head matches original v1", Store.values_equal(new_head, Store.normalize_state(legacy)), true)


func _test_json_numeric_drift() -> void:
	# Simulate a save->JSON->load cycle where ints become floats. The store must
	# not treat 0 vs 0.0 as a change (which would spawn phantom versions).
	var raw := _raw_state([_building("a", 0, 0)], [], [], 5)
	var json_text := JSON.stringify(raw)
	var reloaded = JSON.parse_string(json_text)
	_expect_bool("json reparsed to dictionary", reloaded is Dictionary, true)

	var before := Store.normalize_state(raw)
	var after := Store.normalize_state(reloaded)
	_expect_bool("no phantom diff after json round-trip", Store.diff_is_empty(Store.diff_states(before, after)), true)
	_expect_bool("values_equal treats 0 and 0.0 equal", Store.values_equal(0, 0.0), true)


func _test_document_json_roundtrip() -> void:
	# Mirrors main.gd's save/load: a document = live top-level state + nested
	# history, serialized to JSON and reopened. After reload, the head must
	# reconstruct to the last-saved plan (this is what _apply_save_text applies).
	var hist := Store.new_history(_raw_state([_building("a", 0, 0)], [], [], 1), "Imported", 1.0)
	hist = Store.append_version(hist, _raw_state([_building("a", 0, 0), _building("b", 4, 4)], [], [], 2), "Saved", Store.KIND_MANUAL, 2.0)["history"]
	var expected_head := Store.state_at(hist, int(hist["head_version_id"]))

	var document := _raw_state([_building("a", 0, 0), _building("b", 4, 4)], [], [], 2)
	document["version"] = 5
	document["history"] = hist

	var reloaded = JSON.parse_string(JSON.stringify(document))
	_expect_bool("document reparsed", reloaded is Dictionary, true)
	var loaded_history: Dictionary = reloaded["history"]
	var head_id := int(loaded_history.get("head_version_id", -1))
	var head_state := Store.state_at(loaded_history, head_id)
	_expect_bool("reloaded head reconstructs last save", Store.values_equal(head_state, expected_head), true)
	# The applied (denormalized) state must round-trip its paths/buildings too.
	var applied := Store.to_apply_state(head_state)
	_expect_num("applied head has 2 buildings", float((applied["buildings"] as Array).size()), 2.0)


# --- Assertions --------------------------------------------------------------

func _expect_bool(label: String, got: bool, want: bool) -> void:
	_checks += 1
	if got != want:
		_fail("%s: got %s want %s" % [label, got, want])


func _expect_num(label: String, got: float, want: float, tol := 0.001) -> void:
	_checks += 1
	if abs(got - want) > tol:
		_fail("%s: got %s want %s" % [label, got, want])


func _expect_str(label: String, got: String, want: String) -> void:
	_checks += 1
	if got != want:
		_fail("%s: got '%s' want '%s'" % [label, got, want])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	# A compile failure in the store would abort each test before it asserts,
	# leaving _failures empty; the check-count floor turns that into a failure.
	if _checks < EXPECTED_CHECKS:
		_fail("only %d checks ran (expected >= %d) - tests aborted early" % [_checks, EXPECTED_CHECKS])
	var result_path := "res://Tools/save_versioning_test_result.txt"
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if _failures.is_empty():
		var msg := "Save versioning store smoke tests passed."
		print(msg)
		if file != null:
			file.store_string(msg + "\n")
			file.close()
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		if file != null:
			file.store_string("Save versioning tests FAILED:\n" + "\n".join(_failures) + "\n")
			file.close()
		quit(1)
