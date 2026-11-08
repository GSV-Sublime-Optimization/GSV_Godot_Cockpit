extends SceneTree

## The hologram is a working input surface with honest source/freshness boundaries.
const VIEW = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
const WORKSTATION = preload("res://scenes/ColonyWorkstation.tscn")

var failures: PackedStringArray = []
var refreshes := 0
var navigated: Array[Dictionary] = []
var compositions: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ColonyWorkstation.tscn",
		"default Godot Play enters the actual 3D workstation, not old 13-tab scene")
	var view: PanelContainer = VIEW.new()
	view.refresh_requested.connect(func(): refreshes += 1)
	view.resource_activated.connect(func(meta: Dictionary): navigated.append(meta))
	view.compose_requested.connect(func(meta: Dictionary): compositions.append(meta))
	root.add_child(view)
	await process_frame
	_check(view._camera != null and view._architecture.has("root"),
		"theatre is a native Camera3D with independent 3D stage")
	_check(view._meshes.size() == 4, "unobserved source creates only four unknown rigs")
	_check(view._graph["edges"].is_empty(), "no speculative links")
	_check(view._refresh_button != null, "real read-only refresh control exists")
	view._refresh_button.pressed.emit()
	_check(refreshes == 1, "pressing observe emits an owning Studio refresh request")
	var stamp := "2025-01-01T00:00:00Z"
	view.set_snapshot({
		"body_feed_state": "observed",
		"bodies": [
			{"body_id": "kilo-core-msi", "state": "reported_fresh",
				"observation": {"memory_available_bytes": 6442450944,
				"system_volume_free_bytes": 21474836480, "age_seconds": 9}}
		],
		"project_feed_state": "observed",
		"projects": [
			{"name": "Furyline", "path": "C:/dev/active/Furyline", "branch": "main"},
			{"name": "Kilo_Core", "path": "C:/dev/active/Kilo_Core", "branch": "master"}
		],
		"mission_feed_state": "observed",
		"missions": [
			{"id": "msn_012345abcdef", "title": "Evidence canary",
			"status": "running", "risk": "R2",
			"repo": "C:/dev/active/Furyline", "updated_at": stamp}
		],
		"service_feed_state": "observed",
		"services": [{"id": "studio", "name": "Studio", "status": "up"}]
	})
	await process_frame
	_check(view._meshes.size() == 8, "source graph shows four rigs, two projects, mission and service")
	_check(view._links.size() == 1 and view._links[0]["root"].visible,
		"only verified repo relation is rendered")
	_check(view._meshes["rig:kilo-core-msi"].has("label") and
		view._meshes["project:C:/dev/active/Furyline"].has("spin"),
		"geometry exposes domain shapes and label LOD")
	_check(view.select_key("rig:kilo-core-msi"), "physical body is selectable")
	_check(view._info.text.contains("6.0 GiB") and view._info.text.contains("NOT ADMITTED"),
		"measured body resources and denied work authority are visible")
	_check(view.select_key("project:C:/dev/active/Furyline"), "observed project is selectable")
	_check(view._meshes["project:C:/dev/active/Furyline"]["entry"].get("game", false),
		"game categorization only follows observed repository path")
	view._lens.select(5)
	view._apply_visibility()
	_check(view._meshes["project:C:/dev/active/Furyline"]["root"].visible,
		"game-specific lens reveals observed game repo")
	_check(not view._meshes["project:C:/dev/active/Kilo_Core"]["root"].visible,
		"game lens does not invent a Kilo_Core game")
	_check(not view._links[0]["root"].visible,
		"hidden relation endpoint hides its physical beam")
	_check(not view.select_key("mission:msn_012345abcdef"),
		"cannot pick a mission hidden behind filtered lens")
	view._lens.select(0)
	view._apply_visibility()
	_check(view.select_key("mission:msn_012345abcdef"), "source mission can be picked")
	view._focus_selected()
	_check(view._distance <= 7.5 and view._focus_target.distance_to(
		view._meshes["mission:msn_012345abcdef"]["root"].position) < 0.01,
		"dive puts camera focus at exact source object")
	view._open_selected()
	_check(navigated.size() == 1 and navigated[0].get("id") == "msn_012345abcdef",
		"3D selected mission opens verified source ID")
	view._compose_selected()
	_check(compositions.size() == 1 and compositions[0].get("risk") == "R0"
		and compositions[0].get("path") == "C:/dev/active/Furyline",
		"mission generates R0 only, guarded Studio composer context")
	view._time_check.button_pressed = true
	view._time_slider.value = 1.0
	view._apply_visibility()
	_check(not view._meshes["mission:msn_012345abcdef"]["root"].visible,
		"old time record is not represented as recent")
	_check(not view._links[0]["root"].visible,
		"4D source-age filter removes orphaned link")
	view.queue_free()
	await process_frame

	var app: Control = WORKSTATION.instantiate()
	app.auto_refresh = false
	root.add_child(app)
	await process_frame
	_check(app._pages.has("hyperspace:hyperspace"), "theatre is the real start scene")
	_check(not app._library_panel.visible and not app._inspector_panel.visible and
		not app._activity_panel.visible, "launch hides legacy dashboard docks")
	app._open_resource({"kind": "factory", "id": "factory", "name": "Software Factory"})
	await process_frame
	_check(app._library_panel.visible and app._inspector_panel.visible,
		"entering Studio tools restores accessible operator docks")
	app.queue_free()
	await process_frame
	if failures.is_empty():
		print("WORKSTATION_HOLODIVE_CONTRACT_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("WORKSTATION_HOLODIVE_CONTRACT_FAIL: " + failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
