extends RefCounted

class_name PlannerUiScale

enum Tier {
	SMALL,
	MEDIUM,
	LARGE,
}

const SMALL_SCALE := 1.0
const MEDIUM_SCALE := 1.3
const LARGE_SCALE := 1.6
const MEDIUM_SHORT_EDGE := 1300
const LARGE_SHORT_EDGE := 2000


static func tier_for_viewport(viewport_size: Vector2i) -> int:
	var short_edge = mini(viewport_size.x, viewport_size.y)
	if short_edge >= LARGE_SHORT_EDGE:
		return Tier.LARGE
	if short_edge >= MEDIUM_SHORT_EDGE:
		return Tier.MEDIUM
	return Tier.SMALL


static func scale_for_viewport(viewport_size: Vector2i) -> float:
	match tier_for_viewport(viewport_size):
		Tier.LARGE:
			return LARGE_SCALE
		Tier.MEDIUM:
			return MEDIUM_SCALE
	return SMALL_SCALE


static func scale_for_node(node: Node) -> float:
	if node == null or node.get_viewport() == null:
		return SMALL_SCALE
	return scale_for_viewport(node.get_viewport().size)


static func scaled(value: float, ui_scale: float) -> float:
	return round(value * ui_scale)


static func scaled_int(value: float, ui_scale: float) -> int:
	return maxi(1, int(round(value * ui_scale)))


static func scaled_vec2(value: Vector2, ui_scale: float) -> Vector2:
	return Vector2(scaled(value.x, ui_scale), scaled(value.y, ui_scale))


static func scaled_vec2i(value: Vector2i, ui_scale: float) -> Vector2i:
	return Vector2i(scaled_int(value.x, ui_scale), scaled_int(value.y, ui_scale))


static func font_size(base_size: int, ui_scale: float) -> int:
	return maxi(1, int(round(float(base_size) * ui_scale)))


static func is_small(ui_scale: float) -> bool:
	return is_equal_approx(ui_scale, SMALL_SCALE)


static func apply_font_size(target: Object, theme_name: StringName, base_size: int, ui_scale: float, preserve_small := false) -> void:
	if target == null:
		return
	if preserve_small and is_small(ui_scale):
		if target.has_method("remove_theme_font_size_override"):
			target.call("remove_theme_font_size_override", theme_name)
		return
	if target.has_method("add_theme_font_size_override"):
		target.call("add_theme_font_size_override", theme_name, font_size(base_size, ui_scale))
