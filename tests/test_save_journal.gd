extends SceneTree
## Run with isolated XDG_DATA_HOME; never touches a player's real save.
var failures := 0
var discoveries := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func write_save(value: Variant) -> void:
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(value))
	f.close()

func _run() -> void:
	var state = root.get_node("GameState")
	var journal = root.get_node("Journal")
	var dialogue = root.get_node("DialogueManager")
	journal.entry_added.connect(func(_id): discoveries += 1)
	for first in [0, 1]:
		for second in [0, 1]:
			state.new_game()
			check(dialogue.start("res://data/dialogue/keeper_intro.json", "logbook"), "start")
			dialogue.advance()
			dialogue.advance()
			dialogue.choose(first)
			dialogue.advance()
			dialogue.advance()
			dialogue.choose(second)
			dialogue.advance()
			# Seed storage explicitly; dialogue discovery wiring is a separate change.
			check(journal.entries().is_empty(), "dialogue does not discover entries")
			journal.discover("keeper_log")
			check(state.get_flag("trusted_edith") == (second == 0), "true and false flags")
			check(state.get_flag("skeptic" if first == 0 else "believer") == true, "first choice")
			state.set_flag("radioed_tom", true)
			state.set_flag("lamp_relit", false)
			var flags_before: Dictionary = state.flags.duplicate(true)
			check(state.save_game(), "save succeeds")
			state.new_game()
			check(journal.entries().is_empty() and state.flags.is_empty(), "new game reset")
			var count_before := discoveries
			check(state.load_game(), "load succeeds")
			check(state.flags == flags_before, "all story flags round trip")
			check(journal.entries() == ["keeper_log"], "journal round trip")
			check(discoveries == count_before, "load does not replay entry_added")
			journal.discover("keeper_log")
			check(discoveries == count_before, "repeat discovery is idempotent")
	var snapshot: Array = journal.entries()
	snapshot.append("external_mutation")
	check(not journal.has("external_mutation"), "snapshot is detached")
	for legacy in [{"version": 1, "flags": {"trusted_edith": false}}, {"flags": {"custom": 7.0}}]:
		write_save(legacy)
		check(state.load_game(), "legacy loads")
		check(state.flags == legacy.flags and journal.entries().is_empty(), "legacy flags preserved, no invented entries")
	write_save({"version": 2, "scene": "res://scenes/game.tscn", "flags": {"custom": false}, "journal": ["unknown_future_entry", "keeper_log", "keeper_log"]})
	check(state.load_game(), "unknown IDs retained")
	check(journal.entries() == ["unknown_future_entry", "keeper_log"], "ordered deduplication")
	# Missing or malformed journal data must not block valid scene/story progress.
	var malformed_cases: Array = [{"version": 2}]
	for bad_journal in [null, "bad", {}, 7, [7], [""], ["   "], ["keeper_log", 7]]:
		malformed_cases.append({"version": 2, "journal": bad_journal})
	for fixture in malformed_cases:
		journal.discover("stale_entry")
		state.current_scene = "res://scenes/game.tscn"
		state.flags = {"stale_flag": true}
		fixture["scene"] = "res://scenes/lamp_room.tscn"
		fixture["flags"] = {"trusted_edith": false, "radioed_tom": true}
		write_save(fixture)
		var disk_before := FileAccess.get_file_as_string("user://save.json")
		var count_before := discoveries
		check(state.load_game(), "malformed journal recovers")
		check(state.current_scene == fixture.scene and state.flags == fixture.flags, "recovery restores valid scene and flags")
		check(journal.entries().is_empty(), "recovery clears entire journal including stale entries")
		check(discoveries == count_before, "recovery does not replay discovery notifications")
		check(FileAccess.get_file_as_string("user://save.json") == disk_before, "recovery does not rewrite save")
		check(state.save_game() and state.load_game(), "recovered state can be saved and reloaded")
		check(journal.entries().is_empty() and state.flags == fixture.flags, "recovered state round trip")
	journal.discover("sentinel")
	var expected_flags: Dictionary = state.flags.duplicate(true)
	var expected_entries: Array = journal.entries()
	var expected_scene: String = state.current_scene
	for bad in [null, [], {"version": 99}, {"version": 2, "flags": [], "journal": "bad"}, {"version": 2, "scene": 42, "journal": "bad"}, {"version": 2, "scene": "res://scenes/missing.tscn", "journal": "bad"}]:
		write_save(bad)
		check(not state.load_game(), "invalid save rejected")
		check(state.flags == expected_flags and journal.entries() == expected_entries and state.current_scene == expected_scene, "failed load leaves live state intact")
	check(state.save_game(), "valid save replaces corrupt file")
	var f := FileAccess.open("user://save.json.tmp", FileAccess.WRITE)
	f.store_string("{interrupted")
	f.close()
	check(state.load_game(), "stale temporary write ignored")
	check(journal.entries() == expected_entries, "prior save retained")
	DirAccess.remove_absolute("user://save.json.tmp")
	DirAccess.make_dir_absolute("user://save.json.tmp")
	check(not state.save_game(), "cannot open temp path reports failure")
	check(state.load_game(), "failed write preserves previous save")
	DirAccess.remove_absolute("user://save.json.tmp")
	state.delete_save()
	check(not state.load_game(), "missing save")
	print("Save/journal failures: ", failures)
	quit(1 if failures else 0)
