extends Control

## GSV Godot Cockpit — Main.gd
## The cockpit of GSV Sublime Optimization.
## Not the brain. The cockpit.
##
## Panels:
##   STATUS    — live service probes, agent roster
##   QUESTS    — colony reports as quest board
##   RECEIPTS  — audit trail from receipts.jsonl / sprint logs
##   TD        — Terminal Depths game-heart state
##   FLIGHT    — autonomous supervisor heartbeat and log tail
##   STEER     — bounded cockpit actions / FCC smoke / route packets
##   ROUTE     — natural-language routing to intermediary / gsv

const BRIDGE := "C:/GSV/tools/godot-cockpit/Invoke-GSVGodotBridge.ps1"

## Every panel that talks to the colony does so with a blocking
## OS.execute("pwsh", ...) call from its own _ready(). Building all thirteen
## tabs up front therefore cost 24 serial process spawns — measured at 39 s —
## before the window could draw anything. Tabs are now built on first visit,
## and the cockpit's own first probe waits until a frame has been painted.
## Two frames, not a wall-clock delay: the first frame's delta can already
## exceed a short timer, which would put the probe back ahead of the paint.
const FIRST_PROBE_DELAY_FRAMES := 2

var _tabs: TabContainer
var _status_box: RichTextLabel
var _status_bar: Label
var _route_input: LineEdit
var _route_output: RichTextLabel
var _steer_output: RichTextLabel
var _flight_output: RichTextLabel

## tab index -> Callable(Control), dropped once that tab has been built.
var _lazy_fillers: Dictionary = {}

func _ready() -> void:
	_build_ui()
	_status_bar.text = "● online"
	_status_bar.modulate = Color(0.4, 1.0, 0.4)
	_append_status("[color=cyan]Ξ GSV Godot Cockpit[/color] — online.")
	_append_status("Bridge: " + BRIDGE)
	_append_status("Kilo_Core · GSV · Intermediary · FCC · LiteLLM · OpenClaw · Serena → [b]Cockpit[/b] → you")
	_append_status("─────────────────────────────────────")
	# refresh_status() blocks on a bridge call measured at ~21 s. Paint first.
	_probe_after_first_paint()

## Runs the opening status probe once the cockpit is actually on screen.
func _probe_after_first_paint() -> void:
	for _frame in FIRST_PROBE_DELAY_FRAMES:
		await get_tree().process_frame
	refresh_status()

# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	root.offset_left = 8; root.offset_top = 8
	root.offset_right = -8; root.offset_bottom = -8
	add_child(root)

	# Title
	var title := Label.new()
	title.text = "Ξ  GSV  Sublime Optimization  /  Colony Cockpit"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	# Status bar
	_status_bar = Label.new()
	_status_bar.text = "● booting..."
	_status_bar.modulate = Color(1.0, 0.8, 0.2)
	root.add_child(_status_bar)

	var sep := HSeparator.new()
	root.add_child(sep)

	# Tab container
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_add_tab("Status", _fill_status_tab)
	_add_tab("Events", _panel_filler("res://scripts/EventStream.gd"))
	_add_tab("Git Log", _panel_filler("res://scripts/GitLogPanel.gd"))
	_add_tab("Dispatch", _panel_filler("res://scripts/DispatchQueuePanel.gd"))
	_add_tab("Models", _panel_filler("res://scripts/ModelStatusPanel.gd"))
	_add_tab("Agents", _panel_filler("res://scripts/AgentMap.gd"))
	_add_tab("CHUG", _panel_filler("res://scripts/CHUGPanel.gd"))
	_add_tab("Quests", _panel_filler("res://scripts/QuestBoard.gd"))
	_add_tab("Receipts", _panel_filler("res://scripts/ReceiptViewer.gd"))
	_add_tab("Terminal Depths", _panel_filler("res://scripts/TDStatePanel.gd"))
	_add_tab("Flight", _fill_flight_tab)
	_add_tab("Steer", _fill_steer_tab)
	_add_tab("Route", _fill_route_tab)

	_tabs.tab_changed.connect(_materialize_tab)
	# The tab that is already showing has no tab_changed to wait for.
	_materialize_tab(_tabs.current_tab)

## Adds a tab whose contents are built the first time it is shown.
func _add_tab(tab_name: String, filler: Callable) -> void:
	var panel := VBoxContainer.new()
	panel.name = tab_name
	panel.add_theme_constant_override("separation", 6)
	_tabs.add_child(panel)
	_lazy_fillers[_tabs.get_tab_count() - 1] = filler

func _materialize_tab(idx: int) -> void:
	if not _lazy_fillers.has(idx):
		return
	var filler: Callable = _lazy_fillers[idx]
	_lazy_fillers.erase(idx)
	var panel := _tabs.get_tab_control(idx)
	if panel == null:
		return
	filler.call(panel)

## Filler for tabs whose whole body is a single panel script.
func _panel_filler(script_path: String) -> Callable:
	return func(panel: Control) -> void:
		var node: Control = load(script_path).new()
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(node)

func _fill_status_tab(panel: Control) -> void:
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	panel.add_child(btns)

	_add_btn(btns, "↺ Refresh",  refresh_status)
	_add_btn(btns, "⚡ Proof",    run_proof)
	_add_btn(btns, "🧹 Clear",    func(): _status_box.clear())

	_status_box = RichTextLabel.new()
	_status_box.scroll_following = true
	_status_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_status_box)

func _fill_flight_tab(panel: Control) -> void:
	var info := Label.new()
	info.text = "Autonomous supervisor heartbeat and log tail. Watch the colony work without losing the thread."
	info.modulate = Color(0.7, 0.9, 1.0)
	panel.add_child(info)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	panel.add_child(btns)

	_add_btn(btns, "Refresh Flight", _refresh_flight)
	_add_btn(btns, "Clear", func(): _flight_output.clear())

	_flight_output = RichTextLabel.new()
	_flight_output.scroll_following = true
	_flight_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_flight_output)

func _fill_steer_tab(panel: Control) -> void:
	var info := Label.new()
	info.text = "Bounded actions: steering map, FCC smoke, cockpit memory. No long autonomous launch here."
	info.modulate = Color(0.7, 0.9, 1.0)
	panel.add_child(info)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	panel.add_child(btns)

	_add_btn(btns, "Steering Map", _refresh_steering)
	_add_btn(btns, "FCC Smoke", _fcc_smoke)
	_add_btn(btns, "Memory Tail", _steer_memory)
	_add_btn(btns, "Clear", func(): _steer_output.clear())

	_steer_output = RichTextLabel.new()
	_steer_output.scroll_following = true
	_steer_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_steer_output)

func _fill_route_tab(panel: Control) -> void:
	var info := Label.new()
	info.text = "Type a task. It routes through intermediary + gsv who-can."
	info.modulate = Color(0.7, 0.9, 1.0)
	panel.add_child(info)

	var input_row := HBoxContainer.new()
	panel.add_child(input_row)

	_route_input = LineEdit.new()
	_route_input.placeholder_text = "Route a task to the Greater System..."
	_route_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_input.text_submitted.connect(_do_route)
	input_row.add_child(_route_input)

	_add_btn(input_row, "Route ▶", func(): _do_route(_route_input.text))

	_route_output = RichTextLabel.new()
	_route_output.scroll_following = true
	_route_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_route_output)

func _add_btn(parent: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	parent.add_child(b)

# ── ACTIONS ───────────────────────────────────────────────────────────────────

func refresh_status() -> void:
	_status_bar.text = "● probing..."
	_status_bar.modulate = Color(1.0, 0.8, 0.2)
	var raw := _bridge("status", "")
	_append_status("\n[color=cyan]=== STATUS ===[/color]")
	_append_status(_parse_status(raw))
	_status_bar.text = "● live"
	_status_bar.modulate = Color(0.4, 1.0, 0.4)

func run_proof() -> void:
	_status_bar.text = "● proving..."
	var text := _bridge("proof", "")
	_append_status("\n[color=yellow]=== PROOF ===[/color]")
	_append_status(text)
	_status_bar.text = "● proof done"

func _do_route(obj: String = "") -> void:
	if obj.is_empty():
		obj = _route_input.text.strip_edges()
	if obj.is_empty():
		return
	_route_input.text = ""
	_route_output.append_text("\n[color=white]>>> %s[/color]\n" % obj)
	_status_bar.text = "● routing..."
	var text := _bridge("route", obj)
	_route_output.append_text("[color=green]=== ROUTE RESULT ===[/color]\n%s\n" % text)
	_status_bar.text = "● routed"

func _refresh_steering() -> void:
	_status_bar.text = "● steering..."
	var raw := _bridge("steer", "")
	_append_steer("\n[color=cyan]=== STEERING MAP ===[/color]")
	_append_steer(_parse_steer(raw))
	_status_bar.text = "● steering ready"

func _fcc_smoke() -> void:
	_status_bar.text = "● FCC..."
	var text := _bridge("fcc-smoke", "")
	_append_steer("\n[color=yellow]=== FCC SMOKE ===[/color]")
	_append_steer(text)
	_status_bar.text = "● FCC done"

func _steer_memory() -> void:
	var text := _bridge("memory", "")
	_append_steer("\n[color=green]=== COCKPIT MEMORY ===[/color]")
	_append_steer(text)

func _refresh_flight() -> void:
	_status_bar.text = "● flight..."
	var raw := _bridge("flight", "")
	_append_flight("\n[color=cyan]=== AUTONOMOUS FLIGHT ===[/color]")
	_append_flight(_parse_flight(raw))
	_status_bar.text = "● flight read"

# ── BRIDGE ────────────────────────────────────────────────────────────────────

func _bridge(mode: String, objective: String) -> String:
	var args: Array[String] = ["-NoProfile","-ExecutionPolicy","Bypass","-File",BRIDGE,"-Mode",mode]
	if not objective.is_empty():
		args.append_array(["-Objective", objective])
	var output: Array = []
	var code := OS.execute("pwsh", args, output, true, false)
	if code != 0:
		output.clear()
		code = OS.execute("powershell", args, output, true, false)
	var text := ""
	for item in output:
		text += str(item)
	return text if not text.strip_edges().is_empty() else "(no output — exit %d)" % code

func _parse_status(raw: String) -> String:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return raw
	var d = json.get_data()
	if typeof(d) != TYPE_DICTIONARY:
		return raw
	var lines: PackedStringArray = []
	lines.append("ts: " + str(d.get("ts","?")).substr(0,19))
	lines.append("services: [color=green]%d UP[/color] / [color=%s]%d DOWN[/color]" % [
		int(d.get("services_up",0)),
		"red" if int(d.get("services_down",0)) > 0 else "green",
		int(d.get("services_down",0))
	])
	var svcs = d.get("services", [])
	if typeof(svcs) == TYPE_ARRAY:
		for svc in svcs:
			if typeof(svc) == TYPE_DICTIONARY:
				var up: bool = svc.get("up", false)
				lines.append("  %s %s" % [
					"[color=green]✓[/color]" if up else "[color=red]✗[/color]",
					str(svc.get("name","?"))
				])
	lines.append("")
	lines.append("agents:")
	var cmds = d.get("commands", [])
	if typeof(cmds) == TYPE_ARRAY:
		var found_names: PackedStringArray = []
		var miss_names:  PackedStringArray = []
		for c in cmds:
			if typeof(c) == TYPE_DICTIONARY:
				if c.get("found", false): found_names.append(str(c.get("name","")))
				else:                     miss_names.append(str(c.get("name","")))
		lines.append("  [color=green]✓[/color] " + "  ".join(found_names))
		if not miss_names.is_empty():
			lines.append("  [color=gray]✗[/color] " + "  ".join(miss_names))
	return "\n".join(lines)

func _parse_steer(raw: String) -> String:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return raw
	var d = json.get_data()
	if typeof(d) != TYPE_DICTIONARY:
		return raw

	var lines: PackedStringArray = []
	lines.append("ts: " + str(d.get("ts", "?")).substr(0, 19))
	lines.append("next: " + str(d.get("next_best", "")))
	lines.append("")
	lines.append("lanes:")
	var lanes = d.get("lanes", {})
	if typeof(lanes) == TYPE_DICTIONARY:
		for name in lanes.keys():
			var lane = lanes[name]
			if typeof(lane) == TYPE_DICTIONARY:
				var up: bool = bool(lane.get("up", lane.get("found", false)))
				var color: String = "green" if up else "red"
				lines.append("  [color=%s]%s[/color] %s" % [color, "UP " if up else "MISS", str(name)])

	lines.append("")
	lines.append("recent reports:")
	var reports = d.get("recent_reports", [])
	if typeof(reports) == TYPE_ARRAY:
		for report in reports.slice(0, 6):
			if typeof(report) == TYPE_DICTIONARY:
				lines.append("  " + str(report.get("name", "")))

	return "\n".join(lines)

func _parse_flight(raw: String) -> String:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return raw
	var d = json.get_data()
	if typeof(d) != TYPE_DICTIONARY:
		return raw

	var lines: PackedStringArray = []
	if not bool(d.get("found", false)):
		lines.append("[color=yellow]No autonomous flight run found.[/color]")
		return "\n".join(lines)

	lines.append("run: " + str(d.get("run", "")))
	lines.append("running: " + ("yes" if bool(d.get("running", false)) else "no"))
	var heartbeat = d.get("heartbeat", {})
	if typeof(heartbeat) == TYPE_DICTIONARY:
		lines.append("cycle: %s   phase: %s" % [str(heartbeat.get("cycle", "?")), str(heartbeat.get("phase", "?"))])
		lines.append("heartbeat: " + str(heartbeat.get("heartbeat_at", "")).substr(0, 19))
		lines.append("ends: " + str(heartbeat.get("ends_at", "")).substr(0, 19))
	lines.append("")
	lines.append("log tail:")
	var tail = d.get("log_tail", [])
	if typeof(tail) == TYPE_ARRAY:
		for line in tail.slice(maxi(0, tail.size() - 24), tail.size()):
			lines.append("  " + str(line))

	return "\n".join(lines)

func _append_status(text: String) -> void:
	if _status_box:
		_status_box.append_text(text + "\n")

func _append_steer(text: String) -> void:
	if _steer_output:
		_steer_output.append_text(text + "\n")

func _append_flight(text: String) -> void:
	if _flight_output:
		_flight_output.append_text(text + "\n")
