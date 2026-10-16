extends "res://scripts/autoload/game_state.gd"
var fail_copy := false
var fail_replace := false
var delete_before_failure := false
var replace_called := false

func _copy_file(source: String, destination: String) -> Error:
	if fail_copy:
		return ERR_CANT_CREATE
	return super._copy_file(source, destination)

func _replace_file(source: String, destination: String) -> Error:
	replace_called = true
	if fail_replace:
		if delete_before_failure and FileAccess.file_exists(destination):
			var error := DirAccess.remove_absolute(destination)
			if error != OK:
				return error
		return FAILED
	return super._replace_file(source, destination)

