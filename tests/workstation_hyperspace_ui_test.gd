extends SceneTree

const HYPERSPACE = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
var errors: Array[String] = []
var contexts: Array[Dictionary] = []
var openings: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var view: PanelContainer = HYPERSPACE.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.compose_requested.connect(func(c: Dictionary): contexts.append(c))
	view.resource_activated.connect(func(c: Dictionary): openings.append(c))
	root.add_child(view)
	await process_frame
	_assert(view._viewport != null and not view._viewport.disable_3d, "native 3D viewport exists")
	_assert(view._camera != null and view._camera.current, "actual camera bound to viewport")
	_assert(view._meshes.size() == 4, "four unknown source-bound rig meshes, no fake agents")
	_assert(view._directory_keys.size() == 4, "finder sees all four physical rigs")
	_assert(view.select_key("rig:desktop-i3anuvp"), "I3 can be selected independently")
	_assert(view._selected == "rig:desktop-i3anuvp", "I3 not pinned to Xanadu")
	view._focus_selected()
	_assert(view._focus_target == view._meshes["rig:desktop-i3anuvp"]["root"].position, "I3 focus target")
	view._directory_search.text = "Xanadu"
	view._rebuild_directory()
	_assert(view._directory_keys.size() == 1 and view._directory_keys[0] == "rig:imac-xanadu",
		"finder filters real rig names")
	view._directory_search.text = ""
	view._rebuild_directory()
	view._cycle_visible(1)
	_assert(view._selected != "rig:desktop-i3anuvp", "cycle changes selection")
	_assert(view._compose_button.disabled, "no arbitrary mission before observed repo")
	view.set_snapshot({
		"body_feed_state": "observed",
		"bodies": [{"body_id": "kilo-core-msi", "state": "stale"}],
		"project_feed_state": "observed",
		"projects": [{"name": "Test", "path": "C:/dev/active/test", "branch": "main"}],
		"mission_feed_state": "observed",
		"missions": [{"id": "msn_012345abcdef", "title": "Test real mission", "risk": "R2",
			"status": "awaiting_approval", "repo": "C:/dev/active/test"}],
		"service_feed_state": "unknown", "services": []
	})
	await process_frame
	_assert(view._meshes.size() == 6, "source-bound 3D graph renders project and mission")
	_assert(view._graph["edges"].size() == 1, "one source-backed spatial edge")
	_assert(view._links.size() == 1, "verified relation has a visible 3D wire")
	_assert(view._flow_markers.is_empty(), "awaiting approval is NOT running work")
	_assert(view._meshes["rig:kilo-core-msi"]["root"].get_child_count() > 1,
		"rig retains composite hardware silhouette")
	_assert(view._meshes["project:C:/dev/active/test"]["root"].get_child_count() > 1,
		"project retains composite code silhouette")
	_assert(view.select_key("project:C:/dev/active/test"), "project picking changes actual selection")
	_assert(not view._compose_button.disabled, "observed project enables compose")
	view._compose_selected()
	_assert(contexts.size() == 1 and contexts[0]["path"] == "C:/dev/active/test", "project emits strict source repo hint")
	_assert(contexts[0]["risk"] == "R0", "navigation starts in R0, not privilege escalation")
	view._open_selected()
	_assert(openings.size() == 1 and openings[0]["kind"] == "project", "project emits real resource intent")
	_assert(view.select_key("mission:msn_012345abcdef"), "mission is selectable in 3D")
	_assert(view._info.text.contains("AWAITING_APPROVAL"), "approval remains visible, not implied complete")
	view._open_selected()
	_assert(openings.size() == 2 and openings[1]["id"] == "msn_012345abcdef", "mission deep-links to real ID")
	view._time.select(1)
	view._apply_visibility()
	_assert(not view._meshes["mission:msn_012345abcdef"]["root"].visible, "missing source time cannot qualify age filter")
	view._time.select(0)
	view._lens.select(2)
	view._apply_visibility()
	_assert(not view._meshes["rig:kilo-core-msi"]["root"].visible, "resource domain actually filters 3D")
	_assert(not view._links[0]["root"].visible, "filtered edge also hides in theatre")
	view._lens.select(0)
	view._apply_visibility()
	view._directory_search.text = "I3"
	view._rebuild_directory()
	view._on_directory_selected(0)
	_assert(view._selected == "rig:desktop-i3anuvp", "finder click selects physical I3")
	view._directory_search.text = ""
	view._rebuild_directory()
	view.set_snapshot({
		"project_feed_state": "observed",
		"projects": [{"name": "Test", "path": "C:/dev/active/test", "branch": "main"}],
		"mission_feed_state": "observed",
		"missions": [{"id": "msn_012345abcdef", "title": "Real running task",
			"risk": "R2", "status": "running", "repo": "C:/dev/active/test"}]
	})
	_assert(view._flow_markers.size() == 1, "real running mission has a work packet")
	_assert(view._verified_running == 1, "verified activity count reflects source")
	view._lens.select(1)
	view._apply_visibility()
	_assert(not view._flow_markers[0]["node"].visible, "hidden work does not falsely glow")
	view._lens.select(0)
	view._apply_visibility()
	_assert(view._flow_markers[0]["node"].visible, "restored source relation resumes visible work")
	view.set_snapshot({
		"tool_atlas_state": "observed",
		"tools": [{"id": "omnisynapse", "name": "OMNISYNAPSE", "status": "source_present",
			"path": "C:/dev/active/OMNISYNAPSE"}]
	})
	_assert(view._meshes.has("tool:omnisynapse"), "opt-in local presence renders distinct tool")
	view._lens.select(7)
	view._apply_visibility()
	_assert(view._directory_keys.size() == 1, "new eighth lens isolates tool presence")
	view._on_directory_selected(0)
	_assert(view._selected == "tool:omnisynapse", "tool can be selected by finder")
	_assert(view._open_button.disabled and view._compose_button.disabled,
		"filesystem presence does not authorize session or mission submission")
	_assert(view._info.text.contains("does not establish a connected"),
		"inspector explains limits of tool presence")
	view.queue_free()
	await process_frame
	await process_frame
	if errors.is_empty():
		print("WORKSTATION_HYPERSPACE_UI_PASS")
		quit(0)
	else:
		for e in errors:
			printerr("WORKSTATION_HYPERSPACE_UI_FAIL: " + e)
		quit(1)

func _assert(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
