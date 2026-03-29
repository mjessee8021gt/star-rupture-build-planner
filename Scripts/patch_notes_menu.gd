extends PopupPanel

@export var entry_scene: PackedScene
@export var patch_notes: PatchRegistry

@onready var list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/List

func _ready() -> void:
	close_requested.connect(hide)
	
func refresh() -> void:
	_clear_list()
	
	var notes = patch_notes.patch_notes
	#Sort newest-first.
	notes.sort_custom(func(a: PatchNote, b: PatchNote) -> bool:
		return _version_is_newer(str(a.patch_version), str(b.patch_version)))
	
	for patchnote in notes:
		_add_entry(patchnote)
func _add_entry(patchNote: PatchNote) -> void:
	if entry_scene == null:
		print("PatchNotesPanel: entry_scene is not set.")
		return
	var entry := entry_scene.instantiate() as Control
	if entry == null:
		print("PatchNotesPanel: entry_scene is not set.")
		return
	list.add_child(entry)
	
	var version_label := entry.get_node_or_null("MarginContainer/VBoxContainer/Version") as Label
	if version_label == null:
		print("PatchNotesPanel: version_label is not set.")
		return
	version_label.text = "Version " + str(patchNote.patch_version)
	print(version_label.text)
	
	var notes_rtl := entry.get_node("MarginContainer/VBoxContainer/Notes") as RichTextLabel
	if notes_rtl == null:
		print("PatchNotesPanel: notes_rtl is not set.")
		return
	notes_rtl.bbcode_enabled = false
	var unformatted_notes := patchNote.patch_notes
	var formatted_notes = unformatted_notes.replace("\\n", "\n")
	notes_rtl.text = "Patch Notes:\n" + (formatted_notes if formatted_notes != null else "")
	print(notes_rtl.text)
	
	var issues_rtl := entry.get_node("MarginContainer/VBoxContainer/Issues") as RichTextLabel
	if issues_rtl == null:
		print("PatchNotesPanel: issues_rtl is not set.")
		return
	issues_rtl.bbcode_enabled = false
	issues_rtl.text = "Known Issues:\n" + (patchNote.known_issues if patchNote.known_issues != null else "")
	print(issues_rtl.text)
	
	entry.visible = true
	
func _clear_list() -> void:
	for child in list.get_children():
		child.queue_free()

func _load_patchnote_resources(dir_path: String) -> Array[PatchNote]:
	var out: Array[PatchNote] = []
	var normalized_dir := dir_path.trim_suffix("/")
	var directory := DirAccess.open(normalized_dir)
	if directory == null:
		print("PatchNotesPanel: Could not open directory: " + normalized_dir)
		return out
		
	var files := directory.get_files()
	if files.is_empty():
		print("PatchNotesPanel: No files found in directory: " + normalized_dir + ". If this happens in HTML5 exports, ensure patch note resources are included in export filters.")
		return out
	files.sort()
	for file_name in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
			
		var path := normalized_dir.path_join(file_name)
		var res := ResourceLoader.load(path)
		if res is PatchNote:
			out.append(res)
			print("output file appended")
		else:
			print("PatchNotesPanel: Resource at " + path + " is not a PatchNote Resource.")
	
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
	
