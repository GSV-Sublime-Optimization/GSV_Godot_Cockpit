extends PanelContainer

const EVIDENCE = preload("res://scripts/workstation/WorkbenchMissionEvidence.gd")
const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")

## A tab for *observed* mission logs or catalogued agent runtimes.
## Deliberately not a PTY. A process/CLI/session name cannot be an attach token.

var entry: Dictionary = {}
var client: Node
var _header: Label
var _meta: Label
var _read_log: Button
var _read_evidence: Button
var _evidence_http: HTTPRequest
var _terminal: TextEdit

func configure(selected: Dictionary, studio_client: Node) -> void:
	entry = selected.duplicate(true)
	client = studio_client

func _ready() -> void:
	_evidence_http = HTTPRequest.new()
	_evidence_http.timeout = 6.0
	_evidence_http.max_redirects = 0
	add_child(_evidence_http)
	_evidence_http.request_completed.connect(_on_evidence_completed)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	layout.add_child(header)
	_header = Label.new()
	_header.text = String(entry.get("title", entry.get("name", "Session")))
	_header.add_theme_font_size_override("font_size", 20)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_header)
	var id_button := Button.new()
	id_button.text = "COPY ID"
	id_button.tooltip_text = "Copy source session ID. Does not attach or execute."
	id_button.pressed.connect(_copy_id)
	header.add_child(id_button)
	_meta = Label.new()
	_meta.add_theme_font_size_override("font_size", 12)
	_meta.modulate = Color("#9baec4")
	layout.add_child(_meta)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	layout.add_child(toolbar)
	_read_log = Button.new()
	_read_log.text = "READ LOG TAIL"
	_read_log.tooltip_text = "Explicitly request bounded read-only mission log from local Studio"
	_read_log.disabled = entry.get("session_kind", "") != "mission_log"
	_read_log.pressed.connect(refresh_log)
	toolbar.add_child(_read_log)
	_read_evidence = Button.new()
	_read_evidence.text = "INSPECT RECEIPT / TESTS"
	_read_evidence.disabled = entry.get("session_kind", "") != "mission_log"
	_read_evidence.pressed.connect(refresh_evidence)
	toolbar.add_child(_read_evidence)
	var studio_button := Button.new()
	studio_button.text = "OPEN STUDIO"
	studio_button.pressed.connect(func(): OS.shell_open("http://127.0.0.1:7340/"))
	toolbar.add_child(studio_button)

	_terminal = TextEdit.new()
	_terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_terminal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terminal.editable = false
	_terminal.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_terminal.add_theme_color_override("font_color", Color("#d2e2ec"))
	_terminal.add_theme_font_size_override("font_size", 13)
	_terminal.add_theme_color_override("background_color", Color("#101822"))
	layout.add_child(_terminal)

	var footer := LineEdit.new()
	footer.editable = false
	footer.placeholder_text = "INPUT LOCKED  ·  requires authenticated owner PTY attachment"
	footer.tooltip_text = "This pane cannot spawn or seize a terminal; no PTY contract exists."
	layout.add_child(footer)

	if entry.get("session_kind", "") == "mission_log":
		_meta.text = "STUDIO MISSION  /  %s  /  %s  /  READ-ONLY" % [
			String(entry.get("id", "")), String(entry.get("status", "unknown"))
		]
		_terminal.text = (
			"Observed Studio mission. No live terminal has been claimed.\n"
			+ "Press READ LOG TAIL to request a bounded source log.\n"
			+ "Commands and approvals are handled by KiloCore Studio, not this tab."
		)
		if client != null:
			client.mission_log_received.connect(_on_mission_log)
	else:
		_meta.text = "CATALOGUED RUNTIME  /  SESSION NOT OBSERVED  /  NO ATTACH"
		_terminal.text = (
			"%s\n\n" % String(entry.get("role", "Agent or external tool"))
			+ "This component is known to the colony's project catalogue.\n"
			+ "No authenticated, attachable PTY or session stream has been reported.\n\n"
			+ "To make this tab interactive, the owning harness must publish a\n"
			+ "typed session ID, identity/permission scope, stream route, activity\n"
			+ "heartbeat and cancellation semantics through the approved broker.\n"
			+ "The cockpit will not spawn a lookalike process."
		)

func refresh_log() -> void:
	if client == null or entry.get("session_kind", "") != "mission_log":
		return
	_read_log.disabled = true
	_terminal.text = "Fetching bounded read-only Studio mission trace..."
	if not client.request_mission_log(String(entry.get("id", ""))):
		_terminal.text = "Log request rejected. Refresh the mission index before retrying."
		_read_log.disabled = false

func _on_mission_log(mission_id: String, lines: PackedStringArray, error: String) -> void:
	if mission_id != String(entry.get("id", "")):
		return
	_read_log.disabled = false
	if not error.is_empty():
		_terminal.text = "Mission log unavailable: " + error
		return
	if lines.is_empty():
		_terminal.text = "No log lines returned by Studio for this mission."
		return
	_terminal.text = "\n".join(lines).substr(0, 80000)

func refresh_evidence() -> void:
	if entry.get("session_kind", "") != "mission_log" or _read_evidence.disabled:
		return
	var id := String(entry.get("id", ""))
	if not CATALOG.valid_mission_id(id):
		return
	var port := 7340
	var supplied := OS.get_environment("GSV_STUDIO_ENTITY_PORT")
	if supplied.is_valid_int() and not supplied.is_empty():
		var candidate := int(supplied)
		if candidate >= 1 and candidate <= 65535:
			port = candidate
	_read_evidence.disabled = true
	_terminal.text = "Reading the owning Studio mission result and validator evidence..."
	var code := _evidence_http.request("http://127.0.0.1:%d/api/missions/%s" % [port, id],
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if code != OK:
		_read_evidence.disabled = false
		_terminal.text = "Evidence unavailable / local read rejected."

func _on_evidence_completed(result: int, status: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_read_evidence.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or status != 200 or body.size() > 131072:
		_terminal.text = "Evidence UNKNOWN / no valid Studio mission GET reply."
		return
	var parsed: Dictionary = EVIDENCE.parse(
		body.get_string_from_utf8(), String(entry.get("id", "")))
	if not parsed.get("ok", false):
		_terminal.text = "Evidence UNKNOWN / " + String(parsed.get("reason", "invalid_contract"))
		return
	_terminal.text = EVIDENCE.format(parsed["proof"])

func _copy_id() -> void:
	DisplayServer.clipboard_set(String(entry.get("id", "")))
