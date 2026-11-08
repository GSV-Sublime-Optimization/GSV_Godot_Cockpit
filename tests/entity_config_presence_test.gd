extends SceneTree

## Verify session configuration bounds and the visible status readout.
## No live services needed: the readout is honest about unknown states.
const SESSION = preload("res://scripts/entity/EntitySession.gd")
const SCENE = preload("res://scenes/EntitySession.tscn")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var session: Node = SESSION.new()
	session.observe_period_seconds = 0.5
	session.constellation_period_seconds = 10.0
	session.max_history_events = 2
	root.add_child(session)
	await process_frame
	_expect(session.observe_period_seconds == 2.0, "tick period clamps to its floor")
	_expect(session.constellation_period_seconds == 60.0, "constellation period clamps to its floor")
	_expect(session.max_history_events == 8, "history bound clamps to its floor")
	session.observe_period_seconds = 999.0
	session.constellation_period_seconds = 9999.0
	session.max_history_events = 5000
	_expect(session.observe_period_seconds == 300.0, "tick period clamps to its ceiling")
	_expect(session.constellation_period_seconds == 3600.0, "constellation period clamps to its ceiling")
	_expect(session.max_history_events == 1024, "history bound clamps to its ceiling")
	session.max_history_events = 8
	var text: String = session.status_text()
	_expect(text.contains("observation_only"), "readout names the phase honestly")
	_expect(text.contains("actuators 0"), "readout states zero actuators")
	_expect(text.contains("STUDIO unknown"), "readout is honest before observation")
	_expect(text.contains("GATEWAY unknown"), "gateway readout is honest before observation")
	_expect(text.contains("CONSTELLATION unknown"), "constellation readout is honest before observation")
	_expect(not text.contains("secret"), "readout carries no secrets")
	for i in 12:
		session._on_studio_observation({"source": "fixture", "state": "stale", "error": "offline"})
	_expect(session.recent_events().size() == 8, "history bounded at the clamped max")
	# The readout reads the sensor bridge, not the event trace: drive the real
	# bridge path (one good health reply, then a transport failure) to go stale.
	var good := JSON.stringify({"schema": "kilocore-studio.cockpit-health.v2",
		"missions": {"awaiting": 1, "running": 0, "queued": 0, "thermal_gate": "open"}})
	session._sensor._on_request_completed(HTTPRequest.RESULT_SUCCESS, 200,
		PackedStringArray(), good.to_utf8_buffer())
	session._sensor._on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0,
		PackedStringArray(), PackedByteArray())
	_expect(session.status_text().contains("STUDIO stale"), "readout follows the latest observation")
	var body: Node = SCENE.instantiate()
	root.add_child(body)
	await process_frame
	var readout: Label = body.get_node_or_null("StatusReadout") as Label
	_expect(readout != null, "scene carries a visible status readout")
	if readout != null:
		_expect(not readout.text.is_empty(), "readout has text on load")
		_expect(readout.text.contains("observation_only"), "scene readout names the phase")
	body.queue_free()
	session.queue_free()
	if failures.is_empty():
		print("ENTITY_CONFIG_PRESENCE_PASS")
		quit(0)
	else:
		for item in failures:
			printerr("ENTITY_CONFIG_PRESENCE_FAIL: " + item)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
