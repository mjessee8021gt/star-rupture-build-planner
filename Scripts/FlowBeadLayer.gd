extends Node2D
class_name FlowBeadLayer

# Draws the animated flow-simulation overlays that sit on top of the rails:
#   * directional "flow beads" travelling from producer to consumer, with speed and
#     spacing scaled by how heavily a rail is loaded, and
#   * pulsing highlights on rails that participate in a detected flow loop.
#
# Rails are supplied in this node's local space (the same space as PathManager), so
# it must be added as a child of PathManager at the origin with no extra transform.

const BEAD_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const BEAD_RADIUS := 3.0
const BEAD_MIN_SPACING := 24.0   # px between beads on a fully loaded rail
const BEAD_MAX_SPACING := 84.0   # px between beads on a lightly loaded rail
const BEAD_MIN_SPEED := 42.0     # px/sec at minimum intensity
const BEAD_MAX_SPEED := 150.0    # px/sec at full intensity
const INTENSITY_EPSILON := 0.001

const LOOP_COLOR := Color(0.85, 0.44, 0.86)   # magenta highlight for ambiguous loops
const LOOP_WIDTH := 7.0
const LOOP_PULSE_SPEED := 4.0
const LOOP_ALPHA_MIN := 0.28
const LOOP_ALPHA_MAX := 0.62

var _rails: Array = []        # each: {"points": PackedVector2Array, "intensity": float}
var _loop_rails: Array = []   # each: {"points": PackedVector2Array}
var _phase := 0.0
var _enabled := false
var _scale := 1.0


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	if not enabled:
		_phase = 0.0
	queue_redraw()


func set_scale_factor(scale_factor: float) -> void:
	_scale = maxf(scale_factor, 0.001)
	queue_redraw()


func set_rails(rails: Array) -> void:
	_rails = rails
	queue_redraw()


func set_loop_rails(loop_rails: Array) -> void:
	_loop_rails = loop_rails
	queue_redraw()


func _process(delta: float) -> void:
	if not _enabled or (_rails.is_empty() and _loop_rails.is_empty()):
		return
	_phase += delta
	queue_redraw()


func _draw() -> void:
	if not _enabled:
		return
	_draw_loop_highlights()
	var radius := BEAD_RADIUS * _scale
	for rail_variant in _rails:
		if not (rail_variant is Dictionary):
			continue
		_draw_rail_beads(rail_variant, radius)


func _draw_loop_highlights() -> void:
	if _loop_rails.is_empty():
		return
	var alpha := lerpf(LOOP_ALPHA_MIN, LOOP_ALPHA_MAX, 0.5 + 0.5 * sin(_phase * LOOP_PULSE_SPEED))
	var color := Color(LOOP_COLOR.r, LOOP_COLOR.g, LOOP_COLOR.b, alpha)
	var width := LOOP_WIDTH * _scale
	for rail_variant in _loop_rails:
		if not (rail_variant is Dictionary):
			continue
		var points: PackedVector2Array = rail_variant.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		draw_polyline(points, color, width, true)


func _draw_rail_beads(rail: Dictionary, radius: float) -> void:
	var intensity := clampf(float(rail.get("intensity", 0.0)), 0.0, 1.0)
	if intensity <= INTENSITY_EPSILON:
		return

	var points: PackedVector2Array = rail.get("points", PackedVector2Array())
	if points.size() < 2:
		return

	var total_length := _polyline_length(points)
	if total_length <= 1.0:
		return

	var spacing := lerpf(BEAD_MAX_SPACING, BEAD_MIN_SPACING, intensity) * _scale
	if spacing <= 1.0:
		return
	var speed := lerpf(BEAD_MIN_SPEED, BEAD_MAX_SPEED, intensity) * _scale
	var offset := fposmod(_phase * speed, spacing)

	var distance := offset
	while distance <= total_length:
		var point := _sample_point(points, distance)
		draw_circle(point, radius, BEAD_COLOR)
		distance += spacing


func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func _sample_point(points: PackedVector2Array, distance_along: float) -> Vector2:
	var remaining := distance_along
	for i in range(1, points.size()):
		var start: Vector2 = points[i - 1]
		var end: Vector2 = points[i]
		var segment_length := start.distance_to(end)
		if segment_length <= 0.0001:
			continue
		if remaining <= segment_length:
			return start.lerp(end, remaining / segment_length)
		remaining -= segment_length
	return points[points.size() - 1]
