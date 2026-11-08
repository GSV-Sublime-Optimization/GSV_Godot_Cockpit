extends SceneTree

## Pure negative controls + optional REAL local Studio constellation handshake.
##   godot --headless --path . --script res://tests/studio_constellation_test.gd
##   GSV_STUDIO_LIVE=1 [same command]   # only if Studio already serves :7340
## The live canary is SLOW by nature: the Studio /api/projects scan takes
## ~15s to answer (its own backend times out after 15s), so the bridge uses
## a 20s timeout and a 120s cached refresh. The canary accepts either a live
## constellation or an honest unavailable (scan timed out) — never a
## fabricated live with null projects.
const PROJECTION = preload("res://scripts/entity/StudioProjectsProjection.gd")
const BRIDGE = preload("res://scripts/entity/StudioConstellationBridge.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_expect(PROJECTION.parse_projects("{}").get("reason", "") == "unknown_projects_schema",
		"unknown schema rejects closed")
	_expect(PROJECTION.parse_projects("{broken").get("reason", "") == "malformed_json",
		"invalid JSON rejects closed")
	var good := JSON.stringify({
		"schema": "kilocore-studio.projects-scan.v2",
		"generated_at": "2026-11-08T05:59:56.338841+00:00",
		"state": "OK",
		"source": "Kilo_Core Project Constellation",
		"reason": "",
		"workspace_root": "C:/dev/active",
		"count": 2,
		"projects": [
			{"name": "Furyline", "status": "active", "secret": "do not retain this"},
			{"name": "Bastion", "status": "active"}
		],
		"constellation_schema": "v2",
		"secret": "do not retain this"
	})
	var parsed: Dictionary = PROJECTION.parse_projects(good)
	_expect(parsed.get("ok", false), "known projects schema accepted")
	if parsed.get("ok", false):
		var observation: Dictionary = parsed["observation"]
		_expect(observation.get("state", "") == "live", "complete constellation is live")
		_expect(observation.get("project_count", -1) == 2, "typed project count projected")
		_expect(observation.get("projects", []).size() == 2, "bounded project summaries admitted")
		_expect(not JSON.stringify(observation).contains("do not retain"),
			"payload secrets excluded")
		_expect(not observation.has("secret") and not observation.has("workspace_root"),
			"unapproved raw data never reaches scene")
	var scan_failed := JSON.stringify({
		"schema": "kilocore-studio.projects-scan.v2",
		"generated_at": "2026-11-08T05:59:56.338841+00:00",
		"state": "UNKNOWN",
		"source": "Kilo_Core Project Constellation",
		"reason": "scan timed out after 15.0 seconds",
		"workspace_root": "C:/dev/active",
		"count": null,
		"projects": null,
		"constellation_schema": null
	})
	var failed: Dictionary = PROJECTION.parse_projects(scan_failed)
	_expect(failed.get("ok", false), "scan-failed envelope parses")
	if failed.get("ok", false):
		_expect(failed["observation"].get("state", "") == "unavailable",
			"scan with null projects is honestly unavailable")
		_expect(failed["observation"].get("error", "") == "constellation_scan_unavailable",
			"unavailable carries a fixed reason")
	var bad_count := JSON.stringify({
		"schema": "kilocore-studio.projects-scan.v2",
		"generated_at": "2026-11-08T05:59:56.338841+00:00",
		"state": "OK",
		"source": "Kilo_Core Project Constellation",
		"reason": "",
		"count": -1,
		"projects": []
	})
	_expect(not PROJECTION.parse_projects(bad_count).get("ok", false),
		"negative project counts rejected")
	var many := []
	for i in 60:
		many.append({"name": "project-%d" % i, "status": "active"})
	var overflow := JSON.stringify({
		"schema": "kilocore-studio.projects-scan.v2",
		"generated_at": "2026-11-08T05:59:56.338841+00:00",
		"state": "OK",
		"source": "Kilo_Core Project Constellation",
		"reason": "",
		"count": 60,
		"projects": many
	})
	var capped: Dictionary = PROJECTION.parse_projects(overflow)
	_expect(capped.get("ok", false), "oversized project list parses")
	if capped.get("ok", false):
		_expect(capped["observation"].get("projects", []).size() == 50,
			"project summaries capped at 50")
		_expect(capped["observation"].get("projects_skipped", -1) == 10,
			"overflow counted as skipped")
	var bridge: Node = BRIDGE.new()
	root.add_child(bridge)
	await process_frame
	_expect(bridge.current_observation().get("state") == "unknown",
		"no synthetic live state before a request")
	_expect(bridge.observe(), "constellation GET dispatched")
	_expect(not bridge.observe(), "one request in flight; second observe skipped")
	await process_frame
	_expect(bridge.current_observation().get("state") != "live",
		"no live state before the first response lands")
	if OS.get_environment("GSV_STUDIO_LIVE") == "1":
		var update: Dictionary = await bridge.observation_changed
		_expect(update.get("state") in ["live", "unavailable", "stale"],
			"real constellation observation is an honest state")
		if update.get("state") == "live":
			_expect(update.get("project_count", -1) >= 0, "live means a real count")
			_expect(update.get("projects", []).size() <= 50, "live projects bounded")
		if update.get("state") == "unavailable":
			_expect(not update.has("secret"), "unavailable response bounded to projection")
		_expect(not bridge.observe(), "cached sensor refuses a second fetch inside its refresh window")
		_expect(bridge.observe(true), "forced observe bypasses the refresh window")
	bridge.queue_free()
	if failures.is_empty():
		print("STUDIO_CONSTELLATION_PASS")
		quit(0)
	else:
		for item in failures:
			printerr("STUDIO_CONSTELLATION_FAIL: " + item)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
