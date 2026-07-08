extends SceneTree

# Headless smoke tests for the blueprint engine (Scripts/blueprint_store.gd).
#
# The store is a pure data library, so these tests build blueprint dictionaries
# and serialized annotations as plain data, then assert normalization/validation
# (dropping dangling rails and re-anchoring orphaned annotations), bounds
# computation, JSON round-trip + format gating, migration, and the capture<->
# stamp annotation relinking math (cell offsets and building index<->uid).
#
# Result is written to Tools/blueprint_test_result.txt (matches the alignment/
# flow-sim/save-versioning runner convention) and mirrored to stdout/stderr.

const Store = preload("res://Scripts/blueprint_store.gd")
const Library = preload("res://Scripts/blueprint_library.gd")

var _failures: Array[String] = []
var _checks := 0

const EXPECTED_CHECKS := 52


func _initialize() -> void:
	_test_make_and_normalize()
	_test_drop_dangling_rails()
	_test_bounds()
	_test_orphan_annotation_reanchors()
	_test_json_roundtrip_and_format_gate()
	_test_migration()
	_test_annotation_capture_relink()
	_test_annotation_stamp_relink()
	_test_thumbnail()
	_test_library_crud()
	_finish()


# --- Fixtures ----------------------------------------------------------------

func _building(id: String, ox: int, oy: int, fw := 2, fh := 2, tick := 0, alt := false) -> Dictionary:
	return {
		"id": id,
		"scene_path": "res://Buildings/%s.tscn" % id,
		"anchor_offset": [ox, oy],
		"footprint": [fw, fh],
		"rotated_tick": tick,
		"is_alternate": alt,
		"selection_template": {"Recipe": {"selected": 1, "metadata_path": "res://Recipes/ore.tres"}},
	}


func _rail(fi: int, ti: int, ver := 0) -> Dictionary:
	return {"from_index": fi, "from_port": "out", "to_index": ti, "to_port": "in", "rail_version": ver}


func _saved_cell_annotation(cx: int, cy: int, text := "note") -> Dictionary:
	return {
		"id": "n_%d_%d" % [cx, cy],
		"target_type": "cell",
		"anchor_cell": [cx, cy],
		"target_building_uid": "",
		"text": text,
		"format": "bbcode",
		"created_at_unix": 10.0,
		"updated_at_unix": 10.0,
	}


func _saved_building_annotation(uid: String, cx: int, cy: int, text := "pinned") -> Dictionary:
	return {
		"id": "n_%s" % uid,
		"target_type": "building",
		"anchor_cell": [cx, cy],
		"target_building_uid": uid,
		"text": text,
		"format": "bbcode",
		"created_at_unix": 10.0,
		"updated_at_unix": 10.0,
	}


# --- Tests -------------------------------------------------------------------

func _test_make_and_normalize() -> void:
	var bp := Store.make_blueprint("My Base", "desc",
		[_building("Smelter", 0, 0), _building("Assembler", 4, 0)],
		[_rail(0, 1)], [], "", 500.0)
	_expect_str("format stamped", String(bp.get("format", "")), Store.FORMAT)
	_expect_num("version stamped", float(bp.get("version", 0)), float(Store.CURRENT_VERSION))
	_expect_num("created timestamp", float(bp.get("created_at_unix", 0)), 500.0)
	_expect_num("two buildings kept", float((bp["buildings"] as Array).size()), 2.0)
	_expect_num("one rail kept", float((bp["rails"] as Array).size()), 1.0)
	# rotated_tick wraps into 0..3
	var wrapped := Store.normalize({"buildings": [_building("Smelter", 0, 0, 2, 2, 6)]})
	_expect_num("rotated_tick wrapped mod 4", float(wrapped["buildings"][0]["rotated_tick"]), 2.0)
	# building missing both id and scene_path is dropped
	var dropped := Store.normalize({"buildings": [{"anchor_offset": [1, 1]}]})
	_expect_num("id-less building dropped", float((dropped["buildings"] as Array).size()), 0.0)
	# idempotence
	var again := Store.normalize(bp)
	_expect_num("normalize idempotent building count", float((again["buildings"] as Array).size()), 2.0)
	_expect_str("normalize idempotent name", String(again.get("name", "")), "My Base")


func _test_drop_dangling_rails() -> void:
	# A rail pointing past the building list must be dropped during normalize.
	var raw := {
		"buildings": [_building("Smelter", 0, 0)],
		"rails": [_rail(0, 5), _rail(0, 0), _rail(-1, 0)],
	}
	var norm := Store.normalize(raw)
	_expect_num("only in-range rail survives", float((norm["rails"] as Array).size()), 1.0)
	_expect_num("surviving rail to_index", float(norm["rails"][0]["to_index"]), 0.0)


func _test_bounds() -> void:
	# Two 2x2 buildings at (0,0) and (4,0): span x 0..6, y 0..2.
	var b := [_building("A", 0, 0, 2, 2), _building("B", 4, 0, 2, 2)]
	var bounds := Store.compute_bounds(b)
	_expect_num("bounds width", float(bounds.x), 6.0)
	_expect_num("bounds height", float(bounds.y), 2.0)
	# A tall 1x3 shifts height.
	var b2 := [_building("A", 0, 0, 2, 2), _building("C", 0, 1, 1, 3)]
	var bounds2 := Store.compute_bounds(b2)
	_expect_num("bounds height tall", float(bounds2.y), 4.0)
	_expect_num("empty bounds zero", float(Store.compute_bounds([]).x), 0.0)


func _test_orphan_annotation_reanchors() -> void:
	# A building-typed annotation whose index is out of range must fall back to
	# a cell anchor rather than vanish.
	var raw := {
		"buildings": [_building("Smelter", 0, 0)],
		"annotations": [{
			"target_type": "building",
			"anchor_offset": [1, 1],
			"target_building_index": 7,
			"text": "orphan",
			"format": "bbcode",
		}],
	}
	var norm := Store.normalize(raw)
	_expect_num("orphan annotation retained", float((norm["annotations"] as Array).size()), 1.0)
	_expect_str("orphan re-anchored to cell", String(norm["annotations"][0]["target_type"]), Store.TARGET_CELL)
	_expect_num("orphan index cleared", float(norm["annotations"][0]["target_building_index"]), -1.0)


func _test_json_roundtrip_and_format_gate() -> void:
	var bp := Store.make_blueprint("RT", "d",
		[_building("Smelter", 0, 0, 2, 2, 1, true)], [], [], "QUJD", 1.0)
	var text := Store.to_json(bp)
	var back := Store.from_json(text)
	_expect_bool("roundtrip parses", not back.is_empty(), true)
	_expect_str("roundtrip name", String(back.get("name", "")), "RT")
	_expect_bool("roundtrip is_alternate", bool(back["buildings"][0]["is_alternate"]), true)
	_expect_num("roundtrip rotated_tick", float(back["buildings"][0]["rotated_tick"]), 1.0)
	_expect_str("roundtrip thumbnail preserved", String(back.get("thumbnail_png_b64", "")), "QUJD")
	# Foreign / malformed JSON is rejected.
	_expect_bool("non-blueprint json rejected", Store.from_json('{"format":"srbp","version":5}').is_empty(), true)
	_expect_bool("garbage json rejected", Store.from_json("not json at all").is_empty(), true)


func _test_migration() -> void:
	# A version-0 doc is stamped up to current without losing fields.
	var legacy := {"format": Store.FORMAT, "version": 0, "name": "old", "buildings": [_building("Smelter", 0, 0)]}
	var migrated := Store.migrate(legacy)
	_expect_num("migrate bumps version", float(migrated.get("version", 0)), float(Store.CURRENT_VERSION))
	_expect_str("migrate keeps name", String(migrated.get("name", "")), "old")


func _test_annotation_capture_relink() -> void:
	# Group anchor at cell (10, 5). A cell note at (12, 6) becomes offset (2, 1).
	var origin := Vector2i(10, 5)
	var uid_to_index := {"bldg_a": 0, "bldg_b": 1}
	var cell_bp := Store.annotation_to_blueprint(_saved_cell_annotation(12, 6), origin, uid_to_index)
	_expect_num("capture cell offset x", float(cell_bp["anchor_offset"][0]), 2.0)
	_expect_num("capture cell offset y", float(cell_bp["anchor_offset"][1]), 1.0)
	_expect_str("capture cell type", String(cell_bp["target_type"]), Store.TARGET_CELL)
	# A note pinned to a captured building resolves to its index.
	var pinned_bp := Store.annotation_to_blueprint(_saved_building_annotation("bldg_b", 12, 6), origin, uid_to_index)
	_expect_str("capture building type", String(pinned_bp["target_type"]), Store.TARGET_BUILDING)
	_expect_num("capture building index", float(pinned_bp["target_building_index"]), 1.0)
	# A note pinned to a building OUTSIDE the group degrades to a cell anchor.
	var foreign_bp := Store.annotation_to_blueprint(_saved_building_annotation("bldg_z", 12, 6), origin, uid_to_index)
	_expect_str("capture foreign pin degrades to cell", String(foreign_bp["target_type"]), Store.TARGET_CELL)


func _test_annotation_stamp_relink() -> void:
	# Stamp the earlier notes at origin (20, 20). Offsets add back on.
	var place := Vector2i(20, 20)
	var index_to_uid := {0: "new_a", 1: "new_b"}
	var cell_ann := {"target_type": "cell", "anchor_offset": [2, 1], "target_building_index": -1, "text": "t", "format": "bbcode"}
	var out_cell := Store.annotation_from_blueprint(cell_ann, place, index_to_uid, "id1", 99.0)
	_expect_num("stamp cell anchor x", float(out_cell["anchor_cell"][0]), 22.0)
	_expect_num("stamp cell anchor y", float(out_cell["anchor_cell"][1]), 21.0)
	_expect_str("stamp new id applied", String(out_cell["id"]), "id1")
	_expect_num("stamp timestamp applied", float(out_cell["created_at_unix"]), 99.0)
	# A building-pinned note re-binds to the freshly created building's uid.
	var pin_ann := {"target_type": "building", "anchor_offset": [0, 0], "target_building_index": 1, "text": "t", "format": "bbcode"}
	var out_pin := Store.annotation_from_blueprint(pin_ann, place, index_to_uid, "id2")
	_expect_str("stamp rebinds uid", String(out_pin["target_building_uid"]), "new_b")
	_expect_str("stamp keeps building type", String(out_pin["target_type"]), Store.TARGET_BUILDING)


func _test_thumbnail() -> void:
	var buildings := [_building("smelter", 0, 0, 2, 2), _building("assembler", 4, 0, 2, 2)]
	var b64 := Store.render_thumbnail_b64(buildings)
	_expect_bool("thumbnail non-empty", b64 != "", true)
	var img := Image.new()
	var err := img.load_png_from_buffer(Marshalls.base64_to_raw(b64))
	_expect_num("thumbnail decodes as png", float(err), float(OK))
	_expect_bool("thumbnail has pixels", img.get_width() > 0 and img.get_height() > 0, true)
	_expect_bool("empty blueprint has no thumbnail", Store.render_thumbnail_b64([]) == "", true)


func _test_library_crud() -> void:
	# Isolated temp root so the test never touches a real user's library.
	var root := "user://blueprint_test_tmp_%d" % Time.get_ticks_usec()
	var lib = Library.new(root)

	var bp_a := Store.make_blueprint("Power Block", "reactor cluster",
		[_building("Reactor", 0, 0), _building("Battery", 3, 0)], [_rail(0, 1)], [], "", 100.0)
	var bp_b := Store.make_blueprint("Smelter Row", "",
		[_building("Smelter", 0, 0)], [], [], "", 200.0)

	var id_a := lib.save_new(bp_a)
	var id_b := lib.save_new(bp_b)
	_expect_str("id slugified from name", id_a, "power-block")
	_expect_bool("saved file exists", lib.exists(id_a), true)

	var entries := lib.list_entries()
	_expect_num("library lists both", float(entries.size()), 2.0)
	# Newest updated first: bp_b (200) before bp_a (100).
	_expect_str("list sorted newest first", String(entries[0].get("id", "")), id_b)
	_expect_num("entry building count", float(entries[1].get("building_count", 0)), 2.0)
	_expect_num("entry rail count", float(entries[1].get("rail_count", 0)), 1.0)

	var loaded := lib.load(id_a)
	_expect_str("load roundtrips name", String(loaded.get("name", "")), "Power Block")
	_expect_num("load roundtrips buildings", float((loaded["buildings"] as Array).size()), 2.0)

	# Colliding name gets a distinct id, does not clobber the first.
	var id_dup := lib.save_new(Store.make_blueprint("Power Block", "second", [_building("Reactor", 0, 0)], [], []))
	_expect_str("collision id suffixed", id_dup, "power-block-2")
	_expect_num("collision did not overwrite", float((lib.load(id_a)["buildings"] as Array).size()), 2.0)

	# Rename reflects in name but keeps the id/handle stable.
	_expect_bool("rename ok", lib.rename(id_b, "Renamed Row"), true)
	_expect_str("rename applied", String(lib.load(id_b).get("name", "")), "Renamed Row")

	# Export -> import produces an independent copy.
	var exported := lib.export_text(id_a)
	_expect_bool("export non-empty", exported != "", true)
	var id_imported := lib.import_text(exported)
	_expect_bool("import created entry", id_imported != "", true)
	_expect_str("import preserved name", String(lib.load(id_imported).get("name", "")), "Power Block")
	_expect_bool("import rejects garbage", lib.import_text("nonsense") == "", true)

	# Delete removes just that entry.
	_expect_bool("delete ok", lib.delete(id_b), true)
	_expect_bool("deleted gone", lib.exists(id_b), false)
	_expect_bool("delete missing returns false", lib.delete("does-not-exist"), false)

	_cleanup_dir(root)


func _cleanup_dir(root: String) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute("%s/%s" % [root, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(root)


# --- Harness -----------------------------------------------------------------

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
	var result_path := "res://Tools/blueprint_test_result.txt"
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if _failures.is_empty():
		var msg := "Blueprint store smoke tests passed (%d checks)." % _checks
		print(msg)
		if file != null:
			file.store_string(msg + "\n")
			file.close()
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		if file != null:
			file.store_string("Blueprint tests FAILED:\n" + "\n".join(_failures) + "\n")
			file.close()
		quit(1)
