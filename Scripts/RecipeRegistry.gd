extends Node

const IGNORED_BUILDING_IDS := {
	&"dispatcher": true,
	&"receiver": true,
}

const BUILDING_DISPLAY_NAMES := {
	&"assembler": "Assembler",
	&"chemical_generator": "Chemical Generator",
	&"compounder": "Compounder",
	&"compounder_v2": "Compounder V2",
	&"constructorizer": "Constructorizer",
	&"constructorizer_v2": "Constructorizer V2",
	&"fabricator": "Fabricator",
	&"fabricator_v2": "Fabricator V2",
	&"facturer": "Facturer",
	&"furnace": "Furnace",
	&"furnace_v2": "Furnace V2",
	&"helium_extractor": "Helium Extractor",
	&"laser_drill": "Laser Drill",
	&"mega_press": "MegaPress",
	&"megapress": "MegaPress",
	&"oil_extractor": "Oil Extractor",
	&"orbital_launcher_v1": "Orbital Launcher",
	&"ore_excavator": "Excavator (impure)",
	&"ore_excavator_v2": "Excavator V2 (impure)",
	&"pressurizer": "Pressurizer",
	&"pyro_forge": "Pyro Forge",
	&"radial_rail_connect": "Radial Rail",
	&"refinery": "Refinery",
	&"rail_mod_3": "Rail Modulator 3",
	&"rail_mod_5": "Rail Modulator 5",
	&"smelter": "Smelter",
	&"sulfur_extractor": "Sulfur Extractor",
}

const ROOT_RECIPES := [
	preload("res://Recipes/Accumulator.tres"),
	preload("res://Recipes/Aerogel.tres"),
	preload("res://Recipes/Airlock.tres"),
	preload("res://Recipes/Anti-radiation_covers.tres"),
	preload("res://Recipes/Applicator.tres"),
	preload("res://Recipes/Basic_building_materials.tres"),
	preload("res://Recipes/Basic_fuel.tres"),
	preload("res://Recipes/Battery.tres"),
	preload("res://Recipes/Biofilament.tres"),
	preload("res://Recipes/Bioprinter.tres"),
	preload("res://Recipes/Calcite_sheet.tres"),
	preload("res://Recipes/Calcium_block.tres"),
	preload("res://Recipes/Calcium_powder.tres"),
	preload("res://Recipes/Calcium_powder_v2.tres"),
	preload("res://Recipes/Carbon_sonar.tres"),
	preload("res://Recipes/Ceramics.tres"),
	preload("res://Recipes/Ceramics_v2.tres"),
	preload("res://Recipes/Chemicals.tres"),
	preload("res://Recipes/Chemicals_v2.tres"),
	preload("res://Recipes/Condenser.tres"),
	preload("res://Recipes/Condenser_v2.tres"),
	preload("res://Recipes/Containment_vessel.tres"),
	preload("res://Recipes/Control_systems.tres"),
	preload("res://Recipes/Converter.tres"),
	preload("res://Recipes/Cyclotrone.tres"),
	preload("res://Recipes/Deuterium.tres"),
	preload("res://Recipes/Dome.tres"),
	preload("res://Recipes/Electromagnet.tres"),
	preload("res://Recipes/Electromagnetic_coil.tres"),
	preload("res://Recipes/Electronics.tres"),
	preload("res://Recipes/Epoxy.tres"),
	preload("res://Recipes/Explosive_charge.tres"),
	preload("res://Recipes/Generator.tres"),
	preload("res://Recipes/Geothite_ingot.tres"),
	preload("res://Recipes/Geothite_lattice.tres"),
	preload("res://Recipes/Geothite_ore.tres"),
	preload("res://Recipes/Geothite_powder.tres"),
	preload("res://Recipes/Glass.tres"),
	preload("res://Recipes/Glass_v2.tres"),
	preload("res://Recipes/Hardening_agent.tres"),
	preload("res://Recipes/Hardening_agent_v2.tres"),
	preload("res://Recipes/Harvest_crude_oil.tres"),
	preload("res://Recipes/Harvest_helium-3.tres"),
	preload("res://Recipes/harvest_sulpher.tres"),
	preload("res://Recipes/Heat_resistant_sheet.tres"),
	preload("res://Recipes/Heat_resistant_sheet_v2.tres"),
	preload("res://Recipes/Heat_shield.tres"),
	preload("res://Recipes/Heavy_ammo.tres"),
	preload("res://Recipes/Impeller.tres"),
	preload("res://Recipes/Inductor.tres"),
	preload("res://Recipes/Intermediate_building_materials.tres"),
	preload("res://Recipes/Ion Injector.tres"),
	preload("res://Recipes/Ion_bomb.tres"),
	preload("res://Recipes/ion_injector_v2.tres"),
	preload("res://Recipes/Ion_stabilizer.tres"),
	preload("res://Recipes/Ion_thruster.tres"),
	preload("res://Recipes/Laser_emitter.tres"),
	preload("res://Recipes/laser_emitter_v2.tres"),
	preload("res://Recipes/Lens.tres"),
	preload("res://Recipes/Liquid_helium.tres"),
	preload("res://Recipes/Liquid_helium_v2.tres"),
	preload("res://Recipes/Mars_habitat_base.tres"),
	preload("res://Recipes/mine_Calcium.tres"),
	preload("res://Recipes/mine_Calcium_v2.tres"),
	preload("res://Recipes/mine_Titanium.tres"),
	preload("res://Recipes/mine_Titanium_v2.tres"),
	preload("res://Recipes/mine_Wolfram.tres"),
	preload("res://Recipes/mine_Wolfram_v2.tres"),
	preload("res://Recipes/Missile_housing.tres"),
	preload("res://Recipes/Molecular_scalpel.tres"),
	preload("res://Recipes/Nano_fibre.tres"),
	preload("res://Recipes/Nanosyringe.tres"),
	preload("res://Recipes/Nozzle.tres"),
	preload("res://Recipes/Onboard_instruments.tres"),
	preload("res://Recipes/Organic_compound.tres"),
	preload("res://Recipes/Payload_stage.tres"),
	preload("res://Recipes/Pistol_ammo.tres"),
	preload("res://Recipes/Plasma_generator.tres"),
	preload("res://Recipes/Plastic.tres"),
	preload("res://Recipes/Plastic_dust.tres"),
	preload("res://Recipes/Powerium.tres"),
	preload("res://Recipes/pressure_tank.tres"),
	preload("res://Recipes/Pressurized_helium.tres"),
	preload("res://Recipes/Pressurized_helium_v2.tres"),
	preload("res://Recipes/Propulsion_stage.tres"),
	preload("res://Recipes/Pseudorubber_insulator.tres"),
	preload("res://Recipes/Pump.tres"),
	preload("res://Recipes/Quantum_tranquilizer.tres"),
	preload("res://Recipes/Refined_oil.tres"),
	preload("res://Recipes/Reinforced_frame.tres"),
	preload("res://Recipes/Reinforced_housing.tres"),
	preload("res://Recipes/Resonator.tres"),
	preload("res://Recipes/RNA_stabilizer.tres"),
	preload("res://Recipes/Rocket_engine.tres"),
	preload("res://Recipes/Rocket_fuel.tres"),
	preload("res://Recipes/Rotor.tres"),
	preload("res://Recipes/Rotor_v2.tres"),
	preload("res://Recipes/RTSC.tres"),
	preload("res://Recipes/RTSC_generator.tres"),
	preload("res://Recipes/Satelite_body.tres"),
	preload("res://Recipes/Scafolding.tres"),
	preload("res://Recipes/Scanner.tres"),
	preload("res://Recipes/Scanner_v2.tres"),
	preload("res://Recipes/Shotgun_ammo.tres"),
	preload("res://Recipes/Stabilizer.tres"),
	preload("res://Recipes/Standard_ammo.tres"),
	preload("res://Recipes/Stator.tres"),
	preload("res://Recipes/Stator_v2.tres"),
	preload("res://Recipes/Substance_FHS-135-493.tres"),
	preload("res://Recipes/Sulferic_acid_v2.tres"),
	preload("res://Recipes/Sulpheric_acid.tres"),
	preload("res://Recipes/Superconductor.tres"),
	preload("res://Recipes/Superconductor_v2.tres"),
	preload("res://Recipes/Supermagnet.tres"),
	preload("res://Recipes/Synthetic Silicon.tres"),
	preload("res://Recipes/Synthetic_dna.tres"),
	preload("res://Recipes/Synthetic_protein.tres"),
	preload("res://Recipes/Synthetic_resin.tres"),
	preload("res://Recipes/Synthetic_resin_v2.tres"),
	preload("res://Recipes/Titanium housing.tres"),
	preload("res://Recipes/Titanium_bar.tres"),
	preload("res://Recipes/Titanium_beam.tres"),
	preload("res://Recipes/Titanium_rod.tres"),
	preload("res://Recipes/Titanium_rod_v2.tres"),
	preload("res://Recipes/Titanium_sheet.tres"),
	preload("res://Recipes/Titanium_sheet_v2.tres"),
	preload("res://Recipes/Titanoferrite_ingot.tres"),
	preload("res://Recipes/Tracking_device.tres"),
	preload("res://Recipes/Tube.tres"),
	preload("res://Recipes/Tube_v2.tres"),
	preload("res://Recipes/Turbine.tres"),
	preload("res://Recipes/Uberfilament.tres"),
	preload("res://Recipes/Valve.tres"),
	preload("res://Recipes/Wolfram_bar.tres"),
	preload("res://Recipes/Wolfram_plate.tres"),
	preload("res://Recipes/Wolfram_plate_v2.tres"),
	preload("res://Recipes/Wolfram_powder.tres"),
	preload("res://Recipes/Wolfram_powder_v2.tres"),
	preload("res://Recipes/Wolfram_steel_ingot.tres"),
	preload("res://Recipes/Wolfram_wire.tres"),
	preload("res://Recipes/Wolfram_wire_v2.tres"),
]

var _root_recipes: Array[Recipe] = []
var _recipes_by_output_id: Dictionary = {}
var _recipe_building_ids: Dictionary = {}


func _ready() -> void:
	_root_recipes = _build_root_recipe_list()
	_build_recipe_indexes()


func get_root_recipes() -> Array[Recipe]:
	if _root_recipes.is_empty():
		_root_recipes = _build_root_recipe_list()
	return _root_recipes.duplicate()


func get_recipes_for_output_id(output_id: StringName) -> Array[Recipe]:
	if _recipes_by_output_id.is_empty():
		_build_recipe_indexes()

	var recipes: Array[Recipe] = []
	var indexed_recipes = _recipes_by_output_id.get(output_id, [])
	if indexed_recipes is Array:
		for indexed_recipe in indexed_recipes:
			var recipe := indexed_recipe as Recipe
			if recipe != null:
				recipes.append(recipe)
	return recipes


func get_best_recipe_for_output_id(output_id: StringName, enabled_v2_building_ids: Dictionary = {}) -> Recipe:
	var candidates := get_recipes_for_output_id(output_id)
	if candidates.is_empty():
		return null

	var enabled_v2_candidates: Array[Recipe] = []
	var normal_candidates: Array[Recipe] = []
	var fallback_candidates: Array[Recipe] = []
	for candidate in candidates:
		var building_id := get_recipe_building_id(candidate)
		if _is_v2_building_id(building_id):
			if bool(enabled_v2_building_ids.get(building_id, false)):
				enabled_v2_candidates.append(candidate)
		elif building_id != StringName(""):
			normal_candidates.append(candidate)
		else:
			fallback_candidates.append(candidate)

	if not enabled_v2_candidates.is_empty():
		return _get_highest_output_recipe(enabled_v2_candidates)
	if not normal_candidates.is_empty():
		return _get_highest_output_recipe(normal_candidates)
	return _get_highest_output_recipe(fallback_candidates)


func get_recipe_building_id(recipe: Recipe) -> StringName:
	if _recipe_building_ids.is_empty():
		_build_recipe_indexes()
	return _recipe_building_ids.get(_recipe_key(recipe), StringName(""))


func get_recipe_building_display_name(recipe: Recipe) -> String:
	return get_building_display_name(get_recipe_building_id(recipe))


func get_building_display_name(building_id: StringName) -> String:
	if building_id == StringName(""):
		return "Unknown"
	if BUILDING_DISPLAY_NAMES.has(building_id):
		return String(BUILDING_DISPLAY_NAMES[building_id])
	return String(building_id).replace("_", " ").capitalize()


func get_recipe_output_id(recipe: Recipe) -> StringName:
	if recipe == null or recipe.outputs.is_empty():
		return StringName("")
	return _get_stack_id(recipe.outputs[0])


func get_recipe_output_qty(recipe: Recipe) -> float:
	if recipe == null or recipe.outputs.is_empty() or recipe.outputs[0] == null:
		return 0.0
	return float(recipe.outputs[0].qty)


func _build_root_recipe_list() -> Array[Recipe]:
	var recipes: Array[Recipe] = []
	for resource in ROOT_RECIPES:
		var recipe := resource as Recipe
		if recipe != null:
			recipes.append(recipe)

	recipes.sort_custom(func(a: Recipe, b: Recipe) -> bool:
		return get_recipe_display_name(a, true).nocasecmp_to(get_recipe_display_name(b, true)) < 0
	)
	return recipes


func get_recipe_display_name(recipe: Recipe, include_variant_suffix := false) -> String:
	if recipe == null:
		return ""
	var suffix := ""
	if include_variant_suffix and _is_v2_recipe(recipe):
		suffix = " V2"
	if recipe.display_name.strip_edges() != "":
		return recipe.display_name + suffix
	if String(recipe.id).strip_edges() != "":
		return String(recipe.id) + suffix
	return recipe.resource_path.get_file().get_basename().replace("_", " ")


func _build_recipe_indexes() -> void:
	if _root_recipes.is_empty():
		_root_recipes = _build_root_recipe_list()

	_recipes_by_output_id.clear()
	_recipe_building_ids.clear()
	for recipe in _root_recipes:
		var output_id := get_recipe_output_id(recipe)
		if output_id == StringName(""):
			continue
		if not _recipes_by_output_id.has(output_id):
			_recipes_by_output_id[output_id] = []
		_recipes_by_output_id[output_id].append(recipe)

	_index_building_recipes()

	for output_id in _recipes_by_output_id.keys():
		var recipes: Array = _recipes_by_output_id[output_id]
		recipes.sort_custom(func(a: Recipe, b: Recipe) -> bool:
			return get_recipe_display_name(a, true).nocasecmp_to(get_recipe_display_name(b, true)) < 0
		)


func _index_building_recipes() -> void:
	for building_id in BuildRegistry.BUILDINGS.keys():
		if IGNORED_BUILDING_IDS.has(building_id):
			continue

		var scene := BuildRegistry.get_scene(building_id)
		if scene == null:
			continue

		var instance := scene.instantiate()
		if instance == null:
			continue

		var resolved_building_id := StringName(instance.get("id"))
		if resolved_building_id == StringName(""):
			resolved_building_id = building_id

		if not IGNORED_BUILDING_IDS.has(resolved_building_id):
			_index_building_recipe_list(instance.get("available_recipes"), resolved_building_id)
			_index_building_recipe(instance.get("recipe"), resolved_building_id)
		instance.free()


func _index_building_recipe_list(recipes, building_id: StringName) -> void:
	if not (recipes is Array):
		return
	for recipe in recipes:
		_index_building_recipe(recipe, building_id)


func _index_building_recipe(recipe, building_id: StringName) -> void:
	var typed_recipe := recipe as Recipe
	if typed_recipe == null:
		return

	var key := _recipe_key(typed_recipe)
	if key == "":
		return

	_recipe_building_ids[key] = building_id


func _get_stack_id(stack: ItemStack) -> StringName:
	if stack == null:
		return StringName("")
	if stack.id != StringName(""):
		return stack.id
	if stack.item != null:
		return stack.item.id
	return StringName("")


func _recipe_key(recipe: Recipe) -> String:
	if recipe == null:
		return ""
	if recipe.resource_path != "":
		return recipe.resource_path
	return str(recipe.get_instance_id())


func _is_v2_recipe(recipe: Recipe) -> bool:
	if recipe == null:
		return false
	return recipe.resource_path.get_file().get_basename().to_lower().ends_with("_v2")


func _is_v2_building_id(building_id: StringName) -> bool:
	return String(building_id).to_lower().ends_with("_v2")


func _get_highest_output_recipe(recipes: Array[Recipe]) -> Recipe:
	var best_recipe: Recipe = null
	var best_output := -INF
	for recipe in recipes:
		var output_qty := get_recipe_output_qty(recipe)
		if best_recipe == null or output_qty > best_output:
			best_recipe = recipe
			best_output = output_qty
	return best_recipe
