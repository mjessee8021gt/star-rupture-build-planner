extends RefCounted

# Save Engine V2 - version store (pure data library, no scene dependencies).
#
# The store keeps a document's full version history *inside* the .srbp file as a
# base snapshot plus an ordered list of forward deltas. Any version is
# reconstructed by applying deltas 0..n on top of the base. A cap folds the
# oldest deltas back into the base so the file cannot grow without bound.
#
# Everything here operates on plain Dictionaries so it can be exercised
# headlessly (see Tools/test_save_versioning.gd). Callers convert between the
# engine's normalized form and main.gd's live save-state via normalize_state()
# and to_apply_state().
#
# Normalized state shape:
#   {
#     buildings:   [ {uid, id, position, ...}, ... ],   # matched by uid
#     paths:       [ {from_uid, to_uid, from_port, to_port, rail_version}, ... ],
#     annotations: [ {id, ...}, ... ],                  # matched by id
#     heat, power, cost_bbm, cost_ibm, cost_meteor_cores  # scalars
#   }

const DEFAULT_CAP := 50

# Fields the live save carries that must never register as a change (they are
# either view state or derivable), mirroring main.gd's _capture_history_state.
const VOLATILE_KEYS := ["saved_at_unix", "camera", "production_panel_visible", "occupied_cells", "version", "history"]
const SCALAR_KEYS := ["heat", "power", "cost_bbm", "cost_ibm", "cost_meteor_cores"]

const KIND_BASE := "base"
const KIND_MANUAL := "manual"
const KIND_AUTO := "auto"
const KIND_PRE_DESTRUCTIVE := "pre_destructive"
const KIND_RESTORE := "restore"


# --- Normalization -----------------------------------------------------------

static func normalize_state(raw: Dictionary) -> Dictionary:
	# Convert a live save-state (index-referenced paths, volatile view fields)
	# into the engine's canonical, order-independent form. Idempotent: passing
	# an already-normalized state back through returns an equivalent state.
	var buildings: Array = []
	var index_to_uid: Dictionary = {}
	var raw_buildings = raw.get("buildings", [])
	if raw_buildings is Array:
		for i in raw_buildings.size():
			var b = raw_buildings[i]
			if b is Dictionary:
				var copy: Dictionary = (b as Dictionary).duplicate(true)
				buildings.append(copy)
				index_to_uid[i] = String(copy.get("uid", ""))

	var paths: Array = []
	var raw_paths = raw.get("paths", [])
	if raw_paths is Array:
		for p in raw_paths:
			if not (p is Dictionary):
				continue
			var from_uid := ""
			var to_uid := ""
			if p.has("from_uid") or p.has("to_uid"):
				from_uid = String(p.get("from_uid", ""))
				to_uid = String(p.get("to_uid", ""))
			else:
				from_uid = String(index_to_uid.get(int(p.get("from_index", -1)), ""))
				to_uid = String(index_to_uid.get(int(p.get("to_index", -1)), ""))
			if from_uid == "" or to_uid == "":
				continue
			paths.append({
				"from_uid": from_uid,
				"to_uid": to_uid,
				"from_port": String(p.get("from_port", "")),
				"to_port": String(p.get("to_port", "")),
				"rail_version": int(p.get("rail_version", -1))
			})

	var annotations: Array = []
	var raw_ann = raw.get("annotations", [])
	if raw_ann is Array:
		for a in raw_ann:
			if a is Dictionary:
				annotations.append((a as Dictionary).duplicate(true))

	var out: Dictionary = {
		"buildings": buildings,
		"paths": paths,
		"annotations": annotations
	}
	for k in SCALAR_KEYS:
		out[k] = int(raw.get(k, 0))
	return out


static func to_apply_state(normalized: Dictionary) -> Dictionary:
	# Convert a normalized version back into the shape main.gd._apply_save_state
	# expects (paths re-indexed against the buildings array).
	var buildings: Array = []
	var uid_to_index: Dictionary = {}
	var nb = normalized.get("buildings", [])
	if nb is Array:
		for i in nb.size():
			var b = nb[i]
			if b is Dictionary:
				buildings.append((b as Dictionary).duplicate(true))
				uid_to_index[String((b as Dictionary).get("uid", ""))] = i

	var paths: Array = []
	var np = normalized.get("paths", [])
	if np is Array:
		for p in np:
			if not (p is Dictionary):
				continue
			var fi = uid_to_index.get(String(p.get("from_uid", "")), -1)
			var ti = uid_to_index.get(String(p.get("to_uid", "")), -1)
			if fi < 0 or ti < 0:
				continue
			paths.append({
				"from_index": fi,
				"to_index": ti,
				"from_port": String(p.get("from_port", "")),
				"to_port": String(p.get("to_port", "")),
				"rail_version": int(p.get("rail_version", -1))
			})

	var annotations: Array = []
	var na = normalized.get("annotations", [])
	if na is Array:
		annotations = (na as Array).duplicate(true)

	var out: Dictionary = {
		"buildings": buildings,
		"paths": paths,
		"annotations": annotations
	}
	for k in SCALAR_KEYS:
		if normalized.has(k):
			out[k] = int(normalized[k])
	return out


# --- Value comparison --------------------------------------------------------

static func values_equal(a, b) -> bool:
	# Numeric-aware deep equality. JSON round-trips turn ints into floats, so a
	# plain var_to_str compare would flag phantom changes after a load. Compare
	# numbers by value and recurse structurally.
	var a_num := a is int or a is float
	var b_num := b is int or b is float
	if a_num and b_num:
		return is_equal_approx(float(a), float(b))
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not values_equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k):
				return false
			if not values_equal(a[k], b[k]):
				return false
		return true
	return var_to_str(a) == var_to_str(b)


# --- Diff --------------------------------------------------------------------

static func diff_states(before: Dictionary, after: Dictionary) -> Dictionary:
	return {
		"buildings": _diff_keyed(before.get("buildings", []), after.get("buildings", []), "uid"),
		"annotations": _diff_keyed(before.get("annotations", []), after.get("annotations", []), "id"),
		"paths": _diff_paths(before.get("paths", []), after.get("paths", [])),
		"scalars": _diff_scalars(before, after)
	}


static func diff_is_empty(diff: Dictionary) -> bool:
	for group_key in ["buildings", "annotations"]:
		var g = diff.get(group_key, {})
		if not (g.get("added", {}) as Dictionary).is_empty():
			return false
		if not (g.get("removed", {}) as Dictionary).is_empty():
			return false
		if not (g.get("modified", {}) as Dictionary).is_empty():
			return false
	var p = diff.get("paths", {})
	if not (p.get("added", []) as Array).is_empty() \
			or not (p.get("removed", []) as Array).is_empty() \
			or not (p.get("modified", []) as Array).is_empty():
		return false
	return (diff.get("scalars", {}) as Dictionary).is_empty()


static func _index_by_key(items, key: String) -> Dictionary:
	var out: Dictionary = {}
	if items is Array:
		for it in items:
			if it is Dictionary:
				var id := String((it as Dictionary).get(key, ""))
				if id != "":
					out[id] = it
	return out


static func _diff_keyed(before, after, key: String) -> Dictionary:
	var b := _index_by_key(before, key)
	var a := _index_by_key(after, key)
	var added: Dictionary = {}
	var removed: Dictionary = {}
	var modified: Dictionary = {}
	for id in a:
		if not b.has(id):
			added[id] = a[id]
		else:
			var fields := _field_diff(b[id], a[id])
			if not fields.is_empty():
				modified[id] = {"fields": fields, "before": b[id], "after": a[id]}
	for id in b:
		if not a.has(id):
			removed[id] = b[id]
	return {"added": added, "removed": removed, "modified": modified}


static func _field_diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Dictionary = {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	for k in keys:
		var av = a.get(k, null)
		var bv = b.get(k, null)
		if not values_equal(av, bv):
			out[k] = [av, bv]
	return out


static func _path_signature(p: Dictionary) -> String:
	return "%s|%s|%s|%s" % [
		String(p.get("from_uid", "")),
		String(p.get("to_uid", "")),
		String(p.get("from_port", "")),
		String(p.get("to_port", ""))
	]


static func _diff_paths(before, after) -> Dictionary:
	var b: Dictionary = {}
	var a: Dictionary = {}
	if before is Array:
		for p in before:
			if p is Dictionary:
				b[_path_signature(p)] = p
	if after is Array:
		for p in after:
			if p is Dictionary:
				a[_path_signature(p)] = p
	var added: Array = []
	var removed: Array = []
	var modified: Array = []
	for sig in a:
		if not b.has(sig):
			added.append(a[sig])
		elif not values_equal(b[sig], a[sig]):
			modified.append({"before": b[sig], "after": a[sig]})
	for sig in b:
		if not a.has(sig):
			removed.append(b[sig])
	return {"added": added, "removed": removed, "modified": modified}


static func _diff_scalars(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in SCALAR_KEYS:
		var ov := int(before.get(k, 0))
		var nv := int(after.get(k, 0))
		if ov != nv:
			out[k] = [ov, nv]
	return out


# --- Delta (forward) ---------------------------------------------------------

static func make_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var diff := diff_states(before, after)
	var ops: Dictionary = {}

	var bops := _keyed_delta(diff.get("buildings", {}))
	if not bops.is_empty():
		ops["buildings"] = bops
	var aops := _keyed_delta(diff.get("annotations", {}))
	if not aops.is_empty():
		ops["annotations"] = aops

	var p = diff.get("paths", {})
	if not (p.get("added", []) as Array).is_empty() \
			or not (p.get("removed", []) as Array).is_empty() \
			or not (p.get("modified", []) as Array).is_empty():
		# Paths are small and positionally coupled; store the full new set.
		var after_paths = after.get("paths", [])
		ops["paths"] = {"set": (after_paths as Array).duplicate(true) if after_paths is Array else []}

	var scalars = diff.get("scalars", {})
	if not (scalars as Dictionary).is_empty():
		var sc: Dictionary = {}
		for k in scalars:
			sc[k] = scalars[k][1]
		ops["scalars"] = sc

	return ops


static func _keyed_delta(group: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var added = group.get("added", {})
	if added is Dictionary and not added.is_empty():
		out["added"] = added
	var removed = group.get("removed", {})
	if removed is Dictionary and not removed.is_empty():
		out["removed"] = (removed as Dictionary).keys()
	var modified = group.get("modified", {})
	if modified is Dictionary and not modified.is_empty():
		var changed: Dictionary = {}
		for id in modified:
			changed[id] = modified[id]["after"]
		out["changed"] = changed
	return out


static func apply_delta(state: Dictionary, ops: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	if ops.has("buildings"):
		out["buildings"] = _apply_keyed(out.get("buildings", []), ops["buildings"], "uid")
	if ops.has("annotations"):
		out["annotations"] = _apply_keyed(out.get("annotations", []), ops["annotations"], "id")
	if ops.has("paths"):
		var set_paths = ops["paths"].get("set", [])
		out["paths"] = (set_paths as Array).duplicate(true) if set_paths is Array else []
	if ops.has("scalars"):
		for k in ops["scalars"]:
			out[k] = ops["scalars"][k]
	return out


static func _apply_keyed(items, group: Dictionary, key: String) -> Array:
	var removed: Dictionary = {}
	for id in group.get("removed", []):
		removed[String(id)] = true
	var changed = group.get("changed", {})
	var result: Array = []
	if items is Array:
		for it in items:
			if not (it is Dictionary):
				continue
			var id := String((it as Dictionary).get(key, ""))
			if removed.has(id):
				continue
			if changed is Dictionary and changed.has(id):
				result.append((changed[id] as Dictionary).duplicate(true))
			else:
				result.append((it as Dictionary).duplicate(true))
	var added = group.get("added", {})
	if added is Dictionary:
		var ids: Array = added.keys()
		ids.sort()
		for id in ids:
			result.append((added[id] as Dictionary).duplicate(true))
	return result


# --- History container -------------------------------------------------------

static func new_history(base_state: Dictionary, label: String, unix: float, cap := DEFAULT_CAP) -> Dictionary:
	return {
		"base": normalize_state(base_state),
		"base_meta": {"version_id": 1, "created_unix": unix, "label": label, "kind": KIND_BASE},
		"deltas": [],
		"head_version_id": 1,
		"next_version_id": 2,
		"cap": cap
	}


static func append_version(history: Dictionary, new_state: Dictionary, label: String, kind: String, unix: float) -> Dictionary:
	# Returns { history, added: bool, version_id }. No-op (added=false) when the
	# new state is identical to the current head.
	var norm := normalize_state(new_state)
	var head := reconstruct(history.get("base", {}), history.get("deltas", []))
	var ops := make_delta(head, norm)
	if ops.is_empty():
		return {"history": history, "added": false, "version_id": int(history.get("head_version_id", 1))}

	var vid := int(history.get("next_version_id", 2))
	var deltas: Array = (history.get("deltas", []) as Array).duplicate()
	deltas.append({"version_id": vid, "created_unix": unix, "label": label, "kind": kind, "ops": ops})

	var new_hist := history.duplicate()
	new_hist["deltas"] = deltas
	new_hist["head_version_id"] = vid
	new_hist["next_version_id"] = vid + 1
	new_hist = _prune(new_hist)
	return {"history": new_hist, "added": true, "version_id": vid}


static func _prune(history: Dictionary) -> Dictionary:
	var cap := int(history.get("cap", DEFAULT_CAP))
	if cap < 1:
		cap = 1
	var deltas: Array = (history.get("deltas", []) as Array).duplicate()
	var base: Dictionary = (history.get("base", {}) as Dictionary).duplicate(true)
	var base_meta: Dictionary = (history.get("base_meta", {}) as Dictionary).duplicate(true)
	while deltas.size() + 1 > cap and deltas.size() > 0:
		var oldest = deltas.pop_front()
		base = apply_delta(base, oldest.get("ops", {}))
		base_meta = {
			"version_id": oldest.get("version_id", base_meta.get("version_id", 1)),
			"created_unix": oldest.get("created_unix", 0.0),
			"label": oldest.get("label", ""),
			"kind": KIND_BASE
		}
	var out := history.duplicate()
	out["deltas"] = deltas
	out["base"] = base
	out["base_meta"] = base_meta
	return out


static func reconstruct(base: Dictionary, deltas: Array, up_to := -1) -> Dictionary:
	# up_to is a delta index (inclusive). -1 => apply all deltas (the head).
	var state := base.duplicate(true)
	var count := deltas.size()
	if up_to >= 0:
		count = min(up_to + 1, deltas.size())
	for i in count:
		state = apply_delta(state, deltas[i].get("ops", {}))
	return state


static func list_versions(history: Dictionary) -> Array:
	# Oldest -> newest, each { version_id, created_unix, label, kind, is_head }.
	var head_id := int(history.get("head_version_id", 1))
	var out: Array = []
	var base_meta: Dictionary = history.get("base_meta", {})
	out.append({
		"version_id": int(base_meta.get("version_id", 1)),
		"created_unix": float(base_meta.get("created_unix", 0.0)),
		"label": String(base_meta.get("label", "")),
		"kind": String(base_meta.get("kind", KIND_BASE)),
		"is_head": int(base_meta.get("version_id", 1)) == head_id
	})
	for d in history.get("deltas", []):
		out.append({
			"version_id": int(d.get("version_id", 0)),
			"created_unix": float(d.get("created_unix", 0.0)),
			"label": String(d.get("label", "")),
			"kind": String(d.get("kind", KIND_AUTO)),
			"is_head": int(d.get("version_id", 0)) == head_id
		})
	return out


static func state_at(history: Dictionary, version_id: int) -> Dictionary:
	var base_meta: Dictionary = history.get("base_meta", {})
	var base: Dictionary = history.get("base", {})
	var deltas: Array = history.get("deltas", [])
	if int(base_meta.get("version_id", 1)) == version_id:
		return base.duplicate(true)
	for j in deltas.size():
		if int(deltas[j].get("version_id", -1)) == version_id:
			return reconstruct(base, deltas, j)
	return {}


static func has_version(history: Dictionary, version_id: int) -> bool:
	return not state_at(history, version_id).is_empty() \
		or int(history.get("base_meta", {}).get("version_id", 1)) == version_id


static func diff_versions(history: Dictionary, from_version_id: int, to_version_id: int) -> Dictionary:
	return diff_states(state_at(history, from_version_id), state_at(history, to_version_id))
