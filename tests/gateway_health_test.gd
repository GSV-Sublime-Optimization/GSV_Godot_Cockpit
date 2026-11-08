extends SceneTree

## Pure negative controls + optional REAL local gateway health handshake.
##   godot --headless --path . --script res://tests/gateway_health_test.gd
##   GSV_GATEWAY_LIVE=1 [same command]   # only if the gateway serves :8001
const PROJECTION = preload("res://scripts/entity/GatewayHealthProjection.gd")
const BRIDGE = preload("res://scripts/entity/GatewayObservationBridge.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_expect(PROJECTION.parse_health("{}").get("reason", "") == "invalid_gateway_status",
		"missing status rejects closed")
	_expect(PROJECTION.parse_health("{broken").get("reason", "") == "malformed_json",
		"invalid JSON rejects closed")
	var good := JSON.stringify({"status": "ok", "secret": "do not retain this"})
	var parsed: Dictionary = PROJECTION.parse_health(good)
	_expect(parsed.get("ok", false), "ok status accepted")
	if parsed.get("ok", false):
		var observation: Dictionary = parsed["observation"]
		_expect(observation.get("state", "") == "live", "ok status is live")
		_expect(observation.get("gateway_status", "") == "ok", "typed gateway status projected")
		_expect(not JSON.stringify(observation).contains("do not retain"),
			"payload secrets excluded")
		_expect(not observation.has("secret"), "unapproved raw data never reaches scene")
	var degraded := JSON.stringify({"status": "degraded"})
	var down: Dictionary = PROJECTION.parse_health(degraded)
	_expect(down.get("ok", false), "non-ok status parses")
	if down.get("ok", false):
		_expect(down["observation"].get("state", "") == "unavailable",
			"non-ok status is honestly unavailable")
		_expect(down["observation"].get("error", "") == "gateway_not_ok",
			"unavailable carries a fixed reason")
	var bridge: Node = BRIDGE.new()
	root.add_child(bridge)
	await process_frame
	_expect(bridge.current_observation().get("state") == "unknown",
		"no synthetic live state before a request")
	if OS.get_environment("GSV_GATEWAY_LIVE") == "1":
		_expect(bridge.observe(), "real gateway GET dispatched")
		var update: Dictionary = await bridge.observation_changed
		_expect(update.get("state") == "live", "real gateway protocol observation")
		_expect(update.get("gateway_status", "") == "ok", "real gateway reports ok")
		_expect(not update.has("secret"), "real response bounded to projection")
	bridge.queue_free()
	if failures.is_empty():
		print("GATEWAY_HEALTH_PASS")
		quit(0)
	else:
		for item in failures:
			printerr("GATEWAY_HEALTH_FAIL: " + item)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
