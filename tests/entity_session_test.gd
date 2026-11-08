extends SceneTree

## Verify the embodied session cannot turn observation into authority.
const SESSION = preload("res://scripts/entity/EntitySession.gd")
const SCENE = preload("res://scenes/EntitySession.tscn")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var session: Node = SESSION.new()
	root.add_child(session)
	await process_frame
	var model: Dictionary = session.self_model()
	_check(model.get("schema", "") == "kilocore.entity-session.v0", "typed session")
	_check(model.get("phase", "") == "observation_only", "truthful stage")
	_check(model.get("authorized_actuators", ["bad"]).is_empty(), "no stealth actuators")
	_check(model.get("sensor", {}).get("state", "") == "unknown", "unobserved is unknown")
	# Inject observations into the session event *aggregation* only.
	# These are explicitly fixtures, not evidence the fleet was contacted.
	for i in 70:
		session._on_studio_observation({
			"source": "fixture",
			"state": "stale",
			"error": "offline"
		})
	_check(session.recent_events().size() == 64, "bounded event history")
	_check(session.self_model().get("local_history_events", -1) == 64, "history accounted")
	_check(SCENE != null, "headless-loadable autoconnect scene")
	session.queue_free()
	if failures.is_empty():
		print("ENTITY_SESSION_PASS")
		quit(0)
	else:
		for item in failures:
			printerr("ENTITY_SESSION_FAIL: " + item)
		quit(1)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
