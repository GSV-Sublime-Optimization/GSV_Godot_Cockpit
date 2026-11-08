extends SceneTree

## Pure negative controls + optional REAL local Studio R0 protocol handshake.
##   godot --headless --path . --script res://tests/studio_entity_bridge_test.gd
##   GSV_STUDIO_LIVE=1 [same command]   # only if Studio already serves :7340
const PROJECTION = preload("res://scripts/entity/StudioHealthProjection.gd")
const BRIDGE = preload("res://scripts/entity/StudioObservationBridge.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_expect(PROJECTION.parse_health("{}").get("reason", "") == "unknown_health_schema",
		"unknown schema rejects closed")
	_expect(PROJECTION.parse_health("{broken").get("reason", "") == "malformed_json",
		"invalid JSON rejects closed")
	var good := JSON.stringify({
		"schema": "kilocore-studio.cockpit-health.v2",
		"missions": {
			"awaiting": 2, "running": 1, "queued": 0, "thermal_gate": "open",
			"secret": "do not retain this", "executor": {"auth": "secret"}
		},
		"secret": "do not retain this"
	})
	var parsed: Dictionary = PROJECTION.parse_health(good)
	_expect(parsed.get("ok", false), "known health schema accepted")
	if parsed.get("ok", false):
		var observation: Dictionary = parsed["observation"]
		_expect(observation.get("mission_counts", {}).get("awaiting", -1) == 2,
			"typed mission counts projected")
		_expect(not observation.has("secret") and not observation.has("executor"),
			"unapproved raw data never reaches scene")
		_expect(not JSON.stringify(observation).contains("do not retain"),
			"payload secrets excluded")
	var bad := JSON.stringify({
		"schema": "kilocore-studio.cockpit-health.v2",
		"missions": {"awaiting": -1, "running": 0, "queued": 0, "thermal_gate": "open"}
	})
	_expect(not PROJECTION.parse_health(bad).get("ok", false),
		"negative mission counts rejected")
	var bridge: Node = BRIDGE.new()
	root.add_child(bridge)
	await process_frame
	_expect(bridge.current_observation().get("state") == "unknown",
		"no synthetic live state before a request")
	if OS.get_environment("GSV_STUDIO_LIVE") == "1":
		_expect(bridge.observe(), "real health GET dispatched")
		var update: Dictionary = await bridge.observation_changed
		_expect(update.get("state") == "live", "real Studio protocol observation")
		_expect(update.get("schema") == PROJECTION.EXPECTED_SCHEMA,
			"real response matches typed schema")
		_expect(not update.has("secret"), "real response bounded to projection")
	bridge.queue_free()
	if failures.is_empty():
		print("STUDIO_ENTITY_BRIDGE_PASS")
		quit(0)
	else:
		for item in failures:
			printerr("STUDIO_ENTITY_BRIDGE_FAIL: " + item)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
