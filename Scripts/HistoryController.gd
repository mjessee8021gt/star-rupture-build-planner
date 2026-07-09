class_name HistoryController
extends RefCounted

# Owns the undo/redo stacks and replay bookkeeping that used to live inline in
# main.gd. Scene-specific work (capturing the plan, rebuilding it on replay,
# and the pre-destructive version checkpoint) is injected as callables so this
# controller stays free of scene/UI dependencies and is unit-testable.
#
#   capture_state()             -> Dictionary   snapshot of the current plan
#   apply_state(Dictionary)     -> void         rebuild the plan from a snapshot
#   on_pre_destructive(label, before_state)     optional checkpoint hook, called
#                                               on every commit (cheap); the
#                                               hook itself decides whether to
#                                               act and must copy what it keeps.

const HISTORY_LIMIT := 15

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _is_replaying := false

var _capture_state: Callable
var _apply_state: Callable
var _on_pre_destructive: Callable


func setup(capture_state: Callable, apply_state: Callable, on_pre_destructive := Callable()) -> void:
	_capture_state = capture_state
	_apply_state = apply_state
	_on_pre_destructive = on_pre_destructive


func is_replaying() -> bool:
	return _is_replaying


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()


func capture() -> Dictionary:
	if _capture_state.is_valid():
		var state = _capture_state.call()
		if state is Dictionary:
			return state
	return {}


func commit(label: String, before_state: Dictionary) -> void:
	if _is_replaying or before_state.is_empty():
		return

	var after_state := capture()
	if _states_equal(before_state, after_state):
		return

	# Both snapshots are already independent pure-data dicts, and the apply path
	# duplicates before restoring, so they can be stored directly without a
	# further deep copy.
	_undo_stack.append({
		"label": label,
		"before": before_state,
		"after": after_state,
	})
	while _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()

	if _on_pre_destructive.is_valid():
		_on_pre_destructive.call(label, before_state)


func undo() -> void:
	if _undo_stack.is_empty():
		return

	var entry: Dictionary = _undo_stack.pop_back()
	var before_state = entry.get("before", {})
	if not (before_state is Dictionary):
		return

	_replay(before_state)
	_redo_stack.append(entry)


func redo() -> void:
	if _redo_stack.is_empty():
		return

	var entry: Dictionary = _redo_stack.pop_back()
	var after_state = entry.get("after", {})
	if not (after_state is Dictionary):
		return

	_replay(after_state)
	_undo_stack.append(entry)


func _replay(state: Dictionary) -> void:
	_is_replaying = true
	if _apply_state.is_valid():
		_apply_state.call(state)
	_is_replaying = false


static func _states_equal(first: Dictionary, second: Dictionary) -> bool:
	# Fast path: differing hashes mean the states differ - the common case,
	# since almost every committed action changes the plan. Only fall back to
	# the exact (but costly) deep compare on a hash match, which guards against
	# the astronomically rare hash collision.
	if first.hash() != second.hash():
		return false
	return var_to_str(first) == var_to_str(second)
