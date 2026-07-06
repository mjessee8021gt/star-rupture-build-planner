---
name: gdscript-typed-assignment-inference
description: In this project, avoid := when the RHS is Variant/non-primitive; use plain =
metadata:
  type: feedback
---

When writing GDScript here, do NOT use `:=` (inferred typed assignment) when the right-hand side returns a `Variant` or a non-primitive type the inferencer can't resolve — most commonly `Dictionary.get(...)`, `Array` element access, or `Object.get(prop)`. Use a plain `var x = ...` instead (or an explicit `var x: Type = ...` when the concrete type is known and correct).

**Why:** This project promotes the "variable type is being inferred from a Variant value" warning to an error (warnings-as-errors). `:=` on a Variant RHS trips it and the whole script fails to parse — which cascades (e.g. `buildManager.gd` failing to load made `main.gd` error on `start_build`). Plain `=` declares the var without forcing inference, so no warning fires. The user reports this is a recurring mistake from both Codex 5.5 and Claude models.

**How to apply:** `:=` is fine for clearly-typed RHS (String/int/float literals, `Dictionary`/`Array` literals, typed constructors, functions with a declared non-Variant return). Reach for plain `=` the moment the RHS is `.get()`, subscript access, `OptionButton.get_item_metadata()`, or anything returning `Variant`. Relates to [[srbp-project-overview]].
