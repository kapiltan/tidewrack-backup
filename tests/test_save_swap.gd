extends SceneTree
## Uses disposable user data. Faults model Windows' delete-then-rename behavior.
var failures := 0
var journal: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func write_fixture(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func seed_checkpoint(state: Node, id: String) -> void:
	state.new_game()
	state.flags = {"checkpoint": id, "trusted_edith": false}
	journal.discover(id)

func expect_checkpoint(state: Node, id: String, label: String) -> void:
	check(state.flags == {"checkpoint": id, "trusted_edith": false}, label + " flags")
	check(journal.entries() == [id], label + " journal")
	check(state.current_scene == "res://scenes/game.tscn", label + " scene")

func _run() -> void:
	journal = root.get_node("Journal")
	var fault_script = load("res://tests/helpers/fault_game_state.gd")
	var state = fault_script.new()
	root.add_child(state)
	state.delete_save()
	seed_checkpoint(state, "previous")
	check(state.save_game(), "initial save")
	var previous := FileAccess.get_file_as_string(state.SAVE_PATH)

	# Refuse replacement if a recoverable backup cannot be established.
	seed_checkpoint(state, "new")
	state.fail_copy = true
	state.replace_called = false
	check(not state.save_game() and not state.replace_called, "backup failure aborts before replacement")
	check(FileAccess.get_file_as_string(state.SAVE_PATH) == previous, "backup failure preserves primary")
	state.fail_copy = false

	# Failure before Windows deletes destination: primary still wins over temp.
	state.fail_replace = true
	check(not state.save_game(), "failure before delete reports false")
	check(FileAccess.get_file_as_string(state.SAVE_PATH) == previous, "before-delete failure keeps primary")
	check(state.load_game(), "primary loads despite newer temp")
	expect_checkpoint(state, "previous", "primary priority")

	# Delete succeeds but rename fails: no primary, backup and complete temp survive.
	seed_checkpoint(state, "new")
	state.delete_before_failure = true
	check(not state.save_game(), "delete/rename gap reports false")
	check(not FileAccess.file_exists(state.SAVE_PATH), "fault removed primary")
	check(FileAccess.get_file_as_string(state.BACKUP_PATH) == previous, "previous save retained byte for byte")
	check(FileAccess.file_exists(state.TEMP_PATH), "new temp retained")
	var backup_bytes := FileAccess.get_file_as_string(state.BACKUP_PATH)
	var temp_bytes := FileAccess.get_file_as_string(state.TEMP_PATH)

	# Fresh instance models losing all GameState memory across a process restart.
	var restarted = fault_script.new()
	root.add_child(restarted)
	journal.restore([])
	check(restarted.has_save(), "Continue available with backup")
	check(restarted.load_game(), "fresh instance recovers backup")
	expect_checkpoint(restarted, "previous", "backup preferred to temp")
	check(FileAccess.get_file_as_string(state.BACKUP_PATH) == backup_bytes and FileAccess.get_file_as_string(state.TEMP_PATH) == temp_bytes, "load does not alter recovery files")

	# An invalid backup must not prevent loading a valid temp.
	write_fixture(state.BACKUP_PATH, "{truncated")
	check(restarted.has_save() and restarted.load_game(), "valid temp after invalid backup")
	expect_checkpoint(restarted, "new", "temp recovery")

	# Temp-only recovery must survive another failed save (before temp is truncated).
	DirAccess.remove_absolute(state.BACKUP_PATH)
	seed_checkpoint(restarted, "retry")
	restarted.fail_replace = true
	restarted.delete_before_failure = true
	check(not restarted.save_game(), "temp-only retry fails safely")
	check(restarted.load_game(), "retry retains previous temp as backup")
	expect_checkpoint(restarted, "new", "temp-only retry backup")

	# Both recovery candidates invalid: reject without altering live state.
	write_fixture(state.BACKUP_PATH, JSON.stringify({"version": 2, "flags": [], "journal": []}))
	write_fixture(state.TEMP_PATH, JSON.stringify({"version": 2, "scene": "res://scenes/missing.tscn", "journal": []}))
	check(not restarted.has_save() and not restarted.load_game(), "invalid recovery files rejected")
	expect_checkpoint(restarted, "new", "invalid fallback leaves live state")

	# A failed first save has no backup, but its complete temp is recoverable.
	restarted.delete_save()
	seed_checkpoint(restarted, "first")
	check(not restarted.save_game(), "first-save replacement failure")
	check(not FileAccess.file_exists(state.BACKUP_PATH), "no invented first-save backup")
	check(restarted.has_save() and restarted.load_game(), "first-save temp is available to Continue")
	expect_checkpoint(restarted, "first", "first-save recovery")
	var first_temp := FileAccess.get_file_as_string(state.TEMP_PATH)
	restarted.fail_copy = true
	seed_checkpoint(restarted, "retry")
	check(not restarted.save_game(), "temp-only backup failure aborts")
	check(FileAccess.get_file_as_string(state.TEMP_PATH) == first_temp, "only recoverable temp is not truncated")
	restarted.fail_copy = false

	# Successful replacement retains prior primary as backup.
	restarted.delete_save()
	restarted.fail_replace = false
	seed_checkpoint(restarted, "previous")
	check(restarted.save_game(), "save after cleanup")
	seed_checkpoint(restarted, "new")
	check(restarted.save_game() and restarted.load_game(), "normal replacement")
	expect_checkpoint(restarted, "new", "new primary")
	DirAccess.remove_absolute(state.SAVE_PATH)
	check(restarted.load_game(), "backup retained after successful replacement")
	expect_checkpoint(restarted, "previous", "previous checkpoint backup")
	restarted.delete_save()
	check(not restarted.has_save() and not restarted.load_game(), "explicit deletion clears recovery candidates")
	state.queue_free()
	restarted.queue_free()
	print("Save swap failures: ", failures)
	quit(1 if failures else 0)
