extends SceneTree

const SCENE = preload("res://scenes/ColonyWorkstation.tscn")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var begin := Time.get_ticks_msec()
	var ui: Control = SCENE.instantiate()
	ui.auto_refresh = false
	root.add_child(ui)
	await process_frame
	_check(ui._view_ready, "first-frame interface ready")
	_check(Time.get_ticks_msec() - begin < 1500, "no blocking startup subprocess")
	_check(ui._tabs.get_tab_count() == 1 and ui._pages.has("hyperspace:hyperspace"),
		"3D holographic theatre opens as first tab, not legacy fleet menus")
	_check(not ui._library_panel.visible and not ui._inspector_panel.visible,
		"first-paint is immersive instead of a cluttered dock dashboard")
	ui._close_tab(ui._tabs.current_tab)
	await process_frame
	_check(ui._pages.has("fleet:fleet"), "closing theatre opens working legacy fleet surface")
	_check(ui._rig_labels.size() == 4, "all four rig cards remain available")
	_check(ui._palette_commands.size() >= 8, "command palette actions registered")
	_check(ui._palette != null and ui._palette_results != null, "command palette constructed")
	if ui._palette_results != null:
		_check(ui._palette_results.item_count >= 8, "palette actions actually visible")
		ui._palette_search.text = "fleet"
		ui._fill_palette()
		_check(ui._palette_results.item_count == 1, "palette filters action list")
		ui._palette_search.text = ""
		ui._fill_palette()
	_check(ui._pages.has("fleet:fleet"), "fleet workspace pinned")
	_check(not ui._activity.text.contains("running agent"), "no fake agent alive banner")
	var fake := {
		"body_feed_state": "observed", "mission_feed_state": "observed",
		"service_feed_state": "observed",
		"health": {"state": "live"},
		"authorized_actuators": [],
		"bodies": [
			{"body_id": "kilo-core-msi", "state": "reported_fresh",
				"observation": {"memory_available_bytes": 8589934592, "system_volume_free_bytes": 21474836480}},
			{"body_id": "desktop-i3anuvp", "state": "stale", "observation": {}},
			{"body_id": "desktop-l9v3emb", "state": "unknown", "observation": {}},
			{"body_id": "imac-xanadu", "state": "invalid", "observation": {}}
		],
		"missions": [{"id": "msn_012345abcdef", "title": "Fixture only",
			"risk": "R0", "status": "running", "source": "test_fixture",
			"session_kind": "mission_log", "interactive": false}],
		"services": [{"name": "Fixture Hub", "status": "DEGRADED"}]
	}
	ui._on_snapshot(fake)
	_check(ui._status.text.contains("1/4 FRESH"), "fresh state is not generalized")
	_check(ui._rig_labels["desktop-i3anuvp"].text.contains("STALE"), "stale rig visible")
	_check(ui._rig_labels["desktop-l9v3emb"].text.contains("UNKNOWN"), "unknown rig visible")
	ui._open_resource({"kind": "agent", "id": "hermes", "name": "Hermes Agent",
		"role": "Persistent agent runner"})
	await process_frame
	_check(ui._tabs.get_tab_count() == 2, "agent gets own tab")
	var pane: Node = ui._pages["agent:hermes"].get_child(0)
	_check(not pane._read_log.disabled == false, "unobserved agent log button disabled")
	_check(pane._terminal.text.contains("No authenticated"), "PTY not fabricated")
	ui._open_resource({"kind": "sessions", "id": "sessions", "name": "Missions"})
	_check(ui._mission_list.item_count == 1, "observed mission indexed")
	ui._activate_mission(0)
	await process_frame
	_check(ui._pages.has("mission:msn_012345abcdef"), "mission opens in tab")
	var mission_pane: Node = ui._pages["mission:msn_012345abcdef"].get_child(0)
	_check(not mission_pane._read_log.disabled, "mission log explicitly fetchable")
	ui._close_tab(ui._tabs.get_tab_idx_from_control(ui._pages["agent:hermes"]))
	await process_frame
	_check(not ui._pages.has("agent:hermes"), "tab close detaches local view")
	_check(ui._pages.has("fleet:fleet"), "closing other tab preserves fleet")
	ui._apply_layout(1)
	_check(not ui._inspector_panel.visible and not ui._activity_panel.visible, "focus layout")
	ui._apply_layout(0)
	_check(ui._inspector_panel.visible and ui._activity_panel.visible, "colony layout")
	ui._open_resource({"kind": "hyperspace", "id": "hyperspace", "name": "Hyperspace"})
	await process_frame
	_check(ui._pages.has("hyperspace:hyperspace"), "3D graph is a real workstation tab")
	var hyper: Node = ui._pages["hyperspace:hyperspace"].get_child(0)
	_check(hyper._viewport != null and hyper._camera != null, "embedded 3D viewport and camera initialize")
	hyper.set_snapshot({
		"body_feed_state": "unknown", "bodies": [],
		"project_feed_state": "observed",
		"projects": [{"name": "Fixture repo", "path": "C:/dev/active/fixture", "branch": "main"}],
		"mission_feed_state": "unknown", "missions": [],
		"service_feed_state": "unknown", "services": []
	})
	_check(hyper.select_key("project:C:/dev/active/fixture"), "embedded graph sees source project")
	hyper._open_selected()
	_check(ui._pages.has("project:C:/dev/active/fixture"), "graph deep-link opens project resource")
	ui._compose_from_space({"path": "C:/dev/active/fixture", "title": "Inspect fixture",
		"objective": "Review this fixture source and report checks without editing files.",
		"acceptance": "Report source evidence", "risk": "R0"})
	_check(ui._pages.has("factory:factory"), "graph action opens owner-backed mission composer")
	var factory: Node = ui._pages["factory:factory"].get_child(0)
	_check(factory._title.text == "Inspect fixture", "factory receives exact project context")
	_check(factory._pending_project == "C:/dev/active/fixture", "context hint preserved for fresh Studio validation")
	_check(factory._submit.disabled, "context alone cannot authorize mission POST")
	ui.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("WORKSTATION_UI_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("WORKSTATION_UI_FAIL: " + failure)
		quit(1)

func _check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
