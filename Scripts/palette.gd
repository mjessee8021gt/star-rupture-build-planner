extends RefCounted

class_name PlannerPalette

const TEXT_PRIMARY := Color8(234, 239, 243, 255)
const TEXT_MUTED := Color8(188, 198, 208, 255)
const TEXT_BADGE := Color8(245, 247, 250, 255)

const SCENE_PANEL_FILL := Color8(24, 30, 38, 236)
const SCENE_PANEL_BORDER := Color8(86, 100, 118, 255)
const BUTTON_FILL := Color8(40, 49, 60, 242)
const BUTTON_HOVER := Color8(53, 65, 78, 248)
const BUTTON_PRESSED := Color8(31, 39, 49, 255)

const BUILDING_OUTLINE_WIDTH := 2.0
const BUILDING_OUTLINE_WIDTH_CRAFTING := 1.0

const BUILDING_OUTLINE_EXTRACTION := Color8(127, 200, 169, 255)
const BUILDING_OUTLINE_CRAFTING := Color8(242, 184, 128, 255)
const BUILDING_OUTLINE_PROCESSING := Color8(143, 170, 220, 255)
const BUILDING_OUTLINE_POWER := Color8(230, 208, 151, 255)

const EXTRACTION_BUILDING_IDS := [
	&"ore_excavator",
	&"ore_excavator_v2",
	&"helium_extractor",
	&"sulfur_extractor",
	&"oil_extractor",
	&"laser_drill",
]

const CRAFTING_BUILDING_IDS := [
	&"fabricator",
	&"fabricator_v2",
	&"assembler",
	&"constructorizer",
	&"constructorizer_v2",
	&"facturer",
]

const PROCESSING_BUILDING_IDS := [
	&"smelter",
	&"furnace",
	&"furnace_v2",
	&"mega_press",
	&"megapress",
	&"compounder",
	&"compounder_v2",
	&"pressurizer",
	&"refinery",
	&"pyro_forge",
]

const POWER_BUILDING_IDS := [
	&"solar_v1",
	&"solar_v2",
	&"wind_v1",
	&"wind_v2",
	&"chemical_generator",
]

const BADGE_INPUT_FILL := Color8(41, 90, 108, 220)
const BADGE_OUTPUT_FILL := Color8(126, 92, 35, 220)
const BADGE_NEUTRAL_FILL := Color8(75, 86, 100, 220)

const PORT_INPUT := Color8(86, 180, 233, 255)
const PORT_OUTPUT := Color8(230, 159, 0, 255)
const PORT_UNIVERSAL := Color8(148, 163, 184, 255)

const PATH_PREVIEW := Color(0.901961, 0.623529, 0.0, 0.65)
const PATH_FINAL := Color8(86, 180, 233, 255)

const BUILD_VALID := Color(0.337255, 0.705882, 0.823529, 0.58)
const BUILD_INVALID := Color(0.878431, 0.568627, 0.305882, 0.62)


static func with_alpha(color: Color, alpha: float) -> Color:
	var tinted := color
	tinted.a = alpha
	return tinted


static func port_color_for_name(port_name: String) -> Color:
	var name := port_name.to_lower()
	if name.begins_with("input"):
		return PORT_INPUT
	if name.begins_with("output"):
		return PORT_OUTPUT
	return PORT_UNIVERSAL


static func badge_fill_for_name(node_name: String) -> Color:
	var name := node_name.to_lower()
	if name.contains("input"):
		return BADGE_INPUT_FILL
	if name.contains("output"):
		return BADGE_OUTPUT_FILL
	return BADGE_NEUTRAL_FILL


static func make_panel_style(fill: Color, border: Color, radius: int = 10, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.14)
	style.shadow_size = 6
	return style


static func make_button_style(fill: Color, radius: int = 8, border_width: int = 1) -> StyleBoxFlat:
	return make_panel_style(fill, SCENE_PANEL_BORDER, radius, border_width)


static func building_outline_color(building_id: StringName) -> Color:
	if EXTRACTION_BUILDING_IDS.has(building_id):
		return BUILDING_OUTLINE_EXTRACTION
	if CRAFTING_BUILDING_IDS.has(building_id):
		return BUILDING_OUTLINE_CRAFTING
	if PROCESSING_BUILDING_IDS.has(building_id):
		return BUILDING_OUTLINE_PROCESSING
	if POWER_BUILDING_IDS.has(building_id):
		return BUILDING_OUTLINE_POWER
	return SCENE_PANEL_BORDER


static func building_outline_width(building_id: StringName) -> float:
	if CRAFTING_BUILDING_IDS.has(building_id):
		return BUILDING_OUTLINE_WIDTH_CRAFTING
	return BUILDING_OUTLINE_WIDTH
