---
name: godot-tooltip-theming
description: Style Godot tooltips via a project custom theme, not a runtime root-window theme
metadata:
  type: reference
---

To restyle native Godot tooltips (`Control.tooltip_text` popups) globally in this project, use a **project custom theme**: `gui/theme/custom` in `project.godot` pointing to a `Theme` `.tres` that defines `TooltipPanel/styles/panel` (a `StyleBoxFlat`) and `TooltipLabel/colors/font_color`. This is `Resources/srbp_tooltip_theme.tres`.

**Why:** Setting `get_window().theme` (or `get_tree().root.theme`) at runtime does NOT propagate to tooltip popups — verified live (tooltips stayed the default semi-transparent panel). The project custom theme is the true global fallback for every Control, including tooltip popups, so it reliably reaches tooltips whose owning control is parented under a `Node2D` (like the chip `ColorRect`s and rail badges) with no Control theme ancestor.

The rest of the app styles controls programmatically via `Palette.make_*_style()`; tooltips are the exception because they are engine-native and need theme-based styling. Relates to [[srbp-project-overview]].
