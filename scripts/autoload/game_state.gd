extends Node
## GameState — global save/load and story flags.
##
## Autoloaded as `GameState`. Holds the narrative flags set by dialogue
## choices and persists them to user://save.json so "Continue" works.

signal state_changed

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2
const TEMP_PATH := "user://save.json.tmp"
const BACKUP_PATH := "user://save.json.bak"

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
	if FileAccess.file_exists(SAVE_PATH):
		return true
	return not _read_snapshot(BACKUP_PATH).is_empty() or not _read_snapshot(TEMP_PATH).is_empty()


func save_game() -> bool:
	# Preserve the best existing snapshot before touching temp or primary. In
	# particular, temp may be the only recoverable save after a first-save crash.
	for path in [SAVE_PATH, BACKUP_PATH, TEMP_PATH]:
		if _read_snapshot(path).is_empty():
			continue
		if path != BACKUP_PATH:
			var previous := FileAccess.get_file_as_string(path)
			if _copy_file(path, BACKUP_PATH) != OK:
				return false
			if FileAccess.get_file_as_string(BACKUP_PATH) != previous or _read_snapshot(BACKUP_PATH).is_empty():
				return false
		break
	var payload := {
		"version": SAVE_VERSION,
		"scene": current_scene,
		"flags": flags,
		"journal": Journal.entries(),
	}
	if _decode_snapshot(payload).is_empty():
		return false
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
	# Windows may delete the destination before rename. Backup stays untouched.
	return _replace_file(TEMP_PATH, SAVE_PATH) == OK


# Small filesystem boundaries allow tests to reproduce Windows delete/rename gaps.
func _copy_file(source: String, destination: String) -> Error:
	return DirAccess.copy_absolute(source, destination)


func _replace_file(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source, destination)


func load_game() -> bool:
	var paths: Array[String] = [SAVE_PATH]
	# An existing but invalid primary remains an error, not silent rollback.
	if not FileAccess.file_exists(SAVE_PATH):
		paths = [BACKUP_PATH, TEMP_PATH]
	for path in paths:
		var snapshot := _read_snapshot(path)
		if snapshot.is_empty():
			continue
		if path != SAVE_PATH:
			push_warning("GameState: recovering save from %s." % path)
		if snapshot.journal_recovered:
			push_warning("GameState: malformed journal data; loading with an empty journal.")
		current_scene = snapshot.scene
		flags = snapshot.flags.duplicate(true)
		Journal.restore(snapshot.journal)
		state_changed.emit()
		return true
	return false


func _read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	return _decode_snapshot(JSON.parse_string(text))


func _decode_snapshot(parsed: Variant) -> Dictionary:
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	var version: Variant = data.get("version", 1)
	if not (version is int or version is float) or (version != 1 and version != SAVE_VERSION):
		return {}
	var scene: Variant = data.get("scene", "res://scenes/game.tscn")
	var loaded_flags: Variant = data.get("flags", {})
	var loaded_journal: Variant = data.get("journal", [])
	var journal_recovered := false
	if not scene is String or not scene.begins_with("res://scenes/"):
		return {}
	if not ResourceLoader.exists(scene, "PackedScene") or not loaded_flags is Dictionary:
		return {}
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
			journal_recovered = true
			loaded_journal = []
	return {"scene": scene, "flags": loaded_flags, "journal": loaded_journal,
		"journal_recovered": journal_recovered}


func delete_save() -> void:
	# Explicit deletion must not resurrect a recovery snapshot on Continue.
	for path in [SAVE_PATH, BACKUP_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
