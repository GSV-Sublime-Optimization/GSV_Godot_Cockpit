extends SceneTree

const CONTRACT = preload("res://scripts/workstation/WorkbenchMissionContract.gd")
const DESK = preload("res://scripts/workstation/WorkbenchMissionDesk.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var target := {"name": "Furyline", "path": "C:/dev/active/Furyline",
		"git": {"is_repo": true, "branch": "main"}}
	var good := JSON.stringify({"schema": CONTRACT.PROJECT_SCHEMA,
		"state": "OBSERVED", "projects": [target,
		{"name": "not git", "path": "C:/tmp/no-repo", "git": {"is_repo": false}}]})
	var scanned: Dictionary = CONTRACT.parse_projects(good)
	_check(scanned.get("ok", false) and scanned["projects"].size() == 1,
		"only observed Git repositories are eligible")
	_check(not CONTRACT.parse_projects(good.replace("OBSERVED", "UNKNOWN")).get("ok", false),
		"unknown discovery cannot authorize")
	_check(not CONTRACT.parse_projects(good.replace(CONTRACT.PROJECT_SCHEMA, "wrong")).get("ok", false),
		"wrong schema cannot authorize")
	_check(not CONTRACT.parse_projects(JSON.stringify({"schema": CONTRACT.PROJECT_SCHEMA,
		"state": "OBSERVED", "projects": [target, target]})).get("ok", false),
		"duplicate paths fail closed")
	var selected: Dictionary = scanned["projects"][0]
	var spec: Dictionary = CONTRACT.make_spec(selected, "Repair weapon targeting",
		"Fix the observable target lock bug and add a negative control.",
		"Godot import is error-free\nLock-on regression test passes", "R2")
	_check(spec.get("ok", false), "valid mission envelope")
	if spec.get("ok", false):
		_check(spec["body"]["repo"] == "C:/dev/active/Furyline"
			and spec["body"]["base_branch"] == "main", "source-provided path and branch preserved")
		_check(spec["body"]["acceptance"].size() == 2, "acceptance parsed as two criteria")
		_check(spec["body"]["risk"] == "R2", "code scope has explicit human-gated risk")
	_check(not CONTRACT.make_spec(selected, "Patch", "too short", "", "R2").get("ok", false),
		"empty acceptance and short objective refused")
	_check(not CONTRACT.make_spec(selected, "Repair weapon targeting",
		"Fix the observable target lock bug and add a negative control.",
		"One test", "R3").get("ok", false), "R3 cannot be submitted from this view")
	var ack := JSON.stringify({"id": "msn_012345abcdef", "status": "awaiting_approval",
		"repo": selected["path"], "risk": "R2"})
	var accepted: Dictionary = CONTRACT.parse_post_result(201, ack, selected["path"], "R2")
	_check(accepted.get("ok", false) and accepted.get("needs_approval", false),
		"exact accepted R2 acknowledgement")
	_check(not CONTRACT.parse_post_result(200, ack, selected["path"], "R2").get("ok", false),
		"HTTP 200 is not creation")
	_check(not CONTRACT.parse_post_result(201, ack, "C:/dev/other", "R2").get("ok", false),
		"cross-repository spoof refused")
	_check(not CONTRACT.parse_post_result(201, ack.replace("msn_012345abcdef", "msn_bad"),
		selected["path"], "R2").get("ok", false), "invalid mission ID refused")
	var desk: PanelContainer = DESK.new()
	desk.auto_discover = false
	root.add_child(desk)
	await process_frame
	_check(desk._submit.disabled, "first paint never enables submit")
	desk._install_projects(scanned["projects"])
	_check(desk._submit.disabled, "no silent default project selection")
	desk._project_select.select(1)
	desk._title.text = "Repair weapon targeting"
	desk._objective.text = "Fix the observable target lock bug and add a negative control."
	desk._acceptance.text = "Godot import is error-free\nLock-on regression passes"
	desk._update_submit()
	_check(not desk._submit.disabled, "explicit selected fresh project can submit")
	desk._observed_at = Time.get_ticks_msec() - desk.FRESH_MS - 1
	desk._update_submit()
	_check(desk._submit.disabled, "stale project disables posting")
	desk._submit_mission()
	_check(not desk._post_busy, "stale project never starts POST")
	desk.queue_free()
	await process_frame
	if failures.is_empty():
		print("WORKSTATION_MISSION_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("WORKSTATION_MISSION_FAIL: " + failure)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
