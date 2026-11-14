extends SceneTree

## OPTIONAL workstation-local read-only integration canary; not a CI gate.
## Requires a fresh explicit GitHub CLI export, no fixture or POST.
const LEDGER = preload("res://scripts/workstation/WorkbenchReviewLedger.gd")
const HYPERSPACE = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
const REVIEW = preload("res://scripts/workstation/WorkbenchReviewDesk.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: Dictionary = LEDGER.read_optional()
	if not source.get("ok", false):
		printerr("REVIEW_LIVE_UNAVAILABLE: " + String(source.get("reason", "unknown")))
		quit(2)
		return
	var desk: PanelContainer = REVIEW.new()
	root.add_child(desk)
	await process_frame
	if not desk._data.get("ok", false) or desk._active_rows.size() != source["items"].size():
		printerr("REVIEW_LIVE_DESK_MISMATCH")
		quit(1)
		return
	var space: PanelContainer = HYPERSPACE.new()
	root.add_child(space)
	await process_frame
	if space._review_state != "observed" or space._graph.get("review_count", -1) != mini(16, source["items"].size()):
		printerr("REVIEW_LIVE_GRAPH_MISMATCH: " + str(space._graph.get("review_count", -1)))
		quit(1)
		return
	var first: Dictionary = source["items"][0]
	var key := "review:" + String(first["key"])
	if not space.select_key(key):
		printerr("REVIEW_LIVE_SOURCE_NOT_SELECTABLE: " + key)
		quit(1)
		return
	if not space._info.text.contains(String(first["head"])):
		printerr("REVIEW_LIVE_EXACT_HEAD_MISSING")
		quit(1)
		return
	print("WORKSTATION_REVIEW_LIVE_PASS count=" + str(source["items"].size()) +
		" observed=" + str(space._graph["review_count"]) +
		" source_age=" + str(int(source["age_seconds"])) + "s")
	quit(0)
