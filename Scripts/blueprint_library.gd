extends RefCounted

# Blueprint library - on-disk CRUD over a folder of .srbpb files.
#
# The library is the user's persistent collection, kept under user:// so it
# survives across plans and (on the web build) across reloads via the browser's
# persistent storage. Each blueprint is one JSON file named "<id>.srbpb", where
# the id is a slug of its name plus a uniqueness suffix; the id doubles as the
# file stem and the stable handle the UI passes around.
#
# This layer only touches the filesystem and delegates all shape/validation to
# blueprint_store.gd. Import/export from arbitrary paths is here too; the web
# build's browser file picker/download lives in the UI layer (it calls
# export_text / import_text on this store).
#
# Instantiate with a root override in tests: BlueprintLibrary.new("user://tmp").

const Store = preload("res://Scripts/blueprint_store.gd")

const DEFAULT_ROOT := "user://blueprints"
const EXTENSION := "srbpb"

var _root: String


func _init(root := DEFAULT_ROOT) -> void:
	_root = root
	_ensure_dir()


func get_root() -> String:
	return _root


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(_root):
		DirAccess.make_dir_recursive_absolute(_root)


func _path_for(id: String) -> String:
	return "%s/%s.%s" % [_root, id, EXTENSION]


# --- Listing / loading -------------------------------------------------------

# Lightweight metadata for every blueprint in the library, newest first. Does
# not carry the full building/rail data or the thumbnail bytes (keeps the list
# cheap to build); the UI loads the full blueprint on demand via load().
func list_entries() -> Array:
	var entries: Array = []
	var dir := DirAccess.open(_root)
	if dir == null:
		return entries
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == EXTENSION:
			var id := file_name.get_basename()
			var bp := _read(id)
			if not bp.is_empty():
				entries.append(_entry_meta(id, bp))
		file_name = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a, b): return float(a.get("updated_at_unix", 0)) > float(b.get("updated_at_unix", 0)))
	return entries


func _entry_meta(id: String, bp: Dictionary) -> Dictionary:
	var c := Store.counts(bp)
	return {
		"id": id,
		"name": String(bp.get("name", "")),
		"description": String(bp.get("description", "")),
		"created_at_unix": float(bp.get("created_at_unix", 0.0)),
		"updated_at_unix": float(bp.get("updated_at_unix", 0.0)),
		"bounds": bp.get("bounds", [0, 0]),
		"building_count": int(c.get("buildings", 0)),
		"rail_count": int(c.get("rails", 0)),
		"annotation_count": int(c.get("annotations", 0)),
		"has_thumbnail": String(bp.get("thumbnail_png_b64", "")) != "",
	}


# Full blueprint for an id, or {} if missing / unreadable / not a blueprint.
func load(id: String) -> Dictionary:
	return _read(id)


func exists(id: String) -> bool:
	return FileAccess.file_exists(_path_for(id))


func _read(id: String) -> Dictionary:
	var path := _path_for(id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	return Store.from_json(file.get_as_text())


# --- Saving ------------------------------------------------------------------

# Write a brand-new blueprint, assigning a fresh unique id from its name.
# Returns the id, or "" on failure.
func save_new(bp: Dictionary) -> String:
	var id := _unique_id(String(bp.get("name", "")))
	if _write(id, bp):
		return id
	return ""


# Overwrite an existing blueprint in place (bumps updated_at_unix).
func overwrite(id: String, bp: Dictionary) -> bool:
	var updated := bp.duplicate(true)
	updated["updated_at_unix"] = float(Time.get_unix_time_from_system())
	return _write(id, updated)


func rename(id: String, new_name: String) -> bool:
	var bp := _read(id)
	if bp.is_empty():
		return false
	bp["name"] = new_name
	bp["updated_at_unix"] = float(Time.get_unix_time_from_system())
	return _write(id, bp)


func delete(id: String) -> bool:
	var path := _path_for(id)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


func _write(id: String, bp: Dictionary) -> bool:
	_ensure_dir()
	var file := FileAccess.open(_path_for(id), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(Store.to_json(bp))
	file.close()
	return true


# --- Import / export ---------------------------------------------------------

# Serialized JSON for an existing blueprint (used by the web download bridge).
func export_text(id: String) -> String:
	var bp := _read(id)
	if bp.is_empty():
		return ""
	return Store.to_json(bp)


# Write an existing blueprint out to an arbitrary path (desktop file dialog).
func export_to(id: String, dest_path: String) -> bool:
	var text := export_text(id)
	if text == "":
		return false
	var file := FileAccess.open(dest_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


# Bring a blueprint's JSON text into the library as a new entry. Returns the new
# id, or "" if the text is not a valid blueprint.
func import_text(text: String) -> String:
	var bp := Store.from_json(text)
	if bp.is_empty():
		return ""
	return save_new(bp)


func import_from(src_path: String) -> String:
	if not FileAccess.file_exists(src_path):
		return ""
	var file := FileAccess.open(src_path, FileAccess.READ)
	if file == null:
		return ""
	return import_text(file.get_as_text())


# --- Id generation -----------------------------------------------------------

func _unique_id(name: String) -> String:
	var base := _slugify(name)
	if not exists(base):
		return base
	var n := 2
	while exists("%s-%d" % [base, n]):
		n += 1
	return "%s-%d" % [base, n]


func _slugify(name: String) -> String:
	var out := ""
	for c in name.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "-"
		# other characters are dropped
	while out.contains("--"):
		out = out.replace("--", "-")
	out = out.lstrip("-").rstrip("-")
	if out == "":
		out = "blueprint"
	return out
