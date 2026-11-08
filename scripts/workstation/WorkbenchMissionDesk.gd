extends PanelContainer

## Explicit, one-shot operator mission composer for the existing Studio mission store.
## No shell, agent spawn, auto-approval, merge, arbitrary URLs, or remembered credentials.
## R2 edits wait for Studio's independent human approval.

signal mission_submitted(mission_id: String, state: String)
signal mission_view_requested(mission_id: String)

@export var auto_discover: bool = true

const CONTRACT = preload("res://scripts/workstation/WorkbenchMissionContract.gd")
const FRESH_MS := 45000

var _project_http: HTTPRequest
var _post_http: HTTPRequest
var _project_select: OptionButton
var _project_state: Label
var _title: LineEdit
var _objective: TextEdit
var _acceptance: TextEdit
var _risk: OptionButton
var _submit: Button
var _view_mission: Button
var _guard_action: Button
var _response: RichTextLabel
var _ack_id := ""
var _projects: Array[Dictionary] = []
var _projects_state := "unknown"
var _observed_at := 0
var _projects_busy := false
var _post_busy := false
# An acknowledged or ambiguous POST is a one-shot boundary.
# A retry requires a separate deliberate operator interaction.
var _submission_guard := "draft"
var _expected_repo := ""
var _expected_risk := ""
var _port := 7340

func _ready() -> void:
	var supplied := OS.get_environment("GSV_STUDIO_ENTITY_PORT")
	if supplied.is_valid_int() and not supplied.is_empty():
		var numeric := int(supplied)
		if numeric >= 1 and numeric <= 65535:
			_port = numeric
	_project_http = HTTPRequest.new()
	_project_http.timeout = 9.0
	_project_http.max_redirects = 0
	add_child(_project_http)
	_project_http.request_completed.connect(_on_projects_finished)
	_post_http = HTTPRequest.new()
	_post_http.timeout = 8.0
	_post_http.max_redirects = 0
	add_child(_post_http)
	_post_http.request_completed.connect(_on_post_finished)
	_build()
	var clock := Timer.new()
	clock.wait_time = 1.0
	clock.autostart = true
	clock.timeout.connect(_update_submit)
	add_child(clock)
	if auto_discover:
		call_deferred("_refresh_projects")

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 11)
	scroll.add_child(column)
	var heading := Label.new()
	heading.text = "SOFTWARE FACTORY  /  REAL STUDIO MISSION"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color("#7cddf6"))
	column.add_child(heading)
	var doctrine := Label.new()
	doctrine.text = ("One project. One explicit objective. An owned worktree and evidence-bearing mission. "
		+ "Current executor admission is controlled by Studio, not by the selected agent seat. "
		+ "R2 code edits require a separate human approval in Studio.")
	doctrine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(doctrine)

	var picker_row := HBoxContainer.new()
	column.add_child(picker_row)
	var repo_label := Label.new()
	repo_label.text = "TARGET REPOSITORY"
	repo_label.custom_minimum_size.x = 170
	picker_row.add_child(repo_label)
	_project_select = OptionButton.new()
	_project_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_project_select.item_selected.connect(func(_index): _update_submit())
	picker_row.add_child(_project_select)
	var refresh := Button.new()
	refresh.text = "SCAN PROJECTS"
	refresh.tooltip_text = "Read-only, single-flight canonical project discovery via local Studio"
	refresh.pressed.connect(_refresh_projects)
	picker_row.add_child(refresh)

	_project_state = Label.new()
	_project_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_project_state.text = "PROJECT SOURCE UNKNOWN. Submission disabled until observed."
	column.add_child(_project_state)
	_title = LineEdit.new()
	_title.placeholder_text = "Mission title (6-120 characters)"
	_title.max_length = 120
	_title.text_changed.connect(func(_value): _update_submit())
	column.add_child(_title)
	var objective_label := Label.new()
	objective_label.text = "OBJECTIVE   /   desired working change"
	column.add_child(objective_label)
	_objective = TextEdit.new()
	_objective.custom_minimum_size.y = 112
	_objective.placeholder_text = "Describe the software change, target behavior, constraints and non-goals..."
	_objective.text_changed.connect(_update_submit)
	column.add_child(_objective)
	var acceptance_label := Label.new()
	acceptance_label.text = "ACCEPTANCE EVIDENCE   /   one testable criterion per line"
	column.add_child(acceptance_label)
	_acceptance = TextEdit.new()
	_acceptance.custom_minimum_size.y = 95
	_acceptance.placeholder_text = "Godot import exits 0 with no engine errors\nFeature test passes on exact commit\nNo unrelated workspace files touched"
	_acceptance.text_changed.connect(_update_submit)
	column.add_child(_acceptance)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 14)
	column.add_child(controls)
	_risk = OptionButton.new()
	_risk.add_item("R0  /  READ & REPORT")
	_risk.add_item("R1  /  DOCS ONLY")
	_risk.add_item("R2  /  CODE + HUMAN APPROVAL")
	_risk.select(2)
	_risk.item_selected.connect(func(_index): _update_submit())
	controls.add_child(_risk)
	_submit = Button.new()
	_submit.text = "SUBMIT TO STUDIO"
	_submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submit.pressed.connect(_submit_mission)
	controls.add_child(_submit)
	_view_mission = Button.new()
	_view_mission.text = "VIEW VERIFIED INDEX"
	_view_mission.visible = false
	_view_mission.tooltip_text = "Open only after Studio's observed mission list confirms the ID"
	_view_mission.pressed.connect(func():
		if not _ack_id.is_empty():
			mission_view_requested.emit(_ack_id))
	controls.add_child(_view_mission)
	var open_studio := Button.new()
	open_studio.text = "OPEN STUDIO"
	open_studio.pressed.connect(func():
		OS.shell_open("http://127.0.0.1:%d/" % _port))
	controls.add_child(open_studio)
	_guard_action = Button.new()
	_guard_action.visible = false
	_guard_action.modulate = Color("#f3ad91")
	_guard_action.tooltip_text = ("Before retrying, inspect Studio's canonical mission index. "
		+ "An ambiguous POST may already have created a mission.")
	_guard_action.pressed.connect(_release_submission_guard)
	column.add_child(_guard_action)

	_response = RichTextLabel.new()
	_response.bbcode_enabled = false
	_response.custom_minimum_size.y = 128
	_response.fit_content = true
	_response.scroll_active = false
	_response.text = ("MISSION NOT SUBMITTED.\n"
		+ "After Studio acknowledges a mission ID, inspect the source log and receipts "
		+ "in the observed Missions tab. Promotion remains review-gated.")
	column.add_child(_response)
	_reset_picker()
	_update_submit()

func _reset_picker() -> void:
	if _project_select == null:
		return
	_project_select.clear()
	_project_select.add_item("Select an OBSERVED Git project", 0)
	_project_select.select(0)

func _refresh_projects() -> void:
	if _projects_busy or _post_busy:
		return
	_projects_busy = true
	_projects_state = "unknown"
	_observed_at = 0
	_projects.clear()
	_reset_picker()
	_project_state.text = "Scanning Studio Project Constellation (single flight)..."
	_update_submit()
	var err := _project_http.request("http://127.0.0.1:%d/api/projects" % _port,
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if err != OK:
		_projects_busy = false
		_project_state.text = "PROJECT SOURCE UNAVAILABLE / request refused."
		_update_submit()

func _on_projects_finished(result: int, status: int, _headers: PackedStringArray,
		bytes: PackedByteArray) -> void:
	_projects_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or status != 200 or bytes.size() > 524288:
		_projects_state = "unavailable"
		_project_state.text = "PROJECT SOURCE UNAVAILABLE / invalid HTTP reply. NO POST."
		_update_submit()
		return
	var parsed: Dictionary = CONTRACT.parse_projects(bytes.get_string_from_utf8())
	if not parsed.get("ok", false):
		_projects_state = "unknown"
		_project_state.text = "PROJECT SOURCE UNKNOWN / " + String(parsed.get("reason", "bad_contract")) + ". NO POST."
		_update_submit()
		return
	_install_projects(parsed["projects"])

func _install_projects(incoming: Array) -> void:
	_projects.clear()
	for candidate in incoming:
		_projects.append(candidate.duplicate(true))
	_projects_state = "observed"
	_observed_at = Time.get_ticks_msec()
	_reset_picker()
	for index in _projects.size():
		var project := _projects[index]
		_project_select.add_item("%s   [%s]" % [project["name"], project["branch"]], index + 1)
	_project_state.text = ("%d eligible source-observed repositories. Explicitly select one; "
		+ "the snapshot expires in 45 seconds.") % _projects.size()
	_update_submit()

func _fresh() -> bool:
	return _projects_state == "observed" and _observed_at > 0 and (
		Time.get_ticks_msec() - _observed_at < FRESH_MS)

func _selected_project() -> Dictionary:
	if _project_select == null or not _fresh():
		return {}
	var selected := _project_select.get_selected_id()
	if selected <= 0 or selected > _projects.size():
		return {}
	return _projects[selected - 1].duplicate(true)

func _risk_code() -> String:
	return ["R0", "R1", "R2"][_risk.selected] if _risk != null and _risk.selected >= 0 and _risk.selected <= 2 else "R3"

func _update_submit() -> void:
	if _submit == null:
		return
	if _guard_action != null:
		_guard_action.visible = _submission_guard in ["uncertain", "acknowledged"]
		_guard_action.text = ("CHECK STUDIO, THEN AUTHORIZE RETRY (DUPLICATE RISK)"
			if _submission_guard == "uncertain" else
			"START A NEW MISSION DRAFT")
	var valid_source := _fresh()
	if _projects_state == "observed" and not valid_source and _project_state != null:
		_project_state.text = "PROJECT SOURCE STALE / rescan before submitting. NO POST."
	var spec: Dictionary = CONTRACT.make_spec(_selected_project(),
		_title.text, _objective.text, _acceptance.text, _risk_code())
	_submit.disabled = (_projects_busy or _post_busy or _submission_guard != "draft"
		or not valid_source or not spec.get("ok", false))
	_submit.tooltip_text = ("Ready for explicit Studio submission" if not _submit.disabled
		else "Submission locked: verify Studio before another POST" if
		_submission_guard != "draft" else
		String(spec.get("reason", "Project source is not fresh")))

func _release_submission_guard() -> void:
	if _post_busy or _submission_guard == "draft":
		return
	if _submission_guard == "acknowledged":
		_ack_id = ""
		_view_mission.visible = false
		_title.clear()
		_objective.clear()
		_acceptance.clear()
		_project_select.select(0)
		_response.text = "NEW DRAFT / select a fresh observed repository and write a new objective."
	else:
		_response.text = ("RETRY UNLOCKED BY OPERATOR / verify in Studio first: "
			+ "a previous POST may already have created a mission.")
	_submission_guard = "draft"
	_update_submit()

func _submit_mission() -> void:
	if _post_busy or _submission_guard != "draft" or not _fresh():
		return
	var project := _selected_project()
	var spec: Dictionary = CONTRACT.make_spec(project, _title.text,
		_objective.text, _acceptance.text, _risk_code())
	if not spec.get("ok", false):
		_response.text = "NOT SUBMITTED / " + String(spec.get("reason", "invalid_envelope"))
		return
	_post_busy = true
	_ack_id = ""
	_view_mission.visible = false
	_expected_repo = String(project["path"])
	_expected_risk = _risk_code()
	_response.text = "SUBMITTING TO LOCAL STUDIO / awaiting exact HTTP acknowledgement..."
	_update_submit()
	var err := _post_http.request("http://127.0.0.1:%d/api/missions" % _port,
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(spec["body"]))
	if err != OK:
		_post_busy = false
		_response.text = "NOT SUBMITTED / local Studio transport rejected request. Text preserved."
		_update_submit()

func _on_post_finished(result: int, status: int, _headers: PackedStringArray,
		bytes: PackedByteArray) -> void:
	_post_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or bytes.size() > 65536:
		_submission_guard = "uncertain"
		_response.text = "NOT ACKNOWLEDGED / Studio may have created the mission. Verify in Studio before retrying."
		_update_submit()
		return
	var ack: Dictionary = CONTRACT.parse_post_result(
		status, bytes.get_string_from_utf8(), _expected_repo, _expected_risk)
	if not ack.get("ok", false):
		_submission_guard = "uncertain"
		_response.text = ("NOT ACKNOWLEDGED / " + String(ack.get("reason", "invalid_result"))
			+ ". Submission is locked until you verify Studio and explicitly unlock retry.")
		_update_submit()
		return
	var mission_id := String(ack["id"])
	var state := String(ack["status"])
	_ack_id = mission_id
	_submission_guard = "acknowledged"
	_view_mission.visible = true
	_response.text = ("ACKNOWLEDGED BY STUDIO\nID: %s\nSTATE: %s\nRISK: %s\nREPOSITORY: %s\n\n"
		+ "This is a stored mission, NOT proof of a running agent, passing test or merge.\n"
		+ "Code work requires separate human approval in Studio when awaiting_approval.\n"
		+ "Use OBSERVED MISSIONS for source logs and subsequent evidence.") % [
			mission_id, state, _expected_risk, _expected_repo]
	mission_submitted.emit(mission_id, state)
	_update_submit()
