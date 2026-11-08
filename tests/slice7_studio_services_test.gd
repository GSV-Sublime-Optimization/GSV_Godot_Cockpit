extends SceneTree

## Slice 7 Studio services tests: the health projection admits the
## 4-service colony_observation the /api/health feed already carries
## (dispatch / lattice-model-router / NuSyQ-Hub / OpenClaw) — the thin
## Studio card fix (Slice 6 §3.1). Old health-only responses still parse.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/slice7_studio_services_test.gd
##
## Exit 0 = pass, 1 = fail.
## Also run by tests/godot_smoke_gate.py as the "slice7-studio" case.

const PROJECTION = preload("res://scripts/entity/StudioHealthProjection.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_services_admitted()
	_check_health_only_still_parses()
	_check_unknown_label_rejected()
	_check_wrong_schema_rejected()
	_finish()


func _health_with_observation() -> String:
	return """{
		"schema": "kilocore-studio.cockpit-health.v2",
		"missions": {"awaiting": 1, "running": 0, "queued": 0, "thermal_gate": "open"},
		"colony_observation": {
			"available": true, "state": "OBSERVED",
			"presentation": {
				"headline": "4 services; 0 contradictions; 0 unknowns",
				"service_labels": {
					"dispatch": "OBSERVED",
					"lattice-model-router": "READY",
					"nusyq-hub": "DEGRADED",
					"openclaw": "OBSERVED"
				}
			}
		}
	}"""


func _check_services_admitted() -> void:
	var parsed := PROJECTION.parse_health(_health_with_observation())
	if not bool(parsed.get("ok", false)):
		_fail("health with colony_observation rejected: %s" % String(parsed.get("reason", "?")))
		return
	var obs: Dictionary = parsed["observation"]
	var services: Array = obs.get("services", [])
	if services.size() != 4:
		_fail("services admitted: %d, expected 4" % services.size())
		return
	var by_id := {}
	for svc in services:
		by_id[String(svc.get("id", ""))] = svc
	if String(by_id.get("dispatch", {}).get("state", "")) != "live":
		_fail("dispatch OBSERVED did not map to live")
	if String(by_id.get("lattice-model-router", {}).get("state", "")) != "live":
		_fail("lattice-model-router READY did not map to live")
	if String(by_id.get("nusyq-hub", {}).get("state", "")) != "degraded":
		_fail("nusyq-hub DEGRADED did not map to degraded")
	if String(by_id.get("openclaw", {}).get("state", "")) != "live":
		_fail("openclaw OBSERVED did not map to live")
	if String(obs.get("colony_headline", "")).find("4 services") < 0:
		_fail("colony headline missing: %s" % String(obs.get("colony_headline", "")))
	if int(obs.get("mission_counts", {}).get("awaiting", -1)) != 1:
		_fail("mission counts lost when services admitted")


func _check_health_only_still_parses() -> void:
	var text := """{
		"schema": "kilocore-studio.cockpit-health.v2",
		"missions": {"awaiting": 0, "running": 0, "queued": 0, "thermal_gate": "open"}
	}"""
	var parsed := PROJECTION.parse_health(text)
	if not bool(parsed.get("ok", false)):
		_fail("health-only response rejected: %s" % String(parsed.get("reason", "?")))
		return
	var obs: Dictionary = parsed["observation"]
	if not (obs.get("services", []) as Array).is_empty():
		_fail("health-only response gained services")
	if String(obs.get("colony_headline", "?")) != "":
		_fail("health-only response gained a headline")


func _check_unknown_label_rejected() -> void:
	var text := _health_with_observation().replace('"DEGRADED"', '"SPARKLING"')
	var parsed := PROJECTION.parse_health(text)
	if bool(parsed.get("ok", false)):
		_fail("unknown service label SPARKLING accepted — fail-closed required")
	elif String(parsed.get("reason", "")) != "unknown_service_label":
		_fail("unknown label rejected with the wrong reason: %s" % String(parsed.get("reason", "")))


func _check_wrong_schema_rejected() -> void:
	var text := _health_with_observation().replace("kilocore-studio.cockpit-health.v2", "other.v9")
	if bool(PROJECTION.parse_health(text).get("ok", false)):
		_fail("wrong health schema accepted")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[slice7-test] PASS")
		quit(0)
		return
	for message in _failures:
		printerr("[slice7-test] FAIL: %s" % message)
	print("[slice7-test] FAILED (%d)" % _failures.size())
	quit(1)
