# Journal save hardening — Sprint 29

Baseline: main 8c9b1e407afe178a6287c6646705185d2e356e3c. This identifies
repository code, not the unverified Wk29 playtest binary.

## What survives today, before this patch

Pause > Save assigns scene_file_path, then GameState writes version 1, scene,
and flags directly to user://save.json. Main Menu does not save. Continue is
enabled by file existence; load_game restores scene/flags and the menu changes
scene. The player respawns at the authored position. Dialogue starts again from
its interaction entry point. There is no autosave or dialogue cursor persistence.
Pause is blocked during dialogue, so the normal Save UI cannot save mid-dialogue.
An OS quit during dialogue loses changes since the last manual save.

Story flags include skeptic/believer, trusted_edith (including false), and
radioed_tom. Dialogue applies flags but does not branch on them. Replay can set
both skeptic and believer; changing that narrative policy is outside this patch.
Interactable._used is local and unsaved; current interactables do not enable once.
Journal is neither autoloaded nor called anywhere in the baseline; its entries
cannot survive a process restart. Settings use a separate persistence path.

## Patch contract

- Journal becomes an autoload, preserving insertion order and unique nonblank IDs.
- Discovery wiring is deferred: dialogue and content are unchanged. Entries added
  through Journal.discover are persisted; gameplay does not yet call this API.
- Version 2 adds journal (array of IDs) alongside existing scene and flags.
- Version 1 and unversioned saves retain flags and scene, defaulting journal to
  empty. Old progress cannot reconstruct entries reliably. Replaying the logbook
  does not discover entries in this patch. Older binaries may discard v2 data.
- Unknown nonempty IDs survive round trips for future content. Duplicate IDs
  collapse in first-seen order. No title/text content or reader UI is added.
- Missing or malformed v2 journal data logs a warning and loads an empty journal
  while restoring valid scene and flags. Any invalid entry clears the entire array.
  Invalid scene/flags, invalid JSON/top-level data, and unsupported versions still
  reject the load without mutating live state. Loading never rewrites the disk file.
- Successful loads replace rather than merge state; they emit entries_changed,
  not entry_added, so discovery notifications are not replayed. New Game clears
  journal and flags in memory; it still leaves the disk save until the next Save.
- Before touching temp or primary, saving selects the first valid snapshot from
  primary, backup, then temp. If it is not already the backup, it copies it to
  user://save.json.bak and verifies the copy's contents and loadability. Backup
  failure aborts before replacement. This also protects a temp-only recovery save.
- The new payload is written/flushed/closed in user://save.json.tmp before rename
  to save.json. The backup remains through and after replacement. On Windows,
  Godot may delete the destination before rename; failure in that gap returns
  false but leaves the previous checkpoint in backup and the new snapshot in temp.
- If primary is missing, Continue is available when backup or temp is loadable.
  load_game tries valid backup first, then valid temp, and warns on recovery. It
  never merges snapshots or rewrites recovery files during loading. An existing
  invalid primary remains an error rather than silently rolling back. Journal
  validation/fallback rules are identical for primary, backup, and temp.
- Explicit delete_save removes primary, backup, and temp to prevent resurrection.
  New Game still resets memory only. Recovery prioritizes the previous committed
  checkpoint over a newer uncommitted temp when both are valid.
- This protects the previous persisted checkpoint against the delete/rename gap
  in a single running game. It does not promise preservation of unsaved changes,
  survival of hardware/filesystem failure, or safety with concurrent game writers.
  Actual power-loss durability and native Windows execution remain unverified.

## Automated checks

Run with Godot 4.3+ and an isolated data directory so tests cannot touch real saves:

```sh
python3 tests/validate_dialogue.py
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --editor --import --quit
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --script tests/test_save_journal.gd
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --script tests/test_save_swap.gd
```

Journal entries are seeded directly through Journal.discover in the tests, with no
content annotations or discovery wiring. The unchanged dialogue validator retains
its journal-graph placeholder; no annotation checks are needed.

Engine suite covers all four logbook choice combinations, true/false/custom flag
round trips, New Game clearing, journal round trip/order/deduplication, detached
snapshots, silent restore, version 1/unversioned saves, unknown IDs, malformed
journal recovery with scene/flag preservation and no disk rewrite, invalid core
state rejection without partial mutation, stale temporary files, missing saves,
and failed temporary-file creation preserving the previous save.
The swap suite uses tests/helpers/fault_game_state.gd to inject backup-copy failure,
replacement failure before deletion, and deletion followed by rename failure. It
checks byte-for-byte backup retention, fresh-instance recovery, backup priority,
invalid-backup/valid-temp fallback, invalid-candidate rejection, temp-only retry
safety, first-save failure recovery, successful replacement, and explicit deletion.
Fresh-instance recovery is not a full process restart or native Windows test.

## Validation performed

Godot 4.3 headless editor import completed successfully on the initial patch.
After the backup/recovery change, both engine suites were rerun: the swap suite
reports `Save swap failures: 0`, and the journal suite reports
`Save/journal failures: 0`; corruption and blocked-temp-path tests intentionally
log expected errors; the swap suite logs recovery warnings and intentional
invalid-JSON fixture errors. Nine malformed-journal fixtures log recovery warnings and pass,
including recovery save/load round trips. Both dialogue graphs pass the Python validator with no warnings.
`git diff --check` passes. Interactive/exported and real power-loss tests below
remain pending. The engine run caught and corrected a JSON numeric-version check:
Godot parses JSON numbers as floats, so version checks use numeric equality rather
than Array membership (which distinguishes integer and floating-point variants).

## Before calling it done

- [ ] Match the tested/exported Wk29 binary to a commit; run the engine suite on
      that candidate and target OSes, including exported resource loading.
- [ ] Cold quit/relaunch/Continue after each of the four logbook combinations;
      verify all flags plus journal IDs seeded through a test harness. Gameplay
      discovery and its end-to-end checks belong to a separate wiring change.
- [ ] Load real archived v1 saves with true AND false trusted_edith, radioed_tom,
      and lamp_relit; save as v2 and relaunch. Retain originals for comparison.
- [ ] New Game with an existing save: cancel/confirm behavior still needs product
      implementation. The current menu has no overwrite confirmation (FB-036).
- [ ] Missing/corrupt/future save: current menu checks existence and gives no load
      error explanation. Add user-visible recovery without silently deleting data.
- [ ] Kill before temp write, during write, and during replacement; inject full
      disk, permission and rename failures. Confirm either prior or complete new
      snapshot (including recovery candidates), plus accurate Save failed feedback.
      The deletion/rename gap is covered by injected tests; native Windows and
      real process interruption/power loss still require target-platform testing.
- [ ] Exit mid-dialogue and Continue: verify last manual checkpoint semantics and
      no stuck dialogue/movement; do not claim dialogue cursor or position resume.
- [ ] Reader UI, entry content, controller focus and discoverability remain open;
      this patch hardens state, it does not complete the player-facing journal.
- [ ] Decide whether exact position, once-only interactions, dialogue checkpoints,
      and conflicting replay flags are launch requirements; they remain unsaved
      or unchanged. Do not mark FB-005 fixed solely from a source review.
