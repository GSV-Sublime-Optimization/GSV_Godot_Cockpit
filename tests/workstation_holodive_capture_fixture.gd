extends SceneTree

## A GPU screenshot fixture. Entire feed is deliberately synthetic test data.
## Does not contact Studio, probe rigs, spawn agents, or create missions.
const WORKSTATION = preload("res://scenes/ColonyWorkstation.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	var app: Control = WORKSTATION.instantiate()
	app.auto_refresh = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var observed := Time.get_datetime_string_from_system(true, true).replace(" ", "T")
	observed = observed.substr(0, 19) + "Z"
	var synthetic: Dictionary = {
		"body_feed_state": "observed",
		"bodies": [
			{"body_id": "kilo-core-msi", "state": "reported_fresh",
				"observation": {"memory_available_bytes": 9 * 1073741824,
					"system_volume_free_bytes": 45 * 1073741824, "age_seconds": 30}},
			{"body_id": "desktop-i3anuvp", "state": "stale",
				"observation": {"memory_available_bytes": 2 * 1073741824,
					"system_volume_free_bytes": 20 * 1073741824, "age_seconds": 2500}},
			{"body_id": "desktop-l9v3emb", "state": "unknown"},
			{"body_id": "imac-xanadu", "state": "unknown"}
		],
		"project_feed_state": "observed",
		"projects": [
			{"name": "Furyline", "path": "C:/dev/active/Furyline", "branch": "main"},
			{"name": "Ash-and-Anvil", "path": "C:/dev/active/Ash-and-Anvil", "branch": "main"},
			{"name": "GSV_Godot_Cockpit", "path": "C:/dev/active/GSV_Godot_Cockpit", "branch": "master"},
			{"name": "Kilo_Core", "path": "C:/dev/active/Kilo_Core", "branch": "master"},
			{"name": "KiloCore-Studio", "path": "C:/dev/active/KiloCore-Studio", "branch": "main"},
			{"name": "FleetBridge", "path": "C:/dev/active/FleetBridge", "branch": "main"}
		],
		"mission_feed_state": "observed",
		"missions": [
			{"id": "msn_012345abcdef", "title": "Furyline / targeting", "risk": "R2",
				"status": "running", "repo": "C:/dev/active/Furyline", "updated_at": observed},
			{"id": "msn_012345abcdee", "title": "Forge / playtest", "risk": "R2",
				"status": "awaiting_approval", "repo": "C:/dev/active/Ash-and-Anvil", "updated_at": observed},
			{"id": "msn_012345abcdec", "title": "Studio / evidence", "risk": "R0",
				"status": "succeeded", "repo": "C:/dev/active/KiloCore-Studio", "updated_at": observed}
		],
		"service_feed_state": "observed",
		"services": [
			{"id": "studio", "name": "Studio", "status": "ok"},
			{"id": "gateway", "name": "Gateway", "status": "degraded"},
			{"id": "fleetbridge", "name": "Fleet Bridge", "status": "ok"},
			{"id": "mempalace", "name": "MemPalace", "status": "down"}
		]
	}
	app._on_snapshot(synthetic)
	var page: PanelContainer = app._pages.get("hyperspace:hyperspace")
	var space: PanelContainer = page.get_child(0)
	space.set_snapshot(synthetic)
	if space._graph.get("nodes", []).size() < 13:
		printerr("FIXTURE_HOLODIVE_BAD_GRAPH")
		quit(1)
		return
	space.select_key("mission:msn_012345abcdef")
	var watermark := Label.new()
	watermark.text = "SYNTHETIC VISUAL FIXTURE  /  NOT LIVE FLEET STATUS"
	watermark.position = Vector2(20, 848)
	watermark.add_theme_font_size_override("font_size", 20)
	watermark.add_theme_color_override("font_color", Color("#ffb569"))
	watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(watermark)
	for frame in 45:
		await process_frame
	var destination := "res://receipts/holodive-visual-fixture.png"
	var absolute := ProjectSettings.globalize_path(destination)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var status := root.get_texture().get_image().save_png(absolute)
	print("HOLODIVE_GPU_FIXTURE " + absolute + " SAVE " + str(status))
	quit(0 if status == OK else 1)
