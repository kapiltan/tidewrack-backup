extends Node
## Ordered discovery IDs; snapshots are copies, restores never replay discoveries.
signal entry_added(id: String)
signal entries_changed

var _entries: Array[String] = []


func discover(id: String) -> void:
	if id.strip_edges().is_empty() or id in _entries:
		return
	_entries.append(id)
	entry_added.emit(id)
	entries_changed.emit()


func entries() -> Array[String]:
	return _entries.duplicate()


func has(id: String) -> bool:
	return id in _entries


func restore(ids: Array) -> void:
	_entries.clear()
	for id in ids:
		if id is String and not id.strip_edges().is_empty() and id not in _entries:
			_entries.append(id)
	entries_changed.emit()
