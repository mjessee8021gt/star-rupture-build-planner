extends Node

# Headless integration smoke for the SaveLoadController extraction. Runs as a real
# scene (so project autoloads — ProdLedger, BuildRegistry, RecipeRegistry — are
# registered, which a --script SceneTree does NOT do). Instantiates the real Main
# scene and drives collect -> JSON -> apply -> PDF -> history-capture through the
# moved spine. Run with:
#   godot --headless res://Tools/TestSaveLoadRoundtrip.tscn --path .
# Exits 0 on pass, 1 on failure.

const MAIN_SCENE := preload("res://Scenes/Main.tscn")


func _ready() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	# Let Main._ready + its deferred passes settle.
	for _i in range(5):
		await get_tree().process_frame
	_run(main)


func _fail(msg: String) -> void:
	printerr("SaveLoad round-trip FAILED: %s" % msg)
	get_tree().quit(1)


func _run(main: Node) -> void:
	var save_load = main._save_load
	if save_load == null:
		_fail("_save_load controller is null after _ready")
		return

	# 1) A minimal one-building plan, round-tripped through JSON like a real save file.
	var plan := {
		"version": 5,
		"heat": 0, "power": 0, "cost_bbm": 0, "cost_ibm": 0, "cost_meteor_cores": 0,
		"camera": {"position": [0, 0], "zoom": [1, 1]},
		"production_panel_visible": false,
		"buildings": [{
			"id": "smelter",
			"position": [128.0, 64.0],
			"rotation_degrees": 0.0,
			"recipe": {}, "purity": {}, "core_level": {},
		}],
		"occupied_cells": [],
		"paths": [],
		"annotations": [],
	}
	var parsed = JSON.parse_string(JSON.stringify(plan))
	if not (parsed is Dictionary):
		_fail("JSON round-trip did not yield a Dictionary")
		return

	# 2) apply_save_state must clear + rebuild the live scene (the moved spine).
	save_load.apply_save_state(parsed)
	var child_count: int = main.buildings_root.get_child_count()
	if child_count != 1:
		_fail("expected 1 building after apply, got %d" % child_count)
		return
	if main.build_manager.occupied_cells.is_empty():
		_fail("occupancy was not rebuilt from the loaded building")
		return

	# 3) collect_save_state must serialize the live scene back out.
	var state = save_load.collect_save_state()
	if int(state.get("version", -1)) != 5:
		_fail("collect_save_state version mismatch: %s" % str(state.get("version")))
		return
	var buildings = state.get("buildings", [])
	if not (buildings is Array) or (buildings as Array).size() != 1:
		_fail("collect_save_state did not serialize the placed building")
		return

	# 4) The version-aware document wrapper (stays in main) must attach history.
	var doc = main._collect_save_document()
	if not doc.has("history"):
		_fail("_collect_save_document did not attach the version history block")
		return

	# 5) PDF export path (moved) must produce a real PDF.
	var pdf: PackedByteArray = save_load.build_pdf_bytes()
	if pdf.size() < 200 or pdf[0] != 0x25 or pdf[1] != 0x50 or pdf[2] != 0x44 or pdf[3] != 0x46:
		_fail("build_pdf_bytes did not return a %%PDF document (size=%d)" % pdf.size())
		return

	# 6) History-capture path (undo/redo) must strip volatile keys and re-apply cleanly.
	var cap = main._capture_history_state()
	if cap.has("camera") or cap.has("saved_at_unix") or cap.has("production_panel_visible"):
		_fail("_capture_history_state did not strip volatile keys")
		return
	main._apply_history_state(state)
	if main.buildings_root.get_child_count() != 1:
		_fail("history replay lost the building")
		return

	print("SaveLoad round-trip smoke passed (6 checks).")
	get_tree().quit(0)
