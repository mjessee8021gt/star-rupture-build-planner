extends PopupPanel

const DEFAULT_PATCH_REGISTRY: PatchRegistry = preload("res://Patch Notes/Patch_Registry.tres")

@export var entry_scene: PackedScene
@export var patch_notes: PatchRegistry

@onready var list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/List

func _ready() -> void:
	close_requested.connect(hide)
	
func refresh() -> void:
	_clear_list()
	
	var notes := _get_sorted_notes()
	if notes.is_empty():
		return
	
	for note in notes:
		_add_entry(note)
	
func _get_sorted_notes() -> Array[PatchNote]:
	var notes := _read_registry_notes()
	notes.sort_custom(func(a: PatchNote, b: PatchNote) -> bool:
		return _version_is_newer(str(a.patch_version), str(b.patch_version)))
	return notes
	
func _read_registry_notes() -> Array[PatchNote]:
	var registry := _resolve_registry()
	if registry == null:
		print("PatchNotesPanel: Patch Registry is not available.")
		return[]
	return registry.get_patch_notes()
		
func _resolve_registry() -> PatchRegistry:
	if patch_notes != null:
		return patch_notes
		
	if DEFAULT_PATCH_REGISTRY != null:
		patch_notes = DEFAULT_PATCH_REGISTRY
		return patch_notes
		
	return null
	
func _add_entry(patch_note: PatchNote) -> void:
	if entry_scene == null:
		print("PatchNotesPanel: entry_scene is not set.")
		return
	var entry := entry_scene.instantiate() as Control
	if entry == null:
		print("PatchNotesPanel: entry_scene is not a control scene.")
		return
	list.add_child(entry)
	
	var version_label := entry.get_node_or_null("MarginContainer/VBoxContainer/Version") as Label
	if version_label == null:
		print("PatchNotesPanel: version_label is not set.")
		return
	version_label.text = "Version " + str(patch_note.patch_version)
	
	var notes_rtl := entry.get_node_or_null("MarginContainer/VBoxContainer/Notes") as RichTextLabel
	if notes_rtl == null:
		print("PatchNotesPanel: notes_rtl is not set.")
		return
	notes_rtl.bbcode_enabled = false
	var formatted_notes := patch_note.patch_notes.replace("\\n", "\n")
	notes_rtl.text = "Patch Notes:\n" + formatted_notes
	
	var issues_rtl := entry.get_node_or_null("MarginContainer/VBoxContainer/Issues") as RichTextLabel
	if issues_rtl == null:
		print("PatchNotesPanel: issues_rtl is not set.")
		return
	issues_rtl.bbcode_enabled = false
	
	entry.visible = true
	
func _clear_list() -> void:
	for child in list.get_children():
		child.queue_free()
	
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
	
