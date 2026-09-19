extends Resource

class_name ItemStack

@export var item : ItemDefinition
@export var qty : float
@export var id: StringName


## Formats a quantity for display: whole numbers render without a decimal
## ("60", not "60.0"), fractional rates keep their decimals ("7.5", "11.25").
static func format_qty(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 2).rstrip("0").rstrip(".")
