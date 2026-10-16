extends SceneTree

## Offline/fixture acceptance: no missing-path engine errors, Markdown quests,
## and genuine on-disk receipt visibility through the cockpit UI.

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := ProjectSettings.globalize_path("user://gsv-cockpit-acceptance")
	var err := DirAccess.make_dir_recursive_absolute(fixture)
	if err != OK:
		_fail("could not create fixture directory: %s" % err)
		_finish()
		return

	var report := fixture.path_join("20261016-proof.md")
	var legacy := fixture.path_join("20261016-legacy.txt")
	var receipts := fixture.path_join("receipts.jsonl")
	_write(report, "# Sample verified quest")
	_write(legacy, "Legacy report")
	_write(receipts, '{"ts":"2026-10-16T14:00:00Z","kind":"proof","message":"portable-receipt-visible"}' + "\n")

	var prior_reports := OS.get_environment("GSV_KILOCORE_REPORTS_DIR")
	OS.set_environment("GSV_KILOCORE_REPORTS_DIR", fixture)

	var board: Control = load("res://scripts/QuestBoard.gd").new()
	root.add_child(board)
	await process_frame
	var quests := _visible_text(board)
	if not quests.contains("proof") or not quests.contains("legacy"):
		_fail("QuestBoard failed to display both .md and .txt reports: %s" % quests)
	else:
		print("[portable-test] PASS: Markdown and text quests rendered")

	var viewer: Control = load("res://scripts/ReceiptViewer.gd").new()
	root.add_child(viewer)
	await process_frame
	var audit := _visible_text(viewer)
	if not audit.contains("portable-receipt-visible"):
		_fail("ReceiptViewer did not render on-disk JSONL proof: %s" % audit)
	else:
		print("[portable-test] PASS: on-disk JSONL receipt displayed")

	OS.set_environment("GSV_KILOCORE_REPORTS_DIR", fixture.path_join("does-not-exist"))
	var empty_board: Control = load("res://scripts/QuestBoard.gd").new()
	root.add_child(empty_board)
	await process_frame
	var empty_text := _visible_text(empty_board)
	if not empty_text.contains("(no reports found)"):
		_fail("missing reports directory failed to render empty state")
	else:
		print("[portable-test] PASS: absent directory renders empty state without error")

	board.queue_free()
	viewer.queue_free()
	empty_board.queue_free()
	OS.set_environment("GSV_KILOCORE_REPORTS_DIR", prior_reports)
	for p in [report, legacy, receipts]:
		DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(fixture)
	_finish()

func _write(p: String, contents: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		_fail("cannot write fixture: %s" % p)
		return
	f.store_string(contents)
	f.close()

func _visible_text(node: Node) -> String:
	var txt := ""
	if node is Label:
		txt += node.text + "\n"
	if node is RichTextLabel:
		txt += node.get_parsed_text() + "\n"
	for child in node.get_children():
		txt += _visible_text(child)
	return txt

func _fail(msg: String) -> void:
	failures.append(msg)

func _finish() -> void:
	if failures.is_empty():
		print("[portable-test] PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("[portable-test] FAIL: %s" % failure)
		quit(1)
