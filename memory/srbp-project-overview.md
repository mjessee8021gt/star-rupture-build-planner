---
name: srbp-project-overview
description: StarRupture Build Planner — what it is, source of truth, current dev state
metadata:
  type: project
---

StarRupture Build Planner (SRBP) is a Godot 4.7 (GL Compatibility) desktop-first planner for laying out StarRupture factory/base builds: grid placement, rail routing, production totals, save/load (`.srbp`, SAVE_FORMAT_VERSION=4), PDF export, undo/redo (15-entry snapshot), flow simulation, Pathing 2.0, annotations, What-if analyzer/generator, accessibility scaling.

Source of truth for internal workings is the Obsidian dev wiki at `Wiki/`, entry point `Wiki/Codex Northstar.md`. The wiki was verified accurate against code on 2026-07-05 (save version, rail capacities 120/240/480, palette constants, autoloads all matched).

Ownership: `main.gd` (scene coordinator, 110K), `buildManager.gd` (placement/selection/alignment, 78K), `path_manager.gd` (rails, 86K). Simulation is layered: `FlowGraphBuilder` → `FlowSimulator` → `PathingIntelligence` → PathManager badges/tooltips. Keep these layers separate.

0.5 "The Simulation Update" is the active cycle. As of 2026-07-05 the working tree has uncommitted in-flight work: Pathing 2.0 (`Scripts/PathingIntelligence.gd` is untracked/new) plus the alignment backend in buildManager (+840 lines) — the wiki describes these as "first-pass done" but they are working-tree changes not yet committed. Since delivered (2026-07-06/07): alignment UI ingress, save comparison (Save Engine 2.0), eyedropper mirroring + rail-copy (`Wiki/Devlogs/V0.5.0 - Eyedropper Mirroring Feature Placement`). Still unbuilt: stamp/blueprint, visual layers, map overlay, mobile touch redesign.
