extends SceneTree

## Active graphics must follow verified source work, never arbitrary "alive" shimmer.
const VIEW = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PanelContainer = VIEW.new()
	root.add_child(scene)
	await process_frame
	_check(not scene.is_processing(), "unknown colony consumes no per-frame animation budget")
	_check(scene._viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"unknown colony renders on invalidation, not continuously")
	var fixture := {
		"body_feed_state": "unknown", "bodies": [],
		"project_feed_state": "observed",
		"projects": [{"name": "Game", "path": "C:/dev/active/Game", "branch": "main"}],
		"mission_feed_state": "observed",
		"missions": [{"id": "msn_012345abcdef", "title": "Playtest",
			"status": "awaiting_approval", "risk": "R2", "repo": "C:/dev/active/Game"}],
		"service_feed_state": "unknown", "services": []
	}
	scene.set_snapshot(fixture)
	_check(scene._graph["edges"].size() == 1, "verified source link exists")
	_check(not scene._links[0]["packet"].visible, "pending approval shows no moving work packet")
	_check(not scene.is_processing(), "awaiting approval is not active execution")
	fixture["missions"][0]["status"] = "running"
	scene.set_snapshot(fixture)
	_check(scene._links[0]["packet"].visible and scene.is_processing(),
		"only observed running mission animates its exact repo-to-mission edge")
	var previous: Vector3 = scene._links[0]["packet"].position
	scene._process(0.14)
	_check(scene._links[0]["packet"].position != previous,
		"work packet follows its verified edge, a real animation not a status label")
	scene._lens.select(1)  # Fleet only: running mission physically invisible.
	scene._apply_visibility()
	_check(not scene._links[0]["root"].visible and not scene.is_processing(),
		"filtering away real work suspends active renderer")
	scene._lens.select(0)
	scene._apply_visibility()
	_check(scene.is_processing(), "restoring mission lane restores source-bound animation")
	fixture["missions"][0]["status"] = "succeeded"
	scene.set_snapshot(fixture)
	_check(not scene._links[0]["packet"].visible and not scene.is_processing(),
		"completed mission stops animated work without an invented executor")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("WORKSTATION_OBSERVED_ACTIVITY_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("WORKSTATION_OBSERVED_ACTIVITY_FAIL: " + failure)
		quit(1)

func _check(value: bool, reason: String) -> void:
	if not value:
		failures.append(reason)
