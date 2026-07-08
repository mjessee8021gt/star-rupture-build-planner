extends RefCounted

# Blueprint engine - pure data library (no scene dependencies).
#
# A blueprint is a portable, plan-independent capture of a group of buildings,
# their internal rails, and any annotations that fell inside the selection. It
# is stored in its own .srbpb file (JSON), *separate* from a factory's .srbp
# save, so the same layout can be stamped into any plan. Buildings reference
# their registered type `id` and their dropdown selections by metadata path, so
# nothing here is tied to a specific plan's coordinate space or building uids.
#
# Everything operates on plain Dictionaries / Arrays so it can be exercised
# headlessly (see Tools/test_blueprint.gd). BuildManager owns the live capture
# (reading ghost/source nodes) and the live stamp (rebuilding ghosts); this
# library owns the on-disk shape, validation, migration, bounds, and the
# annotation index<->uid relinking math.
#
# Canonical blueprint shape:
#   {
#     format: "srbp-blueprint", version: 1,
#     name, description: String,
#     created_at_unix, updated_at_unix: float,
#     bounds: [w, h],                 # footprint of the whole stamp, in cells
#     thumbnail_png_b64: String,      # base64 of a preview PNG ("" when none)
#     buildings: [ {
#       id, scene_path: String,
#       anchor_offset: [x, y],        # top-left anchor cell, relative to stamp origin
#       footprint: [w, h],            # rotated footprint (drives bounds/collision)
#       rotated_tick: int, is_alternate: bool,
#       selection_template: { <OptionName>: {selected, metadata_path} }
#     }, ... ],
#     rails: [ {from_index, from_port, to_index, to_port, rail_version}, ... ],
#     annotations: [ {
#       target_type: "cell"|"building",
#       anchor_offset: [x, y],        # relative to stamp origin (cell anchor)
#       target_building_index: int,   # index into buildings[], or -1
#       text, format: String
#     }, ... ]
#   }

const Palette = preload("res://Scripts/palette.gd")

const FORMAT := "srbp-blueprint"
const CURRENT_VERSION := 1

const TARGET_CELL := "cell"
const TARGET_BUILDING := "building"

# Schematic thumbnail sizing (see render_thumbnail_b64).
const THUMB_MAX_PX := 240
const THUMB_MIN_CELL_PX := 3
const THUMB_MAX_CELL_PX := 22


# --- Construction ------------------------------------------------------------

# Assemble a canonical blueprint from already-captured parts. `buildings`,
# `rails`, and `annotations` are plain arrays in (near) canonical shape; this
# normalizes them, computes bounds, and stamps timestamps.
static func make_blueprint(name: String, description: String, buildings: Array, rails: Array, annotations: Array, thumbnail_png_b64 := "", now_unix := -1.0) -> Dictionary:
	var ts := now_unix if now_unix >= 0.0 else float(Time.get_unix_time_from_system())
	var bp := {
		"format": FORMAT,
		"version": CURRENT_VERSION,
		"name": name,
		"description": description,
		"created_at_unix": ts,
		"updated_at_unix": ts,
		"thumbnail_png_b64": String(thumbnail_png_b64),
		"buildings": buildings,
		"rails": rails,
		"annotations": annotations,
	}
	return normalize(bp)


# --- Normalization / validation ----------------------------------------------

# Coerce an arbitrary dictionary (freshly built or freshly loaded) into the
# canonical shape: typed arrays, valid indices, recomputed bounds. Invalid
# entries are dropped rather than raised. Idempotent.
static func normalize(raw: Dictionary) -> Dictionary:
	var buildings := _normalize_buildings(raw.get("buildings", []))
	var building_count := buildings.size()
	var rails := _normalize_rails(raw.get("rails", []), building_count)
	var annotations := _normalize_annotations(raw.get("annotations", []), building_count)

	var out := {
		"format": FORMAT,
		"version": int(raw.get("version", CURRENT_VERSION)),
		"name": String(raw.get("name", "")),
		"description": String(raw.get("description", "")),
		"created_at_unix": float(raw.get("created_at_unix", 0.0)),
		"updated_at_unix": float(raw.get("updated_at_unix", 0.0)),
		"thumbnail_png_b64": String(raw.get("thumbnail_png_b64", "")),
		"buildings": buildings,
		"rails": rails,
		"annotations": annotations,
	}
	var bounds := compute_bounds(buildings)
	out["bounds"] = [bounds.x, bounds.y]
	return out


static func _normalize_buildings(raw_buildings) -> Array:
	var out: Array = []
	if not (raw_buildings is Array):
		return out
	for entry in raw_buildings:
		if not (entry is Dictionary):
			continue
		var id := String(entry.get("id", ""))
		var scene_path := String(entry.get("scene_path", ""))
		if id == "" and scene_path == "":
			continue
		out.append({
			"id": id,
			"scene_path": scene_path,
			"anchor_offset": _to_ivec_array(entry.get("anchor_offset", [0, 0])),
			"footprint": _to_footprint_array(entry.get("footprint", [1, 1])),
			"rotated_tick": posmod(int(entry.get("rotated_tick", 0)), 4),
			"is_alternate": bool(entry.get("is_alternate", false)),
			"selection_template": _normalize_selection_template(entry.get("selection_template", {})),
		})
	return out


static func _normalize_selection_template(raw) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for key in raw.keys():
		var sel = raw[key]
		if not (sel is Dictionary):
			continue
		out[String(key)] = {
			"selected": int(sel.get("selected", -1)),
			"metadata_path": String(sel.get("metadata_path", "")),
		}
	return out


static func _normalize_rails(raw_rails, building_count: int) -> Array:
	var out: Array = []
	if not (raw_rails is Array):
		return out
	for rail in raw_rails:
		if not (rail is Dictionary):
			continue
		var from_index := int(rail.get("from_index", -1))
		var to_index := int(rail.get("to_index", -1))
		# Drop rails whose endpoints no longer resolve to a captured building.
		if from_index < 0 or from_index >= building_count:
			continue
		if to_index < 0 or to_index >= building_count:
			continue
		out.append({
			"from_index": from_index,
			"from_port": String(rail.get("from_port", "")),
			"to_index": to_index,
			"to_port": String(rail.get("to_port", "")),
			"rail_version": int(rail.get("rail_version", 0)),
		})
	return out


static func _normalize_annotations(raw_annotations, building_count: int) -> Array:
	var out: Array = []
	if not (raw_annotations is Array):
		return out
	for ann in raw_annotations:
		if not (ann is Dictionary):
			continue
		var target_type := String(ann.get("target_type", TARGET_CELL))
		var target_index := int(ann.get("target_building_index", -1))
		if target_type == TARGET_BUILDING and (target_index < 0 or target_index >= building_count):
			# The building this annotation was pinned to is gone; re-anchor to
			# its cell so the note is not silently lost.
			target_type = TARGET_CELL
			target_index = -1
		out.append({
			"target_type": target_type,
			"anchor_offset": _to_ivec_array(ann.get("anchor_offset", [0, 0])),
			"target_building_index": target_index,
			"text": String(ann.get("text", "")),
			"format": String(ann.get("format", "bbcode")),
		})
	return out


# --- Bounds ------------------------------------------------------------------

# Footprint of the whole stamp in cells: the bounding box over every building's
# [anchor_offset, anchor_offset + footprint). Empty blueprint -> (0, 0).
static func compute_bounds(buildings: Array) -> Vector2i:
	if buildings.is_empty():
		return Vector2i.ZERO
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for b in buildings:
		var off := _ivec_from_array(b.get("anchor_offset", [0, 0]))
		var fp := _ivec_from_array(b.get("footprint", [1, 1]))
		min_x = min(min_x, off.x)
		min_y = min(min_y, off.y)
		max_x = max(max_x, off.x + max(1, fp.x))
		max_y = max(max_y, off.y + max(1, fp.y))
	return Vector2i(max_x - min_x, max_y - min_y)


# --- Annotation relinking (capture <-> stamp) --------------------------------

# Capture side: turn one serialized annotation (annotation_layer._serialize_
# annotation shape) into a blueprint annotation, made relative to `origin_cell`
# (the stamp's reference cell, i.e. the group's anchor cell). Building-anchored
# annotations resolve their uid to an index via `uid_to_index`; if the uid is
# not part of the captured group, the annotation falls back to a cell anchor.
static func annotation_to_blueprint(saved: Dictionary, origin_cell: Vector2i, uid_to_index: Dictionary) -> Dictionary:
	var anchor_cell := _ivec_from_array(saved.get("anchor_cell", [0, 0]))
	var target_type := String(saved.get("target_type", TARGET_CELL))
	var target_index := -1
	if target_type == TARGET_BUILDING:
		var uid := String(saved.get("target_building_uid", ""))
		if uid != "" and uid_to_index.has(uid):
			target_index = int(uid_to_index[uid])
		else:
			target_type = TARGET_CELL
	return {
		"target_type": target_type,
		"anchor_offset": [anchor_cell.x - origin_cell.x, anchor_cell.y - origin_cell.y],
		"target_building_index": target_index,
		"text": String(saved.get("text", "")),
		"format": String(saved.get("format", "bbcode")),
	}


# Stamp side: turn a blueprint annotation back into a serialized annotation
# ready for annotation_layer.load_annotations(). `place_origin_cell` is where
# this stamp is being dropped; `index_to_uid` maps captured building indices to
# the freshly-created buildings' uids. `new_id` is a unique id for this copy.
static func annotation_from_blueprint(bp_ann: Dictionary, place_origin_cell: Vector2i, index_to_uid: Dictionary, new_id: String, now_unix := -1.0) -> Dictionary:
	var ts := now_unix if now_unix >= 0.0 else float(Time.get_unix_time_from_system())
	var offset := _ivec_from_array(bp_ann.get("anchor_offset", [0, 0]))
	var anchor_cell := place_origin_cell + offset
	var target_type := String(bp_ann.get("target_type", TARGET_CELL))
	var target_uid := ""
	if target_type == TARGET_BUILDING:
		var idx := int(bp_ann.get("target_building_index", -1))
		if index_to_uid.has(idx):
			target_uid = String(index_to_uid[idx])
		else:
			target_type = TARGET_CELL
	return {
		"id": new_id,
		"target_type": target_type,
		"anchor_cell": [anchor_cell.x, anchor_cell.y],
		"target_building_uid": target_uid,
		"text": String(bp_ann.get("text", "")),
		"format": String(bp_ann.get("format", "bbcode")),
		"created_at_unix": ts,
		"updated_at_unix": ts,
	}


# --- Thumbnail ---------------------------------------------------------------

# Render a schematic footprint preview of the blueprint: one color-coded filled
# rectangle per building (colored by its category via the palette), on a
# transparent background, returned as a base64 PNG string ("" when empty).
#
# This is a CPU-side Image render (no scene instancing, no GPU, no await) so it
# is deterministic and headless-testable. The UI decodes it back to a texture.
static func render_thumbnail_b64(buildings: Array, max_px := THUMB_MAX_PX) -> String:
	if buildings.is_empty():
		return ""

	var min_cell := Vector2i(1 << 30, 1 << 30)
	var max_cell := Vector2i(-(1 << 30), -(1 << 30))
	for b in buildings:
		var off := _ivec_from_array(b.get("anchor_offset", [0, 0]))
		var fp := _ivec_from_array(b.get("footprint", [1, 1]))
		min_cell.x = min(min_cell.x, off.x)
		min_cell.y = min(min_cell.y, off.y)
		max_cell.x = max(max_cell.x, off.x + max(1, fp.x))
		max_cell.y = max(max_cell.y, off.y + max(1, fp.y))

	var span := max_cell - min_cell
	if span.x <= 0 or span.y <= 0:
		return ""

	var cell_px: int = clampi(int(floor(float(max_px) / float(max(span.x, span.y)))), THUMB_MIN_CELL_PX, THUMB_MAX_CELL_PX)
	var pad: int = max(2, int(cell_px / 2))
	var gap: int = 1 if cell_px >= 6 else 0

	var width := span.x * cell_px + pad * 2
	var height := span.y * cell_px + pad * 2
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for b in buildings:
		var off := _ivec_from_array(b.get("anchor_offset", [0, 0]))
		var fp := _ivec_from_array(b.get("footprint", [1, 1]))
		var color: Color = Palette.building_outline_color(StringName(b.get("id", "")))
		color.a = 0.92
		var rx: int = pad + (off.x - min_cell.x) * cell_px
		var ry: int = pad + (off.y - min_cell.y) * cell_px
		var rw: int = max(1, fp.x) * cell_px - gap
		var rh: int = max(1, fp.y) * cell_px - gap
		image.fill_rect(Rect2i(rx, ry, max(1, rw), max(1, rh)), color)

	return Marshalls.raw_to_base64(image.save_png_to_buffer())


# --- JSON (de)serialization + migration ---------------------------------------

static func to_json(bp: Dictionary) -> String:
	return JSON.stringify(normalize(bp), "\t")


# Parse a .srbpb file's text. Returns {} on parse failure or wrong format so
# callers can treat a bad/foreign file as "not a blueprint".
static func from_json(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	if String(parsed.get("format", "")) != FORMAT:
		return {}
	return normalize(migrate(parsed))


# Forward-compatible migration hook. Only v1 exists today; unknown/older
# versions are stamped to the current version after their fields are read.
static func migrate(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	var version := int(out.get("version", CURRENT_VERSION))
	# (no field migrations yet; future versions add cases here before this line)
	out["version"] = CURRENT_VERSION
	return out


static func counts(bp: Dictionary) -> Dictionary:
	return {
		"buildings": (bp.get("buildings", []) as Array).size(),
		"rails": (bp.get("rails", []) as Array).size(),
		"annotations": (bp.get("annotations", []) as Array).size(),
	}


# --- Small vector helpers ----------------------------------------------------

static func _ivec_from_array(value) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	return Vector2i.ZERO


static func _to_ivec_array(value) -> Array:
	var v := _ivec_from_array(value)
	return [v.x, v.y]


static func _to_footprint_array(value) -> Array:
	var v := _ivec_from_array(value)
	return [max(1, v.x), max(1, v.y)]
