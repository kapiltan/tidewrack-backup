extends Node
## GameState — global save/load and story flags.
##
## Autoloaded as `GameState`. Holds the narrative flags set by dialogue
## choices and persists them to user://save.json so "Continue" works.

signal state_changed

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2
const TEMP_PATH := "user://save.json.tmp"

## Story flags set during play, e.g. {"trusted_edith": true}.
var flags: Dictionary = {}
## Path of the scene the player should resume into.
var current_scene: String = "res://scenes/game.tscn"


func set_flag(name: String, value: Variant) -> void:
	flags[name] = value
	state_changed.emit()


func get_flag(name: String, default: Variant = false) -> Variant:
	return flags.get(name, default)


func new_game() -> void:
	flags.clear()
	current_scene = "res://scenes/game.tscn"
	Journal.restore([])
	state_changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"scene": current_scene,
		"flags": flags,
		"journal": Journal.entries(),
	}
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: could not open save file for writing.")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	# Replace only after a complete write; a stale temp file is never loaded.
	return DirAccess.rename_absolute(TEMP_PATH, SAVE_PATH) == OK


func load_game() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("GameState: could not open save file for reading.")
		return false
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameState: save file is corrupt.")
		return false

	var data: Dictionary = parsed
	var version: Variant = data.get("version", 1)
	if not (version is int or version is float) or (version != 1 and version != SAVE_VERSION):
		return false
	var scene: Variant = data.get("scene", "res://scenes/game.tscn")
	var loaded_flags: Variant = data.get("flags", {})
	var loaded_journal: Variant = data.get("journal", [])
	if not scene is String or not scene.begins_with("res://scenes/"):
		return false
	if not ResourceLoader.exists(scene, "PackedScene") or not loaded_flags is Dictionary:
		return false
	# Version 1 never stored journal entries. Do not invent discoveries from flags.
	if version == 1:
		loaded_journal = []
	else:
		var valid_journal := data.has("journal") and loaded_journal is Array
		if valid_journal:
			for id in loaded_journal:
				if not id is String or id.strip_edges().is_empty():
					valid_journal = false
					break
		if not valid_journal:
			push_warning("GameState: malformed journal data; loading with an empty journal.")
			loaded_journal = []
	# Core state is valid; journal failures must not discard story progress.
	current_scene = scene
	flags = loaded_flags.duplicate(true)
	Journal.restore(loaded_journal)
	state_changed.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
