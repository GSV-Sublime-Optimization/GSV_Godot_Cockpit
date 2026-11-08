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
	_assert(view._directory_keys.size() == 4, "every rig available through explicit object finder")
	_assert(view._directory_keys.has("rig:imac-xanadu"), "Xanadu listed, not forced")
	_assert(view._directory_keys.has("rig:desktop-i3anuvp"), "I3 independently reachable")
	_assert(view.select_key("rig:desktop-i3anuvp"), "selection moves from any rig to I3")
	_assert(view._selected == "rig:desktop-i3anuvp", "I3 is actually selected")
	_assert(view._directory.get_selected_items().size() == 1, "finder follows 3D selection")
	view._focus_selected()
	_assert(view._camera_target == view._meshes["rig:desktop-i3anuvp"]["root"].position, "focus re-centres on selected rig")
	view._cycle_visible(1)
	_assert(view._selected != "rig:desktop-i3anuvp", "next node changes selection")
	view._directory_search.text = "Xanadu"
	view._rebuild_directory()
	_assert(view._directory_keys.size() == 1 and view._directory_keys[0] == "rig:imac-xanadu", "finder searches actual source identity")
	view._directory_search.text = ""
	view._rebuild_directory()
	_assert(view._pulse_nodes.is_empty() and not view.is_processing(), "unknown rigs never animate as working")
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
	_assert(view._edge_meshes.size() == 1, "verified repo relation has a 3D edge")
	_assert(view._meshes["rig:kilo-core-msi"]["body"].mesh is BoxMesh, "rig rendered as hardware chassis")
	_assert(view._meshes["project:C:/dev/active/test"]["body"].mesh is CylinderMesh, "code repository rendered as hexagonal vault")
	_assert(view._meshes["mission:msn_012345abcdef"]["body"].mesh is SphereMesh, "mission rendered as faceted work crystal")
	_assert(view._pulse_nodes.is_empty() and not view.is_processing(), "awaiting approval is not running work")
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
	_assert(not view._edge_meshes[0]["node"].visible, "verified edge hides when its endpoint is filtered")
	view._lens.select(0)
	view._apply_visibility()
	_assert(view.select_key("rig:kilo-core-msi"), "selected rig can be changed after domain filtering")
	view._directory_search.text = "I3"
	view._rebuild_directory()
	view._on_directory_selected(0)
	_assert(view._selected == "rig:desktop-i3anuvp", "directory click selects I3, never pins Xanadu")
	view._directory_search.text = ""
	view._rebuild_directory()
	view.set_snapshot({
		"mission_feed_state": "observed",
		"missions": [{"id": "msn_012345abcdef", "title": "Observed build", "risk": "R2",
			"status": "running", "repo": "C:/dev/active/test"}]
	})
	_assert(view._pulse_nodes.size() == 1 and view.is_processing(), "only source-observed running work enables animated activity")
	view._lens.select(1)
	view._apply_visibility()
	_assert(not view.is_processing(), "hidden running mission uses no animation CPU")
	view._lens.select(0)
	view._apply_visibility()
	_assert(view.is_processing(), "restored running mission resumes meaningful animation")
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
