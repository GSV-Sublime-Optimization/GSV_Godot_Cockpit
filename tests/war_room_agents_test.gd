extends SceneTree

## War-room agent-workstation tests (contribution on top of Slice 5):
## the idle budget, the exits, the honesty fixes, and "Assign to seat" from a
## pulled-up card. Negative controls on fake data; no network, no shell.
##
## Run:
##   godot --headless --audio-driver Dummy --path . --script res://tests/war_room_agents_test.gd
##
## Exit 0 = pass, 1 = fail. Also run by tests/godot_smoke_gate.py as the
## "war-room" case. Fixture files live under user:// (cleaned up at the end).

const HOLO_TAB_SCRIPT := "res://scripts/holo/HoloTab.gd"
const HOLO_ROOM_SCENE := "res://scenes/HoloRoom.tscn"
const WAR_ROOM_SCENE := "res://scenes/HoloWarRoom.tscn"
const FIXTURE_DIR := "user://war_room_test"

var _failures: PackedStringArray = []
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	_clean_fixtures()
	_check_budget()
	_check_exit_flags()
	_check_seat_honesty()
	await _check_atlas_header()
	_check_outbox_fail_closed()
	_check_outbox_append()
	_check_order_status()
	await _check_room_idles()
	await _check_room_seat_labels()
	await _check_tab()
	await _check_war_room_scene()
	_clean_fixtures()
	_finish()


# ── Budget + exits ───────────────────────────────────────────────────────────

func _check_budget() -> void:
	var fps_before := Engine.max_fps
	var lpm_before := OS.low_processor_usage_mode
	HoloBudget.apply()
	_expect(Engine.max_fps == 30, "apply() set max_fps %d, expected 30" % Engine.max_fps)
	_expect(OS.low_processor_usage_mode, "apply() did not enable low_processor_usage_mode")
	HoloBudget.set_focused(false)
	_expect(Engine.max_fps == 10, "unfocused max_fps %d, expected 10" % Engine.max_fps)
	HoloBudget.set_focused(true)
	_expect(Engine.max_fps == 30, "refocused max_fps %d, expected 30" % Engine.max_fps)
	Engine.max_fps = fps_before
	OS.low_processor_usage_mode = lpm_before


func _check_exit_flags() -> void:
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_expect(HoloBudget.is_quit_event(esc), "Esc press is not a quit event")
	var esc_up := InputEventKey.new()
	esc_up.keycode = KEY_ESCAPE
	esc_up.pressed = false
	_expect(not HoloBudget.is_quit_event(esc_up), "Esc release counted as a quit event")
	var other := InputEventKey.new()
	other.keycode = KEY_Q
	other.pressed = true
	_expect(not HoloBudget.is_quit_event(other), "Q counted as a quit event")
	_expect(not HoloBudget.is_quit_event(InputEventMouseButton.new()), "a mouse event counted as quit")

	var args := PackedStringArray(["--offscreen", "--shot=renders/room.png", "--quit-after=45"])
	_expect(HoloBudget.shot_path(args) == "renders/room.png", "shot_path parsed '%s'" % HoloBudget.shot_path(args))
	_expect(is_equal_approx(HoloBudget.quit_after_seconds(args), 45.0), "quit_after parsed wrong")
	_expect(HoloBudget.wants_offscreen(args), "--offscreen not recognised")
	var none := PackedStringArray(["--quit-after=soon"])
	_expect(HoloBudget.shot_path(none).is_empty(), "shot_path invented a path")
	_expect(HoloBudget.quit_after_seconds(none) == 0.0, "a non-numeric --quit-after was accepted")
	_expect(not HoloBudget.wants_offscreen(none), "offscreen invented")


# ── Honesty ──────────────────────────────────────────────────────────────────

func _check_seat_honesty() -> void:
	var no_probe := PackedStringArray()
	for seat in HoloLayerRegistry.seat_defs():
		var view := HoloLayerRegistry.seat_view(seat, no_probe)
		_expect(String(view["state"]) != "live",
			"seat %s renders live with no probe" % String(seat.get("id", "?")))
		_expect(bool(view["dimmed"]), "seat %s not dimmed with no probe" % String(seat.get("id", "?")))
		_expect(HoloLayerRegistry.is_honest_state(String(view["state"])),
			"seat %s renders a dishonest state" % String(seat.get("id", "?")))
	var codex := HoloLayerRegistry.seat_view(HoloLayerRegistry.seat_def("codex"), no_probe)
	_expect(String(codex["label"]) == "seen 11-07 (not live)", "codex label was '%s'" % String(codex["label"]))
	var skyclaw := HoloLayerRegistry.seat_view(HoloLayerRegistry.seat_def("skyclaw"), no_probe)
	_expect(String(skyclaw["label"]).contains("not live"), "skyclaw label was '%s'" % String(skyclaw["label"]))
	var gordon := HoloLayerRegistry.seat_view(HoloLayerRegistry.seat_def("gordon"), no_probe)
	_expect(String(gordon["state"]) == "not_detected", "gordon state became '%s'" % String(gordon["state"]))

	# Only a FRESH snapshot that lists the seat makes it live.
	var fresh := {"state": "live", "rigs": {"i3": {"state": "live", "seats": "Claude, ollama"}}}
	var tokens := HoloLayerRegistry.fresh_seat_tokens(fresh)
	_expect(tokens.has("ollama") and tokens.has("claude"), "fresh tokens were %s" % str(tokens))
	var ollama := HoloLayerRegistry.seat_view(HoloLayerRegistry.seat_def("ollama"), tokens)
	_expect(String(ollama["state"]) == "live" and bool(ollama["probed"]), "probed ollama did not read live")
	var codex_probe := HoloLayerRegistry.seat_view(HoloLayerRegistry.seat_def("codex"), tokens)
	_expect(String(codex_probe["state"]) != "live", "codex (no probe mapping) read live")
	var stale := {"state": "stale", "rigs": {"i3": {"state": "live", "seats": "ollama"}}}
	_expect(HoloLayerRegistry.fresh_seat_tokens(stale).is_empty(), "a stale snapshot produced seat tokens")
	_expect(HoloLayerRegistry.is_seat_id("codex") and not HoloLayerRegistry.is_seat_id("nobody"),
		"is_seat_id is wrong")


func _check_atlas_header() -> void:
	var layer := CapabilityAtlasLayer.new()
	root.add_child(layer)
	await process_frame
	var entries: Array = [
		{"id": "a", "name": "A", "grade": "Q", "machine": "msi", "cost_class": "tokenless", "state": "live", "overlay": "static_only"},
		{"id": "b", "name": "B", "grade": "U", "machine": "i3", "cost_class": "cloud", "state": "live", "overlay": "static_only"},
		{"id": "c", "name": "C", "grade": "D", "machine": "l9", "cost_class": "mixed", "state": "planned", "overlay": "static_only"},
	]
	layer.build_from(entries, "unknown")
	_expect(layer.graded_count() == 3, "graded_count %d, expected 3" % layer.graded_count())
	_expect(layer.live_count() == 0, "static 'live' grades counted as live (%d)" % layer.live_count())
	var header := layer.header_text()
	_expect(header.contains("3 graded"), "header lacks '3 graded': %s" % header)
	_expect(header.contains("0 live"), "header lacks '0 live': %s" % header)
	_expect(header.contains("no fresh probe"), "header does not say why nothing is live: %s" % header)
	# A fresh probe makes exactly that entry live.
	(entries[0] as Dictionary)["overlay"] = "live_probe"
	layer.build_from(entries, "live")
	_expect(layer.live_count() == 1, "probed entry not counted live (%d)" % layer.live_count())
	_expect(layer.header_text().contains("1 live") and not layer.header_text().contains("no fresh probe"),
		"fresh header wrong: %s" % layer.header_text())
	layer.queue_free()
	await process_frame


# ── Outbox ───────────────────────────────────────────────────────────────────

func _check_outbox_fail_closed() -> void:
	var box := WarRoomOutbox.new()
	box.outbox_path = ""
	var avail := box.availability()
	_expect(not bool(avail["ok"]), "an unconfigured outbox reported available")
	_expect(String(avail["reason"]).contains(WarRoomOutbox.OUTBOX_PATH_ENV), "no-outbox reason does not name the env var")
	var refused := box.assign("codex", "RIG · MSI")
	_expect(not bool(refused["ok"]), "assign wrote with no outbox configured")
	for bad in ["https://example.invalid/outbox.jsonl", "\\\\server\\share\\outbox.jsonl",
			"//server/share/outbox.jsonl", "res://outbox.jsonl", "relative/outbox.jsonl",
			ProjectSettings.globalize_path(FIXTURE_DIR + "/outbox.txt")]:
		_expect(not WarRoomOutbox.path_refusal(bad).is_empty(), "path not refused: %s" % bad)
	box.outbox_path = ProjectSettings.globalize_path(FIXTURE_DIR + "/no-such-dir/outbox.jsonl")
	_expect(not bool(box.availability()["ok"]), "an outbox in a missing folder reported available")
	# Env var configures it (the GSV_FLEET_TELEMETRY_PATH pattern).
	var path := ProjectSettings.globalize_path(FIXTURE_DIR + "/env-outbox.jsonl")
	OS.set_environment(WarRoomOutbox.OUTBOX_PATH_ENV, path)
	var from_env := WarRoomOutbox.new()
	_expect(from_env.outbox_path == path, "outbox env var not read (%s)" % from_env.outbox_path)
	OS.unset_environment(WarRoomOutbox.OUTBOX_PATH_ENV)


func _check_outbox_append() -> void:
	var box := WarRoomOutbox.new()
	box.outbox_path = ProjectSettings.globalize_path(FIXTURE_DIR + "/outbox.jsonl")
	_expect(bool(box.availability()["ok"]), "fixture outbox unavailable: %s" % String(box.availability()["reason"]))
	_expect(not bool(box.assign("nobody", "RIG · MSI")["ok"]), "assign accepted an unknown seat")
	_expect(not bool(box.assign("codex", "  \n ")["ok"]), "assign accepted an empty title")
	_expect(not FileAccess.file_exists(box.outbox_path), "a refused assign touched the outbox")
	var first := box.assign("codex", "RIG · MSI\nline two")
	_expect(bool(first["ok"]), "assign failed: %s" % String(first.get("reason", "")))
	var second := box.assign("ollama", "Atlas: Ollama (MSI)")
	_expect(bool(second["ok"]), "second assign failed")
	var lines := _read_lines(box.outbox_path)
	_expect(lines.size() == 2, "outbox has %d lines, expected 2 (append, not overwrite)" % lines.size())
	if lines.size() >= 1:
		var keys_in_order := lines[0].begins_with("{\"at\":") \
			and lines[0].find("\"from\"") < lines[0].find("\"kind\"") \
			and lines[0].find("\"kind\"") < lines[0].find("\"id\"") \
			and lines[0].find("\"id\"") < lines[0].find("\"to\"") \
			and lines[0].find("\"to\"") < lines[0].find("\"text\"") \
			and lines[0].find("\"text\"") < lines[0].find("\"via\"")
		_expect(keys_in_order, "order keys out of contract order: %s" % lines[0])
		var row: Variant = JSON.parse_string(lines[0])
		_expect(typeof(row) == TYPE_DICTIONARY, "outbox line is not JSON: %s" % lines[0])
		if typeof(row) == TYPE_DICTIONARY:
			var d := row as Dictionary
			_expect(d.size() == 7, "order has %d keys, expected 7" % d.size())
			_expect(String(d.get("from", "")) == "keath", "from = %s" % String(d.get("from", "")))
			_expect(String(d.get("kind", "")) == "order", "kind = %s" % String(d.get("kind", "")))
			_expect(String(d.get("id", "")).begins_with("o-") and String(d.get("id", "")) == String(first["id"]),
				"id = %s" % String(d.get("id", "")))
			_expect(String(d.get("to", "")) == "codex", "to = %s" % String(d.get("to", "")))
			_expect(String(d.get("text", "")) == "RIG · MSI line two", "text not one clean line: '%s'" % String(d.get("text", "")))
			_expect(String(d.get("via", "")) == "muse-war-room", "via = %s" % String(d.get("via", "")))
			_expect(String(d.get("at", "")).ends_with("Z") and String(d.get("at", "")).length() == 20,
				"at is not ISO UTC: %s" % String(d.get("at", "")))
	_expect(String(first["id"]) != String(second["id"]), "two orders shared an id")
	var long_title := "x".repeat(500)
	_expect(WarRoomOutbox.clean_text(long_title).length() == WarRoomOutbox.MAX_TEXT, "text not bounded")


func _check_order_status() -> void:
	var box := WarRoomOutbox.new()
	box.channel_path = ""
	_expect(String(box.order_status("o-1")["state"]) == "unknown", "no channel copy did not read unknown")
	box.channel_path = ProjectSettings.globalize_path(FIXTURE_DIR + "/missing-channel.jsonl")
	_expect(String(box.order_status("o-1")["state"]) == "unknown", "missing channel copy did not read unknown")
	box.channel_path = ProjectSettings.globalize_path(FIXTURE_DIR + "/channel.jsonl")
	_write(box.channel_path, "\n".join([
		"{\"at\":\"2026-11-08T18:00:00Z\",\"from\":\"keath\",\"kind\":\"order\",\"id\":\"o-7\",\"to\":\"codex\",\"text\":\"RIG · MSI\",\"via\":\"muse-war-room\"}",
		"not json at all",
		"{\"at\":\"2026-11-08T18:01:00Z\",\"from\":\"codex\",\"kind\":\"order-status\",\"id\":\"s-1\",\"order\":\"o-other\",\"status\":\"done\"}",
	]) + "\n")
	_expect(String(box.order_status("o-7")["state"]) == "relayed", "relayed order read %s" % String(box.order_status("o-7")["state"]))
	_expect(String(box.order_status("o-none")["state"]) == "pending", "absent order did not read pending")
	_write(box.channel_path, _read_text(box.channel_path)
		+ "{\"at\":\"2026-11-08T18:02:00Z\",\"from\":\"codex\",\"kind\":\"order-status\",\"order\":\"o-7\",\"status\":\"accepted\"}\n"
		+ "{\"at\":\"2026-11-08T18:03:00Z\",\"from\":\"codex\",\"kind\":\"order-status\",\"id\":\"o-7\",\"status\":\"done\"}\n")
	var status := box.order_status("o-7")
	_expect(String(status["state"]) == "done", "latest order-status not shown: %s" % str(status))
	_expect(String(status["detail"]).contains("codex"), "status detail lacks its sender: %s" % str(status))


# ── Room + tab ───────────────────────────────────────────────────────────────

func _check_room_idles() -> void:
	var room := (load(HOLO_ROOM_SCENE) as PackedScene).instantiate() as HoloRoom
	root.add_child(room)
	# Startup observations are real events (one sweep + pulse); then still.
	var idle := await _wait_idle(room, 12.0)
	_expect(idle, "HoloRoom never went idle after startup")
	# Input wakes it; it settles again on its own.
	room.pull_all(true)
	_expect(not room.is_idle(), "pull_all did not wake the room")
	idle = await _wait_idle(room, 6.0)
	_expect(idle, "HoloRoom did not settle after a pull")
	room.cycle_slice_axis()
	_expect(not room.is_idle(), "a slice-axis change did not start a sweep")
	idle = await _wait_idle(room, 6.0)
	_expect(idle, "HoloRoom did not settle after a sweep")
	# Ledger carries the honest seat + atlas lines.
	room.queue_free()
	await process_frame


func _check_room_seat_labels() -> void:
	var room := (load(HOLO_ROOM_SCENE) as PackedScene).instantiate() as HoloRoom
	root.add_child(room)
	await process_frame
	await process_frame
	var codex_label := room.seat_label_text("codex")
	_expect(codex_label.contains("seen 11-07 (not live)"), "codex seat label: %s" % codex_label)
	_expect(not codex_label.contains("\nlive\n"), "codex seat label still claims live: %s" % codex_label)
	_expect(room.seat_render_state("chatdev") == "dimmed", "chatdev web node not dimmed")
	# Pulling up cards: seat, rig, atlas entry are work items; a sense is not.
	var seat_card := room.pull_card("seat", "codex")
	_expect(String(seat_card.get("kind", "")) == "seat" and bool(seat_card.get("assignable", false)),
		"seat card not assignable: %s" % str(seat_card))
	_expect(room.seat_label_text("codex").begins_with("> "), "pulled seat not highlighted")
	var rig_card := room.pull_card("rig", "rig-msi")
	_expect(String(rig_card.get("title", "")) == "RIG · MSI" and bool(rig_card.get("assignable", false)),
		"rig card wrong: %s" % str(rig_card))
	var sense_card := room.pull_card("sense", "studio-health")
	_expect(not bool(sense_card.get("assignable", true)), "a sense card was offered as a work item")
	var atlas_reader := room.get_node_or_null("CapabilityAtlasReader") as CapabilityAtlasReader
	if atlas_reader != null:
		atlas_reader.read_now()
	var atlas_entries: Array = room.atlas_state().get("entries", [])
	if atlas_entries.is_empty():
		_fail("no atlas entries to pull up")
	else:
		var entry_id := String((atlas_entries[0] as Dictionary).get("id", ""))
		var atlas_card := room.pull_card("atlas", entry_id)
		_expect(String(atlas_card.get("kind", "")) == "atlas" and String(atlas_card.get("title", "")).begins_with("Atlas: "),
			"atlas card wrong: %s" % str(atlas_card))
	_expect(room.pull_card("atlas", "no-such-entry").is_empty(), "pull_card invented an atlas entry")
	room.queue_free()
	await process_frame


func _check_tab() -> void:
	var tab: Control = load(HOLO_TAB_SCRIPT).new()
	var box := WarRoomOutbox.new()
	box.outbox_path = ""
	box.channel_path = ""
	tab.set("outbox", box)
	tab.size = Vector2(1280, 900)
	root.add_child(tab)
	await process_frame
	await process_frame
	var viewport: SubViewport = tab.call("viewport")
	_expect(viewport.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE,
		"SubViewport update mode %d, expected UPDATE_WHEN_VISIBLE" % viewport.render_target_update_mode)
	var room: HoloRoom = tab.call("room")
	# Fail closed: nothing configured -> disabled, with the reason.
	var state: Dictionary = tab.call("assign_state")
	_expect(not bool(state["enabled"]), "Assign enabled with no outbox")
	_expect(String(state["reason"]).contains(WarRoomOutbox.OUTBOX_PATH_ENV), "disabled reason: %s" % String(state["reason"]))
	room.pull_card("rig", "rig-i3")
	await process_frame
	state = tab.call("assign_state")
	_expect(not bool(state["enabled"]), "Assign enabled with a card but no outbox")
	_expect(String(tab.call("card_label_text")).contains("RIG · i3"), "card label: %s" % String(tab.call("card_label_text")))
	var refused: Dictionary = tab.call("assign_pulled_card")
	_expect(not bool(refused["ok"]), "assign_pulled_card wrote with no outbox")
	# Configure the outbox: a sense card stays disabled, a rig card enables.
	box.outbox_path = ProjectSettings.globalize_path(FIXTURE_DIR + "/tab-outbox.jsonl")
	box.channel_path = ProjectSettings.globalize_path(FIXTURE_DIR + "/tab-channel.jsonl")
	room.pull_card("sense", "gateway-health")
	await process_frame
	state = tab.call("assign_state")
	_expect(not bool(state["enabled"]), "Assign enabled for a sense card")
	room.pull_card("seat", "serena")
	await process_frame
	_expect(String(tab.call("selected_seat")) == "serena", "pulling a seat did not select it as the target")
	state = tab.call("assign_state")
	_expect(bool(state["enabled"]), "Assign disabled with an outbox and a seat card: %s" % String(state["reason"]))
	room.pull_card("rig", "rig-msi")
	tab.call("select_seat", "codex")
	var written: Dictionary = tab.call("assign_pulled_card")
	_expect(bool(written.get("ok", false)), "tab assign failed: %s" % String(written.get("reason", "")))
	var lines := _read_lines(box.outbox_path)
	_expect(lines.size() == 1, "tab outbox has %d lines, expected 1" % lines.size())
	if lines.size() == 1:
		var d: Dictionary = JSON.parse_string(lines[0])
		_expect(String(d.get("to", "")) == "codex" and String(d.get("text", "")) == "RIG · MSI",
			"tab order wrong: %s" % lines[0])
	_expect(String(tab.call("order_label_text")).contains("unknown") or String(tab.call("order_label_text")).contains("missing"),
		"status before the channel copy exists: %s" % String(tab.call("order_label_text")))
	_write(box.channel_path, "{\"kind\":\"order-status\",\"order\":\"%s\",\"status\":\"accepted\",\"from\":\"codex\",\"at\":\"2026-11-08T18:05:00Z\"}\n" % String(written["id"]))
	tab.call("_poll_order_status")
	_expect(String(tab.call("order_label_text")).contains("accepted"), "status not shown: %s" % String(tab.call("order_label_text")))

	# Ledger: the status block is replaced in place, never re-appended.
	tab.call("_on_ledger_changed", "HOLOGRAM — observation_only · first")
	tab.call("_on_ledger_changed", "HOLOGRAM — observation_only · second")
	tab.call("_on_ledger_changed", "HOLOGRAM — observation_only · third [b]x[/b]")
	var ledger := String(tab.call("ledger_text"))
	_expect(ledger.count("HOLOGRAM — observation_only") == 1, "status block appended, not replaced:\n%s" % ledger)
	_expect(ledger.contains("third [b]x[/b]"), "ledger lost escaping or the latest block:\n%s" % ledger)
	_expect(not ledger.contains("first") and not ledger.contains("second"), "old status blocks remain:\n%s" % ledger)
	_expect(ledger.contains("ORDERS") and ledger.contains(String(written["id"])), "order event not in the ledger:\n%s" % ledger)
	tab.queue_free()
	await process_frame


func _check_war_room_scene() -> void:
	var scene := load(WAR_ROOM_SCENE) as PackedScene
	_expect(scene != null, "could not load %s" % WAR_ROOM_SCENE)
	if scene == null:
		return
	var app := scene.instantiate()
	root.add_child(app)
	await process_frame
	_expect(app.call("tab") != null, "war room did not mount the Hologram tab")
	_expect(Engine.max_fps == 30, "war room did not apply the budget (max_fps %d)" % Engine.max_fps)
	app.queue_free()
	await process_frame
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false


# ── Helpers ──────────────────────────────────────────────────────────────────

func _wait_idle(room: HoloRoom, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
		if room.is_idle():
			return true
	return room.is_idle()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	return text


func _read_lines(path: String) -> PackedStringArray:
	return _read_text(path).split("\n", false)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("could not write fixture %s" % path)
		return
	f.store_string(text)
	f.close()


func _clean_fixtures() -> void:
	for name in ["outbox.jsonl", "env-outbox.jsonl", "channel.jsonl", "tab-outbox.jsonl", "tab-channel.jsonl"]:
		var path: String = FIXTURE_DIR + "/" + String(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[war-room-test] PASS (%d checks)" % _checks)
		quit(0)
		return
	for message in _failures:
		printerr("[war-room-test] FAIL: %s" % message)
	print("[war-room-test] FAILED (%d of %d checks)" % [_failures.size(), _checks])
	quit(1)
