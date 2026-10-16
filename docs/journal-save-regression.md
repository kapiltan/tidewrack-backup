# Journal save regression notes

Use an isolated Godot user-data directory and disposable save fixtures; keep real
player saves untouched. Gameplay discovery wiring and the reader UI are pending,
so seed entries through a test harness calling Journal.discover and inspect
Journal.entries(), GameState.flags, and GameState.current_scene.

The persistence regression suite is tests/test_save_journal.gd. It passed in
Godot 4.3 after adding malformed-journal recovery. Run it with:

```sh
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --editor --import --quit
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --script tests/test_save_journal.gd
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --script tests/test_save_swap.gd
```

The API checks below are covered by that suite where stated; interactive
cold-restart Continue and exported target-platform checks remain pending.
See [the full verification checklist](journal-save-verification.md) for write
interruption, overwrite UX, and other launch checks.

## 1. Normal save/Continue

**Steps:** In the ground-floor scene, seed keeper_log through
Journal.discover("keeper_log"). Set trusted_edith to false and radioed_tom to true.
Use Pause > Save, verify success, quit the process, relaunch, and select Continue.
Inspect the restored state through the harness.

**Expected:** The saved scene and both flags, including the explicit false value,
are restored. Journal.entries() contains keeper_log exactly once. Loading replaces
live entries rather than merging them and does not emit entry_added. The saved
version is 2. Player position and active dialogue position are not persisted.

**Coverage:** API save/load, flags, journal round trip, and silent restore passed
in the engine suite. Cold-restart menu/scene integration is still a manual check.
Reading the logbook alone does not discover an entry in this persistence-only PR.

**Replacement failures and recovery:** Before replacing save.json, save_game keeps
and validates a previous snapshot in save.json.bak. A backup-copy failure aborts
before replacement. If Windows deletes save.json and then rename fails, Save
reports failure but the previous checkpoint remains in backup. With no primary,
Continue loads a valid backup first, then a valid temp if backup is absent/invalid.
A valid primary always wins; an existing invalid primary is not silently bypassed.
Recovery does not modify files. It restores a whole snapshot using the same
journal fallback rules as normal loading. A first failed save can recover from
its complete temp, and a retry preserves that temp in backup before rewriting it.
Explicit delete_save removes all three candidates; New Game only clears memory.

The swap suite passes injected copy failure, failure before deletion, and the
Windows-style delete/rename gap. It checks prior bytes retained in backup,
fresh-instance load, backup priority, invalid backup with valid temp, invalid
candidates, first-save/temp-only retry recovery, successful replacement, and
explicit deletion. Native Windows, cold process restart, and actual power loss
remain untested. The guarantee concerns a previous persisted checkpoint under
single-process operation, not unsaved progress or hardware/filesystem failure.

## 2. A v1 save without journal data

**Steps:** Seed a live journal entry to detect stale-state leakage, then place this
fixture at user://save.json in the isolated test profile and load it:

```json
{
  "version": 1,
  "scene": "res://scenes/game.tscn",
  "flags": {"trusted_edith": false, "radioed_tom": true}
}
```

**Expected:** Load succeeds, restores the scene and flags, and clears the journal
to an empty array. It does not infer discoveries from flags. Loading does not
rewrite the file; a subsequent successful save writes version 2 with journal: [].
Unversioned saves follow the same legacy path.

**Coverage:** Legacy and unversioned loading, flag preservation, and empty-journal
replacement passed in the engine suite. Verify the subsequent on-disk v2 rewrite
and repeat Continue with archived player saves manually.

## 3. New Game reset

**Steps:** Seed journal entries and story flags, save, then start New Game.
Inspect the live state. Before saving the new game, return to the menu and
Continue; then repeat New Game, save the cleared state, and Continue again.

**Expected:** New Game clears live journal entries and flags and resets the scene
to res://scenes/game.tscn. It does not delete or overwrite the existing disk save.
Continue before another Save restores the old saved progress; after saving the
new game, Continue restores the empty journal and new flags. Reset does not emit
entry_added. Overwrite confirmation is not implemented by this PR.

**Coverage:** Live journal/flag reset and subsequent load passed in the engine
suite. The complete menu sequence and saving the cleared state remain manual
checks.

## 4. Duplicate discovery

**Steps:** Call Journal.discover("keeper_log") twice, then save/load and call it
again. Also load a valid version-2 fixture whose journal array is
["unknown_future_entry", "keeper_log", "keeper_log"].

**Expected:** Each ID occurs once, in first-seen order. Repeating a discovery emits
no additional entry_added notification. Loading does not replay entry_added.
The duplicate fixture restores ["unknown_future_entry", "keeper_log"]; unknown,
nonblank IDs are retained. A following save must keep that normalized order.

**Coverage:** Repeated discovery after restore, signal suppression, and
ordered deduplication with unknown IDs passed in the engine suite. Repeat the
explicit two-calls-before-save sequence and inspect the normalized saved JSON
during manual verification.

## 5. Malformed journal data

**Steps:** Seed stale live entries and flags, then load otherwise valid version-2
saves with journal missing, null, a string/object/number instead of an array,
[7], [""], ["   "], and ["keeper_log", 7]. Use a different valid saved scene and
flags including trusted_edith: false to prove they are restored.

**Expected:** Load returns true and logs a warning that malformed journal data is
being replaced with an empty journal. The valid saved scene and flags are restored.
The entire journal becomes empty, including any stale live entries; a mixed array
is not partially salvaged. No entry_added notification is emitted. Loading leaves
the disk file untouched; a subsequent successful save/load retains the recovered
scene/flags and empty journal. Missing journal data in v1 still loads empty without
this v2 warning. Duplicate and unknown nonblank string IDs remain valid.

**Rejection boundary:** An invalid scene or flags still rejects the load without
changing live state, even when the journal is also malformed. Unreadable files,
invalid JSON/top-level data, and unsupported save versions remain rejected by the
existing format checks; journal recovery does not bypass those checks.

**Coverage:** All listed journal fixtures passed in the engine suite, including
restoration of a different scene, explicit false flags, clearing stale entries,
silent discovery signals, unchanged disk contents, and subsequent save/load.
Invalid scene/flags combined with malformed journal data also passed rejection
checks. The run logged one warning per malformed-journal fixture (nine total).
Interactive Continue and its warning presentation remain manual checks.
