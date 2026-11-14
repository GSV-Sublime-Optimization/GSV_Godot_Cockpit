extends SceneTree

## A PR snapshot cannot create review grants, merge permission, or fake actors.
const LEDGER = preload("res://scripts/workstation/WorkbenchReviewLedger.gd")
const DESK = preload("res://scripts/workstation/WorkbenchReviewDesk.gd")
const HYPERSPACE = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
const APP = preload("res://scenes/ColonyWorkstation.tscn")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _row() -> Dictionary:
	var repo := "GSV-Sublime-Optimization/GSV_Godot_Cockpit"
	return {
		"key": repo + "#20", "repo": repo, "number": 20,
		"url": "https://github.com/" + repo + "/pull/20",
		"title": "Fix source-bound mission",
		"head": "dddddddddddddddddddddddddddddddddddddddd",
		"base": "master", "draft": true, "ci": "passed",
		"review": "UNVERIFIED", "mergeable": "MERGEABLE",
		"provenance": true, "changed_files": 4,
		"lane": "author_admission", "blockers": ["draft", "independent_review_unverified"],
		"score": 34, "required_skill": "godot",
		"suggested_actor": "", "assignment_authorized": false,
		"routing_reason": "source_owner_or_dependency_action_required",
		"detail_observed": true, "updated_at": "2026-11-08T17:00:00Z"
	}

func _document() -> Dictionary:
	return {
		"schema": LEDGER.SCHEMA,
		"generated_utc": Time.get_datetime_string_from_system(true) + "Z",
		"ttl_seconds": 300, "source": "GitHub gh-cli read-only",
		"gate": "advisory_only_exact_head_gsv_merge_dry_run_required",
		"items": [_row()]
	}

func _run() -> void:
	var raw := _document()
	var parsed: Dictionary = LEDGER.parse(JSON.stringify(raw))
	_check(parsed.get("ok", false), "valid recent source index accepted")
	if not parsed.get("ok", false):
		printerr("SOURCE_PARSER_REASON " + String(parsed.get("reason", "?")))
		quit(1)
		return
	_check(parsed["items"][0]["head"] == "dddddddddddddddddddddddddddddddddddddddd",
		"exact review identity retained")
	var text := LEDGER.brief(parsed["items"][0])
	_check(text.contains("EXACT HEAD") and text.contains("ddddd")
		and text.contains("Never merge"), "bounded handoff includes hard gate")

	var altered: Dictionary = raw.duplicate(true)
	altered["items"][0]["assignment_authorized"] = true
	_check(not LEDGER.parse(JSON.stringify(altered)).get("ok", false),
		"claiming actor assignment is rejected")
	altered = raw.duplicate(true)
	altered["items"][0]["url"] = "https://example.com/evil"
	_check(not LEDGER.parse(JSON.stringify(altered)).get("ok", false),
		"untrusted source link is rejected")
	altered = raw.duplicate(true)
	altered["items"][0]["head"] = "bad-head"
	_check(not LEDGER.parse(JSON.stringify(altered)).get("ok", false),
		"invalid commit ref rejected")
	altered = raw.duplicate(true)
	altered["items"].append(_row())
	_check(not LEDGER.parse(JSON.stringify(altered)).get("ok", false),
		"duplicate PR identity rejected")
	altered = raw.duplicate(true)
	altered["generated_utc"] = "2020-01-01T00:00:00Z"
	_check(LEDGER.parse(JSON.stringify(altered)).get("reason") == "stale_source",
		"stale queue cannot masquerade as current")
	altered = raw.duplicate(true)
	altered["generated_utc"] = "2099-01-01T00:00:00Z"
	_check(LEDGER.parse(JSON.stringify(altered)).get("reason") == "future_dated",
		"future-dated source refused")
	altered = raw.duplicate(true)
	altered["gate"] = "automatic_merge_allowed"
	_check(LEDGER.parse(JSON.stringify(altered)).get("reason") == "unsafe_authority_claim",
		"review queue cannot claim merge authority")

	var desk: PanelContainer = DESK.new()
	root.add_child(desk)
	await process_frame
	desk.set_data(parsed)
	_check(desk._queue.item_count == 1, "review operations populates actual observed PR")
	_check(desk._open.disabled and desk._copy.disabled, "unselected resource has no actions")
	desk._focus_next()
	_check(desk._selected == 0, "explicit NEXT focuses an actual PR")
	_check(desk._detail.text.contains("author_admission")
		and desk._detail.text.contains("UNOBSERVED / NOT ASSIGNED"),
		"operator sees truth of blockers and actor availability")
	_check(not desk._copy.disabled and not desk._open.disabled,
		"explicit choice enables source link and bounded handoff")
	desk._search.text = "no such repository"
	desk._render_queue()
	_check(desk._queue.item_count == 0 and desk._open.disabled,
		"search removes actions for hidden sources")
	desk.queue_free()
	await process_frame

	var view: PanelContainer = HYPERSPACE.new()
	var openings: Array[Dictionary] = []
	view.resource_activated.connect(func(meta: Dictionary): openings.append(meta))
	root.add_child(view)
	await process_frame
	view._review_rows.clear()
	for item in parsed["items"]:
		view._review_rows.append(item.duplicate(true))
	view._review_state = "observed"
	view._render()
	var marker := "review:GSV-Sublime-Optimization/GSV_Godot_Cockpit#20"
	_check(view._meshes.has(marker), "source-authenticated PR appears in a distinct 3D gate ring")
	_check(view._graph.get("review_count") == 1 and view._graph["edges"].is_empty(),
		"review gate is source-backed and does not invent repo runtime links")
	view._lens.select(7)
	view._apply_visibility()
	_check(view._meshes[marker]["root"].visible and not view._meshes["rig:kilo-core-msi"]["root"].visible,
		"the 3D review lens actually filters spatial objects")
	_check(view.select_key(marker), "operator may select real PR gate instead of Xanadu")
	_check(view._info.text.contains("dddddddddddddddddddddddd") and view._info.text.contains("NOT ASSIGNED"),
		"review gate exposes exact head and lack of admitted reviewer")
	view._open_selected()
	_check(openings.size() == 1 and openings[0]["kind"] == "reviews",
		"3D pull-request gate routes into actual Review Operations")
	view.queue_free()
	await process_frame

	var app: Control = APP.instantiate()
	app.auto_refresh = false
	root.add_child(app)
	await process_frame
	app._open_resource({"kind": "reviews", "id": "reviews", "name": "Review Operations"})
	await process_frame
	_check(app._pages.has("reviews:reviews"), "review operations has its own real cockpit surface")
	_check(app._library_panel.visible, "operational PR seat restores work docks from 3D dive")
	_check(app._palette_commands.any(func(it): return it["id"] == "reviews"),
		"operator can reach review queue from command palette")
	app.queue_free()
	await process_frame
	if failures.is_empty():
		print("WORKSTATION_REVIEW_OPERATIONS_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("WORKSTATION_REVIEW_OPERATIONS_FAIL: " + failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
