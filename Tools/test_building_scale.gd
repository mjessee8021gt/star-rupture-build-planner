extends SceneTree

# Headless check for accessibility scaling of building overlays.
# Part 1: overlay scales UNIFORMLY about the building origin.
# Part 2: scaling up then back DOWN returns to the exact design rects, even when
#         a control's actual size drifts between frames (as OptionButton/Label
#         auto-sizing does) — regression guard for the "dropdowns/badges don't
#         downscale" bug.

const FABRICATOR := "res://Buildings/Fabricator.tscn"
const OVERLAY := ["TitleLabel", "Recipe", "outputBox", "Input1Box", "Input2Box"]

var _failures: Array[String] = []
var _building: Node2D = null
var _step := 0
var _base := {}


func _initialize() -> void:
	var scene: PackedScene = load(FABRICATOR)
	_building = scene.instantiate()
	root.add_child(_building)


func _process(_delta: float) -> bool:
	if not _building.is_inside_tree():
		return false
	# One action per frame so between-frame relayout can occur.
	match _step:
		0:
			_building.call("set_ui_scale", 1.0)
			_base = _capture(_building)
		1:
			_building.call("set_ui_scale", 2.5)
			_check_uniform_scale(_base, _capture(_building), 2.5)
		2:
			# Simulate auto-size drift: a control reports a size we did not set.
			var opt: Control = _building.get_node("Recipe")
			opt.size += Vector2(9, 4)
			var badge: Control = _building.get_node("Input1Box")
			badge.size += Vector2(5, 5)
		3:
			_building.call("set_ui_scale", 1.0)
			_check_roundtrip(_base, _capture(_building))
		4:
			_finish()
			return true
	_step += 1
	return false


func _check_uniform_scale(base: Dictionary, scaled: Dictionary, scale: float) -> void:
	# Text controls may clamp a few px larger than the pure geometric scale so their
	# content still fits at the bigger font; allow that slack on the up-scale check.
	for name in base.keys():
		var b: Dictionary = base[name]
		var s: Dictionary = scaled[name]
		_expect_vec("%s center @%sx" % [name, scale], s["center"], (b["center"] as Vector2) * scale, 6.0)
		_expect_vec("%s size @%sx" % [name, scale], s["size"], (b["size"] as Vector2) * scale, 6.0)
	var title: Label = _building.get_node("TitleLabel")
	_expect_num("title font @%sx" % scale, float(title.label_settings.font_size), 25.0 * scale, 1.5)
	var shared: LabelSettings = load("res://Assets/std_bldg_label_settings.tres")
	_expect_num("shared LabelSettings untouched", float(shared.font_size), 25.0, 0.01)
	var sprite: Sprite2D = _building.get_node("PrimarySprite")
	_expect_vec("sprite scale", sprite.scale, Vector2.ONE)
	_expect_vec("sprite position", sprite.position, Vector2(-96, -96))


func _check_roundtrip(base: Dictionary, back: Dictionary) -> void:
	for name in base.keys():
		var b: Dictionary = base[name]
		var s: Dictionary = back[name]
		_expect_vec("%s center after down" % name, s["center"], b["center"])
		_expect_vec("%s size after down" % name, s["size"], b["size"])
	var title: Label = _building.get_node("TitleLabel")
	_expect_num("title font after down", float(title.label_settings.font_size), 25.0, 1.0)


func _capture(building: Node2D) -> Dictionary:
	var out := {}
	for name in OVERLAY:
		var c: Control = building.get_node_or_null(name)
		if c == null:
			continue
		out[name] = {"center": c.position + c.size * 0.5, "size": c.size}
	return out


func _expect_vec(label: String, got: Vector2, want: Vector2, tol := 1.5) -> void:
	if got.distance_to(want) > tol:
		_fail("%s: got %s want %s" % [label, got, want])


func _expect_num(label: String, got: float, want: float, tol := 1.0) -> void:
	if abs(got - want) > tol:
		_fail("%s: got %s want %s" % [label, got, want])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("Building scale smoke tests passed.")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
