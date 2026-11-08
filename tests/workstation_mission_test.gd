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
		"Godot import is error-free\nLock-on regression test passes", "R2",
		"python -m pytest tests/test_lockon.py -q")
	_check(spec.get("ok", false), "valid mission envelope")
	if spec.get("ok", false):
		_check(spec["body"]["repo"] == "C:/dev/active/Furyline"
			and spec["body"]["base_branch"] == "main", "source-provided path and branch preserved")
		_check(spec["body"]["acceptance"].size() == 2, "acceptance parsed as two criteria")
		_check(spec["body"]["risk"] == "R2", "code scope has explicit human-gated risk")
		_check(spec["body"].get("validator") == "python -m pytest tests/test_lockon.py -q",
			"R2 mission carries predeclared validator")
	_check(not CONTRACT.make_spec(selected, "Repair weapon targeting",
		"Fix the observable target lock bug and add a negative control.",
		"One test", "R2").get("ok", false), "R2 without validator refused")
	_check(not CONTRACT.make_spec(selected, "Repair weapon targeting",
		"Fix the observable target lock bug and add a negative control.",
		"One test", "R2", "python -m pytest\nrm -rf .").get("ok", false),
		"multiline validator refused")
	_check(not CONTRACT.make_spec(selected, "Repair weapon targeting",
		"Fix the observable target lock bug and add a negative control.",
		"One test", "R0", "python -m pytest").get("ok", false),
		"lower-risk mission cannot declare a validator")
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
	_check(CONTRACT.parse_post_result(201, ack.replace("C:/dev/active/Furyline", "c:\\\\DEV\\\\active\\\\Furyline"),
		selected["path"], "R2").get("ok", false), "canonical Windows slash and case spellings match")
	_check(CONTRACT.parse_post_result(400, JSON.stringify({"error": "validator rejected"}),
		selected["path"], "R2").get("reason", "").contains("validator rejected"),
		"Studio HTTP 400 owner error is shown")
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
	desk._validator.text = "python -m pytest tests/test_lockon.py -q"
	desk._update_submit()
	_check(not desk._submit.disabled, "explicit selected fresh project can submit")
	desk._observed_at = Time.get_ticks_msec() - desk.FRESH_MS - 1
	desk._update_submit()
	_check(desk._submit.disabled, "stale project disables posting")
	desk._submit_mission()
	_check(not desk._post_busy, "stale project never starts POST")
	desk._observed_at = Time.get_ticks_msec()
	desk._update_submit()
	_check(not desk._submit.disabled, "fresh draft can submit")
	desk._expected_repo = selected["path"]
	desk._expected_risk = "R2"
	# A 200 or broken acknowledgement MAY have already stored a mission.
	# Never permit an automatic second POST without a separate operator act.
	desk._on_post_finished(HTTPRequest.RESULT_SUCCESS, 200,
		PackedStringArray(), PackedByteArray())
	_check(desk._submission_guard == "uncertain" and desk._submit.disabled,
		"ambiguous acknowledgement quarantines repeat POST")
	_check(desk._guard_action.visible and desk._guard_action.text.contains("RETRY"),
		"warning presents an explicit retry control")
	desk._submit_mission()
	_check(not desk._post_busy, "quarantine defeats programmatic duplicate POST")
	_check(desk._title.text == "Repair weapon targeting",
		"ambiguous failure preserves user draft")
	desk._release_submission_guard()
	_check(desk._submission_guard == "uncertain" and desk._submit.disabled,
		"manual retry cannot bypass the Studio index read")
	desk._on_index_finished(HTTPRequest.RESULT_SUCCESS, 500,
		PackedStringArray(), PackedByteArray())
	_check(desk._submission_guard == "uncertain" and desk._index_state == "not_checked",
		"failed owner GET leaves retry quarantined")
	desk._on_index_finished(HTTPRequest.RESULT_SUCCESS, 200,
		PackedStringArray(), JSON.stringify({"missions": []}).to_utf8_buffer())
	_check(desk._index_state == "observed_clear" and desk._submit.disabled,
		"source GET alone cannot authorize a second POST")
	desk._release_submission_guard()
	desk._update_submit()
	_check(desk._submission_guard == "draft" and not desk._submit.disabled,
		"fresh bounded owner index plus explicit action unlocks retry")
	# A clean 201 is also a one-shot transition. It cannot mint duplicate
	# missions from the same composer merely by clicking Submit again.
	desk._on_post_finished(HTTPRequest.RESULT_SUCCESS, 201,
		PackedStringArray(), ack.to_utf8_buffer())
	_check(desk._submission_guard == "acknowledged" and desk._submit.disabled,
		"successful creation locks repeat POST")
	_check(desk._ack_id == "msn_012345abcdef", "verified mission ID retained")
	desk._release_submission_guard()
	_check(desk._submission_guard == "draft" and desk._title.text.is_empty()
		and desk._objective.text.is_empty() and desk._acceptance.text.is_empty()
		and desk._validator.text.is_empty()
		and desk._project_select.get_selected_id() == 0,
		"new draft clears previous mission and requires explicit repo choice")
	# A matching task in the live owner index defeats retry, even if the POST's
	# response was lost. An operator can abandon it, never repeat it blindly.
	desk._submission_guard = "uncertain"
	desk._expected_repo = selected["path"]
	desk._expected_risk = "R2"
	desk._expected_title = "Repair weapon targeting"
	desk._expected_objective = "Fix the observable target lock bug and add a negative control."
	var existing := {"missions": [{"id": "msn_012345abcdef",
		"posted_by": "godot-workstation", "repo": selected["path"], "risk": "R2",
		"title": desk._expected_title, "objective": desk._expected_objective}]}
	desk._on_index_finished(HTTPRequest.RESULT_SUCCESS, 200,
		PackedStringArray(), JSON.stringify(existing).to_utf8_buffer())
	_check(desk._index_state == "conflict" and desk._submit.disabled
		and desk._ack_id == "msn_012345abcdef", "matching stored mission prevents duplicate POST")
	desk._release_submission_guard()
	_check(desk._submission_guard == "uncertain", "even manual unlock cannot bypass an index match")
	desk._on_guard_pressed()
	_check(desk._submission_guard == "draft" and desk._title.text.is_empty()
		and desk._project_select.get_selected_id() == 0,
		"conflict action abandons original request rather than retries it")
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
