extends Node2D
class_name DebugLayerOverlay

# Single grid-space renderer for the stackable Visual Debug Layers system. One overlay
# draws every enabled diagnostic layer from a payload computed once in main.gd, rather
# than one Node2D per layer. It follows the FlowBeadLayer contract (set_enabled /
# set_scale_factor / queue_redraw) and, like FlowBeadLayer, is added as a child of
# PathManager at the origin so global scene coordinates convert cleanly via to_local.
#
# Every visible layer pairs color (reused from the Pathing 2.0 vocabulary) with a
# distinct shape/line-style channel so state never depends on hue alone.

const PathingIntel := preload("res://Scripts/PathingIntelligence.gd")

# Layer ids (must match main.gd DEBUG_LAYER_IDS values).
const LAYER_HEALTH := "health"
const LAYER_HEATMAP := "heatmap"
const LAYER_WASTE := "waste"
const LAYER_ORPHAN := "orphan"
const LAYER_TIERING := "tiering"
const LAYER_SATURATION := "saturation"

# Supply-health palette, reused from Pathing 2.0 so the grid overlay matches the chips.
const HEALTH_SUPPLIED := PathingIntel.COLOR_SUPPLIED
const HEALTH_UNDER := PathingIntel.COLOR_UNDER_SUPPLIED
const HEALTH_MISSING := PathingIntel.COLOR_MISSING
const HEALTH_DISCONNECTED := PathingIntel.COLOR_UNUSED

const WASTE_COLOR := Color8(150, 116, 60, 230)      # amber, "output going nowhere"
const ORPHAN_COLOR := Color8(120, 132, 150, 235)    # slate, "not hooked up"
const ORPHAN_PORT_COLOR := Color8(214, 138, 34, 240)

# Sequential heatmap ramp (cool -> hot). Blue->orange reads as a magnitude ramp across
# common color-vision types; magnitude is also reinforced by fill alpha and a value label.
const HEAT_COOL := Color8(58, 108, 138, 255)
const HEAT_HOT := Color8(214, 104, 58, 255)
const HEAT_ALPHA_MIN := 0.14
const HEAT_ALPHA_MAX := 0.58

# Production-stage ramp (raw -> final). Deliberately teal->violet, distinct from the
# heatmap ramp so the two "fill" layers never read as the same thing. Also labelled "T{n}".
const TIER_LOW := Color8(88, 168, 150, 255)
const TIER_HIGH := Color8(150, 112, 190, 255)
const TIER_BAND_HEIGHT := 7.0

# Rail saturation states. Reinforced by line thickness + an over-capacity marker so the
# spare/near/over reading does not rely on the green/amber/red hue axis alone.
const SATURATION_SPARE := Color8(90, 162, 122, 235)
const SATURATION_NEAR := Color8(214, 170, 60, 240)
const SATURATION_OVER := Color8(202, 82, 92, 245)

const RING_INSET := 3.0        # world px the ring sits outside the footprint
const RING_WIDTH := 3.0        # base ring width (scaled by _scale)
const HATCH_SPACING := 11.0    # base world px between hatch lines
const DASH_LENGTH := 9.0
const DASH_GAP := 6.0

var _enabled := false
var _opacity := 1.0
var _scale := 1.0
var _active: Dictionary = {}       # layer_id -> bool
var _payload: Dictionary = {}      # per-layer draw data (world coordinates)
var _label_font: Font = null


func _ready() -> void:
	_label_font = ThemeDB.fallback_font


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	queue_redraw()


func set_scale_factor(scale_factor: float) -> void:
	_scale = maxf(scale_factor, 0.001)
	queue_redraw()


func set_opacity(opacity: float) -> void:
	_opacity = clampf(opacity, 0.0, 1.0)
	queue_redraw()


func set_active_layers(active: Dictionary) -> void:
	_active = active.duplicate(true)
	queue_redraw()


func set_payload(payload: Dictionary) -> void:
	_payload = payload
	queue_redraw()


func is_layer_active(layer_id: String) -> bool:
	return bool(_active.get(layer_id, false))


func _draw() -> void:
	if not _enabled or _opacity <= 0.001:
		return
	# Rail-space fills first (under everything), then building fills, then diagnostic
	# marks, then health rings on top so the most safety-critical read wins.
	if is_layer_active(LAYER_SATURATION):
		_draw_saturation()
	if is_layer_active(LAYER_HEATMAP):
		_draw_heatmap()
	if is_layer_active(LAYER_TIERING):
		_draw_tiering()
	if is_layer_active(LAYER_WASTE):
		_draw_waste()
	if is_layer_active(LAYER_ORPHAN):
		_draw_orphan()
	if is_layer_active(LAYER_HEALTH):
		_draw_health()


# --- Supply-health halos ------------------------------------------------------

func _draw_health() -> void:
	var entries = _payload.get(LAYER_HEALTH, [])
	if not (entries is Array):
		return
	var width := RING_WIDTH * _scale
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var rect := _entry_rect(entry, RING_INSET)
		var state := String(entry.get("state", ""))
		match state:
			"supplied":
				_draw_ring(rect, _tint(HEALTH_SUPPLIED), width, false)
			"under":
				_draw_ring(rect, _tint(HEALTH_UNDER), width, false)
				_draw_hatch(rect, _tint(HEALTH_UNDER, 0.55), width, HATCH_SPACING * _scale)
			"missing":
				_draw_ring(rect, _tint(HEALTH_MISSING), width, false)
				_draw_hatch(rect, _tint(HEALTH_MISSING, 0.7), width, HATCH_SPACING * 0.6 * _scale)
			"disconnected":
				_draw_ring(rect, _tint(HEALTH_DISCONNECTED), width, true)


# --- Heat / power / cost heatmap ---------------------------------------------

func _draw_heatmap() -> void:
	var data = _payload.get(LAYER_HEATMAP, {})
	if not (data is Dictionary):
		return
	var entries = (data as Dictionary).get("entries", [])
	if not (entries is Array):
		return
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var t := clampf(float(entry.get("t", 0.0)), 0.0, 1.0)
		var rect := _entry_rect(entry, 0.0)
		var fill := HEAT_COOL.lerp(HEAT_HOT, t)
		fill.a = lerpf(HEAT_ALPHA_MIN, HEAT_ALPHA_MAX, t) * _opacity
		draw_rect(rect, fill, true)
		var value := float(entry.get("value", 0.0))
		if value > 0.0 and _label_font != null:
			var text := _format_value(value)
			var font_size := int(round(13.0 * _scale))
			var text_size := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var pos := rect.get_center() - text_size * 0.5 + Vector2(0, text_size.y * 0.5)
			draw_string(_label_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _tint(PlannerPaletteText(), 1.0))


# --- Production-stage tiering -------------------------------------------------

func _draw_tiering() -> void:
	var data = _payload.get(LAYER_TIERING, {})
	if not (data is Dictionary):
		return
	var entries = (data as Dictionary).get("entries", [])
	if not (entries is Array):
		return
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var rect := _entry_rect(entry, 0.0)
		var t := clampf(float(entry.get("t", 0.0)), 0.0, 1.0)
		var color := TIER_LOW.lerp(TIER_HIGH, t)
		# A band along the top edge of the footprint reads distinctly from the heatmap's
		# full fill even when both layers are on at once.
		var band_height := minf(rect.size.y, TIER_BAND_HEIGHT * _scale)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, band_height)), _tint(color, 0.92), true)
		if _label_font != null:
			var text := "T%d" % int(entry.get("tier", 0))
			var font_size := int(round(12.0 * _scale))
			var pos := rect.position + Vector2(3.0 * _scale, band_height + font_size)
			draw_string(_label_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _tint(color, 1.0))


# --- Rail saturation choropleth ----------------------------------------------

func _draw_saturation() -> void:
	var data = _payload.get(LAYER_SATURATION, {})
	if not (data is Dictionary):
		return
	for rail_variant in _as_array((data as Dictionary).get("rails", [])):
		if not (rail_variant is Dictionary):
			continue
		var points := _local_points(rail_variant.get("points", PackedVector2Array()))
		if points.size() < 2:
			continue
		var state := String(rail_variant.get("state", "spare"))
		var color := SATURATION_SPARE
		var width := 3.0 * _scale
		if state == "near":
			color = SATURATION_NEAR
			width = 4.5 * _scale
		elif state == "over":
			color = SATURATION_OVER
			width = 6.0 * _scale
		draw_polyline(points, _tint(color), width, true)
		if state == "over":
			# Redundant shape cue: a diamond at the rail midpoint marks over-capacity so
			# the alert does not depend on the red hue.
			_draw_diamond(points[int(points.size() / 2)], 6.0 * _scale, _tint(color))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var diamond := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
	])
	draw_colored_polygon(diamond, color)


# --- Overproduction / waste --------------------------------------------------

func _draw_waste() -> void:
	var data = _payload.get(LAYER_WASTE, {})
	if not (data is Dictionary):
		return
	var width := RING_WIDTH * _scale
	for entry_variant in _as_array((data as Dictionary).get("buildings", [])):
		if not (entry_variant is Dictionary):
			continue
		var rect := _entry_rect(entry_variant, RING_INSET)
		_draw_hatch(rect, _tint(WASTE_COLOR, 0.85), width, HATCH_SPACING * _scale)
		_draw_ring(rect, _tint(WASTE_COLOR), width, false)
	for rail_variant in _as_array((data as Dictionary).get("rails", [])):
		if not (rail_variant is Dictionary):
			continue
		var points := _local_points(rail_variant.get("points", PackedVector2Array()))
		if points.size() < 2:
			continue
		_draw_dashed_polyline(points, _tint(WASTE_COLOR), width, DASH_LENGTH * _scale, DASH_GAP * _scale)


# --- Connectivity / orphan ---------------------------------------------------

func _draw_orphan() -> void:
	var data = _payload.get(LAYER_ORPHAN, {})
	if not (data is Dictionary):
		return
	var width := RING_WIDTH * _scale
	for entry_variant in _as_array((data as Dictionary).get("buildings", [])):
		if not (entry_variant is Dictionary):
			continue
		var rect := _entry_rect(entry_variant, RING_INSET)
		_draw_ring(rect, _tint(ORPHAN_COLOR), width, true)
	for port_variant in _as_array((data as Dictionary).get("ports", [])):
		if not (port_variant is Dictionary):
			continue
		var pos_variant = port_variant.get("pos", null)
		if not (pos_variant is Vector2):
			continue
		var center := to_local(pos_variant)
		var radius := 6.0 * _scale
		draw_arc(center, radius, 0.0, TAU, 20, _tint(ORPHAN_PORT_COLOR), 2.0 * _scale, true)


# --- Drawing primitives -------------------------------------------------------

func _entry_rect(entry: Dictionary, inset: float) -> Rect2:
	# center/size arrive in world coordinates; convert center to overlay-local space
	# and grow the rect outward by `inset` world px so rings sit just outside the footprint.
	var center_world = entry.get("center", Vector2.ZERO)
	var size = entry.get("size", Vector2.ZERO)
	var center: Vector2 = to_local(center_world if center_world is Vector2 else Vector2.ZERO)
	var half: Vector2 = (size if size is Vector2 else Vector2.ZERO) * 0.5 + Vector2(inset, inset)
	return Rect2(center - half, half * 2.0)


func _draw_ring(rect: Rect2, color: Color, width: float, dashed: bool) -> void:
	if dashed:
		var tl := rect.position
		var tr := Vector2(rect.end.x, rect.position.y)
		var br := rect.end
		var bl := Vector2(rect.position.x, rect.end.y)
		_draw_dashed_line(tl, tr, color, width)
		_draw_dashed_line(tr, br, color, width)
		_draw_dashed_line(br, bl, color, width)
		_draw_dashed_line(bl, tl, color, width)
	else:
		draw_rect(rect, color, false, width)


func _draw_hatch(rect: Rect2, color: Color, width: float, spacing: float) -> void:
	if spacing < 1.0:
		return
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	# 45-degree lines of the form (x - y = c); clip each to the rect analytically.
	var c := x0 - y1
	var c_max := x1 - y0
	while c <= c_max:
		var lo := maxf(x0, c + y0)
		var hi := minf(x1, c + y1)
		if hi > lo:
			draw_line(Vector2(lo, lo - c), Vector2(hi, hi - c), color, width)
		c += spacing


func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	for i in range(1, points.size()):
		_draw_dashed_line(points[i - 1], points[i], color, width, dash, gap)


func _draw_dashed_line(a: Vector2, b: Vector2, color: Color, width: float, dash := DASH_LENGTH, gap := DASH_GAP) -> void:
	var seg := b - a
	var length := seg.length()
	if length <= 0.001:
		return
	var dir := seg / length
	var step := maxf(dash + gap, 1.0)
	var travelled := 0.0
	while travelled < length:
		var start := a + dir * travelled
		var end := a + dir * minf(travelled + dash, length)
		draw_line(start, end, color, width)
		travelled += step


func _local_points(points_variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not (points_variant is PackedVector2Array or points_variant is Array):
		return out
	for point in points_variant:
		if point is Vector2:
			out.append(to_local(point))
	return out


func _tint(color: Color, alpha_scale := 1.0) -> Color:
	var out := color
	out.a = clampf(color.a * alpha_scale, 0.0, 1.0) * _opacity
	return out


func _format_value(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _as_array(value) -> Array:
	return value if value is Array else []


static func PlannerPaletteText() -> Color:
	return PlannerPalette.TEXT_PRIMARY
