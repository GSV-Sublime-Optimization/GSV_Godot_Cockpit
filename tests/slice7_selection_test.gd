extends SceneTree

## Slice 7 selection tests: one selection model for rigs / services /
## seats / PRs / missions / Atlas entries / PUs (design §3). Pure logic —
## no scene tree, no live feeds. Fixtures only.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/slice7_selection_test.gd
##
## Exit 0 = pass, 1 = fail.
## Also run by tests/godot_smoke_gate.py as the "slice7-selection" case.

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_default_is_local_rig()
	_check_xanadu_present_but_not_default()
	_check_select_and_dim()
	_check_pr_detail_and_prefill()
	_check_seat_live_vs_dated()
	_check_atlas_proven_only()
	_check_unknown_node()
	_finish()


func _fixture_sources() -> Dictionary:
	var fleet := {
		"age_ms": 42000,
		"rigs": {
			"msi": {"state": "live", "ram_free_mb": 4638, "cpu_load_pct": 12, "seats": "Muse, Codex"},
			"i3": {"state": "live", "ram_free_mb": 14577, "cpu_load_pct": 8},
			"l9": {"state": "stale", "note": "snapshot old"},
			"xanadu": {"state": "live", "ram_free_mb": 5972, "cpu_load_pct": 5},
		},
	}
	var model := {
		"sensor": {"state": "live", "mission_counts": {"awaiting": 1, "running": 0, "queued": 0}, "thermal_gate": "open"},
		"gateway": {"state": "live", "gateway_status": "ok"},
		"constellation": {"state": "unavailable"},
		"fleet_bodies": [{"state": "reported_fresh"}, {"state": "reported_fresh"}],
	}
	var now := Time.get_unix_time_from_system()
	var chorus := {
		"smiths": [
			{"name": "MSI Claude", "doing": "Reviewing FleetBridge#49", "t": now - 90.0, "at": "2026-11-08T10:30:00Z", "station": "hearth", "rig": "msi"},
			{"name": "Steward", "doing": "off-box backup running", "t": now - 60.0, "at": "2026-11-08T10:30:30Z", "station": "vault", "rig": "xanadu"},
		],
		"prs_waiting": [],
		"doctor": [],
		"spine": {"up": 16, "total": 18, "services": [
			{"name": "chatdev", "tier": "agent", "up": true, "ms": 12},
			{"name": "skyclaw", "tier": "lattice", "up": true, "ms": 10},
		]},
	}
	var events := {"events": [
		{"at": "2026-11-08T08:33:54Z", "kind": "pr_merged", "repo": "GSV_Godot_Cockpit", "number": 22, "title": "contrib(chorus): POST origin guard", "url": "https://github.com/GSV-Sublime-Optimization/GSV_Godot_Cockpit/pull/22", "actor": "KiloMusician", "verdict": ""},
	]}
	var atlas := {"entries": [
		{"id": "ollama-server-msi", "name": "Ollama server", "grade": "Q", "machine": "msi", "cost_class": "tokenless", "state": "live", "overlay": "live_probe"},
		{"id": "vague-idea", "name": "Vague idea", "grade": "D", "machine": "msi", "cost_class": "tokenless", "state": "not_detected", "overlay": ""},
	]}
	var pu := {"file_age": "52 d old", "items": [
		{"id": "PU-1-1776596989", "title": "Fix ValueError", "status": "approved", "source_repo": "NuSyQ-Hub", "priority": "medium"},
	]}
	return {"fleet": fleet, "model": model, "chorus": chorus, "events": events, "atlas": atlas, "pu": pu}


func _nodes() -> Array:
	var src := _fixture_sources()
	return HoloSelection.build_nodes(src["fleet"], src["model"], src["chorus"], src["events"], src["atlas"], src["pu"])


func _check_default_is_local_rig() -> void:
	var node := HoloSelection.default_node(_nodes())
	if String(node.get("kind", "")) != "rig" or String(node.get("id", "")) != "msi":
		_fail("default node is %s %s, expected rig msi" % [String(node.get("kind", "?")), String(node.get("id", "?"))])


func _check_xanadu_present_but_not_default() -> void:
	var nodes := _nodes()
	var found := HoloSelection.find_node(nodes, "rig", "xanadu")
	if found.is_empty():
		_fail("xanadu rig node missing from the rail")
		return
	if String(found.get("role", "")).find("library") < 0:
		_fail("xanadu node does not say it is the library/record-keeper: %s" % String(found.get("role", "")))
	if HoloSelection.default_node(nodes).get("id", "") == "xanadu":
		_fail("default node is xanadu — the room must never default to it")


func _check_select_and_dim() -> void:
	var nodes := _nodes()
	var sel := HoloSelection.new()
	sel.select(HoloSelection.find_node(nodes, "rig", "msi"))
	if not sel.has_selection():
		_fail("select did not record a selection")
	if sel.selected_id() != "msi":
		_fail("selected id is %s, expected msi" % sel.selected_id())
	var other := HoloSelection.find_node(nodes, "rig", "i3")
	if not sel.is_dimmed(other):
		_fail("non-selected rig i3 is not dimmed while msi is selected")
	var self_node := HoloSelection.find_node(nodes, "rig", "msi")
	if sel.is_dimmed(self_node):
		_fail("selected rig msi is dimmed")
	if not is_equal_approx(HoloSelection.DIMMED_FACTOR, 0.4):
		_fail("dimmed factor is %f, expected 0.4" % HoloSelection.DIMMED_FACTOR)
	sel.clear()
	if sel.has_selection() or sel.is_dimmed(other):
		_fail("clear did not restore the whole-room view")


func _check_pr_detail_and_prefill() -> void:
	var nodes := _nodes()
	var node := HoloSelection.find_node(nodes, "pr", "GSV_Godot_Cockpit#22")
	if node.is_empty():
		_fail("PR node GSV_Godot_Cockpit#22 missing")
		return
	var lines: PackedStringArray = HoloSelection.detail_lines(node)
	var joined := "\n".join(lines)
	if joined.find("POST origin guard") < 0:
		_fail("PR detail lines carry no title: %s" % joined)
	if joined.find("https://github.com/GSV-Sublime-Optimization/GSV_Godot_Cockpit/pull/22") < 0:
		_fail("PR detail lines carry no deep link: %s" % joined)
	var prefill := HoloSelection.compose_prefill(node)
	if prefill.find("PREFILL ONLY") < 0:
		_fail("compose text does not say PREFILL ONLY: %s" % prefill)
	if prefill.find("never here") < 0 and prefill.find("no submit") < 0:
		_fail("compose text does not disclaim submission: %s" % prefill)


func _check_seat_live_vs_dated() -> void:
	var nodes := _nodes()
	var claude := HoloSelection.find_node(nodes, "seat", "claude")
	if claude.is_empty():
		_fail("claude seat node missing")
		return
	var facts: Dictionary = claude.get("facts", {})
	if String(facts.get("doing", "")).find("FleetBridge#49") < 0:
		_fail("claude seat carries no live smiths activity: %s" % str(facts))
	var gordon := HoloSelection.find_node(nodes, "seat", "gordon")
	if gordon.is_empty():
		_fail("gordon seat node missing")
		return
	if String(gordon.get("age", "")).find("2026-11-07") < 0:
		_fail("seat with no live source is not labelled seen 2026-11-07: %s" % String(gordon.get("age", "")))


func _check_atlas_proven_only() -> void:
	var nodes := _nodes()
	if HoloSelection.find_node(nodes, "atlas", "ollama-server-msi").is_empty():
		_fail("proven Atlas entry (grade Q) missing from the rail")
	if not HoloSelection.find_node(nodes, "atlas", "vague-idea").is_empty():
		_fail("grade-D Atlas entry is on the rail — only proven Q/U entries are selectable")


func _check_unknown_node() -> void:
	var nodes := _nodes()
	if not HoloSelection.find_node(nodes, "rig", "nope").is_empty():
		_fail("find_node returned a node for an unknown id")
	if not HoloSelection.find_node(nodes, "warp", "msi").is_empty():
		_fail("find_node returned a node for an unknown kind")
	if not HoloSelection.default_node([]).is_empty():
		_fail("default_node on an empty list is not empty")


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
