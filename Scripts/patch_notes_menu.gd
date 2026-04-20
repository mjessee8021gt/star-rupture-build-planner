extends PopupPanel

@export var entry_scene: PackedScene

@onready var panel_container: PanelContainer = $PanelContainer
@onready var list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/List

func _ready() -> void:
	close_requested.connect(hide)
	apply_responsive_layout(size)
	
func refresh() -> void:
	apply_responsive_layout(size)
	_clear_list()
	
	var notes := _load_patchnote_resources()
	#Sort newest-first.
	notes.sort_custom(func(a: PatchNote, b: PatchNote) -> bool:
		return _version_is_newer(str(a.patch_version), str(b.patch_version)))
	
	for patchnote in notes:
		_add_entry(patchnote)
func _add_entry(patchNote: PatchNote) -> void:
	if entry_scene == null:
		push_warning("PatchNotesPanel: entry_scene is not set.")
		return
	var entry := entry_scene.instantiate() as Control
	if entry == null:
		push_warning("PatchNotesPanel: Failed to instantiate patch note entry scene.")
		return
	entry.custom_minimum_size = Vector2.ZERO
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(entry)
	
	var version_label := entry.get_node_or_null("MarginContainer/VBoxContainer/Version") as Label
	if version_label == null:
		push_warning("PatchNotesPanel: version_label is not set.")
		return
	version_label.text = "Version " + str(patchNote.patch_version)
	
	var notes_rtl := entry.get_node_or_null("MarginContainer/VBoxContainer/Notes") as RichTextLabel
	if notes_rtl == null:
		push_warning("PatchNotesPanel: notes_rtl is not set.")
		return
	notes_rtl.bbcode_enabled = false
	var unformatted_notes := patchNote.patch_notes
	var formatted_notes = unformatted_notes.replace("\\n", "\n")
	notes_rtl.text = "Patch Notes:\n" + (formatted_notes if formatted_notes != null else "")
	
	var issues_rtl := entry.get_node_or_null("MarginContainer/VBoxContainer/Issues") as RichTextLabel
	if issues_rtl == null:
		push_warning("PatchNotesPanel: issues_rtl is not set.")
		return
	issues_rtl.bbcode_enabled = false
	issues_rtl.text = "Known Issues:\n" + (patchNote.known_issues if patchNote.known_issues != null else "")
	
	entry.visible = true
	
func _clear_list() -> void:
	for child in list.get_children():
		child.queue_free()

func apply_responsive_layout(target_size: Vector2i = Vector2i.ZERO) -> void:
	var panel_size := target_size
	if panel_size == Vector2i.ZERO:
		panel_size = size
	if panel_size.x <= 0 or panel_size.y <= 0:
		return

	min_size = Vector2i.ZERO
	size = panel_size
	if panel_container != null:
		panel_container.custom_minimum_size = Vector2.ZERO
		panel_container.position = Vector2(4.0, 4.0)
		panel_container.size = Vector2(max(panel_size.x - 8, 1), max(panel_size.y - 8, 1))
	if list != null:
		list.custom_minimum_size = Vector2.ZERO
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _load_patchnote_resources() -> Array[PatchNote]:
	var out: Array[PatchNote] = []
	var root := get_tree().root
	var patch_registry := root.get_node_or_null("PatchRegistry")
	if patch_registry == null:
		patch_registry = root.get_node_or_null("PatchReg")
	if patch_registry == null:
		push_warning("PatchNotesPanel: Could not access PatchRegistry autoload singleton")
		return out
	
	var patch_map: Dictionary = patch_registry.PATCHES
	for key in patch_map.keys():
		var res = patch_map[key]
		if res is PatchNote:
			out.append(res)
		else:
			push_warning("PatchNotesPanel: Resource at %s is not a PatchNote Resource." % str(key))
	
	return out
	
func _version_is_newer(a: String, b: String) -> bool:
	var ka := _version_key(a)
	var kb := _version_key(b)

	var n = max(ka.size(), kb.size())
	for i in range(n):
		var ai := ka[i] if i < ka.size() else 0
		var bi := kb[i] if i < kb.size() else 0
		if ai != bi:
			return ai > bi # newer-first
	# identical
	return false

func _version_key(version: String) -> PackedInt32Array:
	var clean := version.strip_edges()

	# strip leading 'v'
	if clean.begins_with("v") or clean.begins_with("V"):
		clean = clean.substr(1)

	# keep only digits and dots at the front (handles "1.2.3-alpha" -> "1.2.3")
	var normalized := ""
	for ch in clean:
		if (ch >= "0" and ch <= "9") or ch == ".":
			normalized += ch
		else:
			break

	var parts := normalized.split(".", false)
	var key := PackedInt32Array()
	for p in parts:
		if p.is_empty():
			continue
		key.append(int(p))
	return key
	
