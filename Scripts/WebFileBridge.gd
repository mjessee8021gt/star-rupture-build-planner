class_name WebFileBridge
extends RefCounted

# Centralizes the HTML5 (JavaScriptBridge) file I/O that was previously
# copy-pasted across save, load, and blueprint import in main.gd:
#   * download_bytes/download_text - push a generated file to the browser.
#   * pick_text_file               - open the browser file picker and read the
#                                    chosen file back as text.
#
# All entry points are safe no-ops off the web platform, so callers can invoke
# them unconditionally after an is_available() guard.

static func is_available() -> bool:
	return OS.has_feature("web") and JavaScriptBridge != null


static func download_bytes(bytes: PackedByteArray, file_name: String, mime: String) -> void:
	if is_available():
		JavaScriptBridge.download_buffer(bytes, file_name, mime)


static func download_text(text: String, file_name: String, mime := "application/json") -> void:
	download_bytes(text.to_utf8_buffer(), file_name, mime)


# --- Instance-based browser text-file picker ---------------------------------
# An instance holds the JS callbacks and <input> element alive across the async
# browser round-trip, so the owner must keep the instance referenced (e.g. a
# member field) until on_loaded/on_failed fires. Reusing an instance cancels
# any pick already in flight.
#
# on_loaded is called with the file's text (which may be empty). on_failed is
# called only on a genuine read error; a user cancelling the picker cleans up
# silently without invoking either callback.

var _input
var _reader
var _input_callback
var _read_callback
var _error_callback
var _on_loaded: Callable
var _on_failed: Callable


func pick_text_file(accept: String, on_loaded: Callable, on_failed := Callable()) -> bool:
	if not is_available():
		return false
	_cleanup()

	var document = JavaScriptBridge.get_interface("document")
	if document == null or document.body == null:
		push_warning("WebFileBridge: browser file picker is unavailable in this web build.")
		return false

	_on_loaded = on_loaded
	_on_failed = on_failed
	_input = document.createElement("input")
	if _input == null:
		push_warning("WebFileBridge: failed to create the browser file input.")
		return false

	_input.setAttribute("type", "file")
	_input.setAttribute("accept", accept)
	_input.setAttribute("style", "display:none")
	_input_callback = JavaScriptBridge.create_callback(_on_input_changed)
	_input.onchange = _input_callback
	document.body.appendChild(_input)
	_input.click()
	return true


func _on_input_changed(args: Array) -> void:
	if args.is_empty():
		_cleanup()
		return
	var event = args[0]
	if event == null or event.target == null or event.target.files == null or int(event.target.files.length) < 1:
		# User dismissed the picker without choosing a file: clean up silently.
		_cleanup()
		return

	_reader = JavaScriptBridge.create_object("FileReader")
	if _reader == null:
		_fail()
		return

	_read_callback = JavaScriptBridge.create_callback(_on_reader_loaded)
	_error_callback = JavaScriptBridge.create_callback(_on_reader_failed)
	_reader.onload = _read_callback
	_reader.onerror = _error_callback
	_reader.readAsText(event.target.files[0])


func _on_reader_loaded(args: Array) -> void:
	var raw_text := ""
	if not args.is_empty() and args[0] != null and args[0].target != null:
		raw_text = str(args[0].target.result)
	var loaded := _on_loaded
	_cleanup()
	if loaded.is_valid():
		loaded.call(raw_text)


func _on_reader_failed(_args: Array) -> void:
	_fail()


func _fail() -> void:
	var failed := _on_failed
	_cleanup()
	if failed.is_valid():
		failed.call()


func _cleanup() -> void:
	if _input != null and _input.parentNode != null:
		_input.parentNode.removeChild(_input)
	_input = null
	_reader = null
	_input_callback = null
	_read_callback = null
	_error_callback = null
	_on_loaded = Callable()
	_on_failed = Callable()
