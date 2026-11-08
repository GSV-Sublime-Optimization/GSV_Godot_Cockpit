extends SceneTree

const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(CATALOG.valid_mission_id("msn_012345abcdef"), "valid mission id")
	_check(not CATALOG.valid_mission_id("msn_hello/../../"), "path escape refused")
	_check(not CATALOG.valid_mission_id("msn_12345678"), "short id refused")
	var examples := {"missions": [{
		"id": "msn_012345abcdef",
		"title": "Test mission [b]not markup[/b]",
		"status": "awaiting_approval",
		"risk": "R2",
		"secret": "DO_NOT_RETAIN",
		"command": "DROP TABLE"
	}]}
	var result: Dictionary = CATALOG.parse_mission_list(JSON.stringify(examples))
	_check(result.get("ok", false), "typed mission allowed")
	if result.get("ok", false):
		var one: Dictionary = result["missions"][0]
		_check(one.get("interactive", true) == false, "observed mission is not a PTY")
		_check(one.get("session_kind", "") == "mission_log", "real trace surface")
		_check(not JSON.stringify(one).contains("DO_NOT_RETAIN"), "raw private fields dropped")
		_check(not JSON.stringify(one).contains("DROP TABLE"), "command field dropped")
	examples["missions"][0]["status"] = "invented_running"
	_check(not CATALOG.parse_mission_list(JSON.stringify(examples)).get("ok", false),
		"imaginary state refused")
	examples["missions"][0]["status"] = "proposed"
	examples["missions"].append(examples["missions"][0].duplicate(true))
	_check(not CATALOG.parse_mission_list(JSON.stringify(examples)).get("ok", false),
		"duplicate IDs refused")
	var log: Dictionary = CATALOG.parse_mission_log(
		JSON.stringify({"id": "msn_012345abcdef", "lines": ["[color=red]plain text[/color]", "OK"]}),
		"msn_012345abcdef"
	)
	_check(log.get("ok", false), "bounded mission log parsed")
	_check(not CATALOG.parse_mission_log(
		JSON.stringify({"id": "msn_aabbccddeeff", "lines": ["spoof"]}),
		"msn_012345abcdef"
	).get("ok", false), "cross-mission trace refused")
	_check(CATALOG.AGENTS.size() >= 9, "agent catalogue includes specialist tools")
	if failures.is_empty():
		print("WORKSTATION_CATALOG_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("WORKSTATION_CATALOG_FAIL: " + failure)
		quit(1)

func _check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
