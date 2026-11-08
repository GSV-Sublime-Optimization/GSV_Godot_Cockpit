extends SceneTree

const DESK = preload("res://scripts/workstation/WorkbenchMissionDesk.gd")
const PANE = preload("res://scripts/workstation/WorkbenchSessionPane.gd")
var errors: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var evidence: Dictionary = {}
	var desk: PanelContainer = DESK.new()
	desk.mission_submitted.connect(func(id: String, state: String):
		evidence["id"] = id
		evidence["state"] = state
	)
	root.add_child(desk)
	await process_frame
	_expect(desk._submit.disabled, "before observation is not submittable")
	for i in range(160):
		if desk._projects_state == "observed":
			break
		await create_timer(0.05).timeout
	_expect(desk._projects_state == "observed", "fixture Studio discovery observed")
	_expect(desk._submit.disabled, "project is never preselected")
	if desk._projects.size() != 1:
		errors.append("expected exactly one eligible Git project")
	else:
		desk._project_select.select(1)
		desk._title.text = "Build fixture mission from Godot"
		desk._objective.text = "Implement the authorized fixture mission and verify exact evidence."
		desk._acceptance.text = "Exact-head import passes\nFixture acceptance passes"
		desk._risk.select(2)
		desk._update_submit()
		_expect(not desk._submit.disabled, "operator-filled R2 envelope enabled")
		desk._submit_mission()
		_expect(desk._post_busy, "actual HTTP POST was initiated")
		for i in range(160):
			if not desk._post_busy:
				break
			await create_timer(0.05).timeout
		_expect(evidence.get("id", "") == "msn_012345abcdef",
			"real loopback POST acknowledged expected mission")
		_expect(evidence.get("state", "") == "awaiting_approval",
			"human approval state preserved")
		_expect(desk._response.text.contains("NOT proof of a running agent"),
			"acknowledged is not fabricated build completion")
		_expect(desk._view_mission.visible, "acknowledged mission can request an indexed view")
		var pane: PanelContainer = PANE.new()
		pane.configure({"session_kind": "mission_log", "id": evidence.get("id", ""),
			"name": "Fixture Mission", "status": "awaiting_approval"}, null)
		root.add_child(pane)
		await process_frame
		pane.refresh_evidence()
		for i in range(160):
			if not pane._read_evidence.disabled:
				break
			await create_timer(0.05).timeout
		_expect(pane._terminal.text.contains("rcpt_fixture_ack_0001"),
			"same mission receipt inspected through real HTTP GET")
		_expect(pane._terminal.text.contains("1/1 acceptance criteria met"),
			"source result is presented as evidence, not a fabricated terminal")
		pane.queue_free()
	desk.queue_free()
	await process_frame
	if errors.is_empty():
		print("WORKSTATION_MISSION_TRANSPORT_PASS")
		quit(0)
	else:
		for err in errors:
			printerr("WORKSTATION_MISSION_TRANSPORT_FAIL: " + err)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		errors.append(label)
