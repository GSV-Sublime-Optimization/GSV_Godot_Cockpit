extends SceneTree

## Optional PHYSICAL GPU capture of real READ-ONLY GitHub export.
## Does not mutate PRs; Fleet/Studio states remain unobserved unless fetched.
const SCENE = preload("res://scenes/ColonyWorkstation.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	var app: Control = SCENE.instantiate()
	app.auto_refresh = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var page: Control = app._pages.get("hyperspace:hyperspace", null)
	if page == null or page.get_child_count() != 1:
		printerr("CAPTURE_NO_THEATRE")
		quit(2)
		return
	var space: Node = page.get_child(0)
	if space._review_rows.is_empty():
		printerr("CAPTURE_NO_FRESH_REVIEW_SOURCE")
		quit(2)
		return
	space._lens.select(7)
	space._on_lens_selected(7)
	var first: Dictionary = space._review_rows[0]
	if not space.select_key("review:" + String(first["key"])):
		printerr("CAPTURE_PR_UNSELECTABLE")
		quit(1)
		return
	# Keep the entire review gate visible; selected source is emphasized by halo.
	space._update_label_lod()
	var marker := Label.new()
	marker.text = "REAL GITHUB READ-ONLY EXPORT / NO EXECUTION / FLEET UNOBSERVED"
	marker.position = Vector2(16, 846)
	marker.add_theme_color_override("font_color", Color("#ffc987"))
	marker.add_theme_font_size_override("font_size", 15)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(marker)
	for frame in 45:
		await process_frame
	var output := "res://receipts/review-gate-live-msi.png"
	var path := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var rc := root.get_texture().get_image().save_png(path)
	print("REVIEW_GATE_GPU_CAPTURE " + path + " exit=" + str(rc))
	quit(0 if rc == OK else 1)
