extends SceneTree

## Capability Atlas tests for the cockpit bake-off entry (Slice 5),
## following the #8 pattern: negative controls on fake data + an opt-in live
## canary that accepts live OR honest unavailable, never fabricated live.
##
## Covers the §7 contract (CAPABILITY-ATLAS-20261108.md): the static graded
## atlas file, the schema-pinned projection, the reader with its
## fleet-telemetry overlay, the holographic layer (pull-up, slice axes,
## discrepancy flag, unverified nodes), and the HoloRoom mounting.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/capability_atlas_test.gd
##
## Exit 0 = pass, 1 = fail. The live canary runs only with GSV_STUDIO_LIVE=1.
## Also run by tests/godot_smoke_gate.py as the "atlas" case.

const HOLO_ROOM_SCENE := "res://scenes/HoloRoom.tscn"
const ATLAS_DATA_PATH := "res://data/capability_atlas.json"

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_projection()
	_check_reader_overlay()
	_check_reader_file_states()
	_check_real_data_file()
	_check_layer()
	await _check_holo_room_atlas()
	if OS.get_environment("GSV_STUDIO_LIVE") == "1":
		await _check_live_canary()
	_finish()


func _good_doc() -> Dictionary:
	return {
		"schema": "kilocore.capability-atlas.v1",
		"generated_at": "2026-11-08T08:00:00Z",
		"source": "test fixture",
		"notes": "fixture",
		"entries": [
			{
				"id": "ollama-server-msi", "name": "Ollama server", "kind": "service",
				"machine": "msi", "grade": "Q", "cost_class": "tokenless",
				"state": "live", "evidence": "probe 2026-11-08",
				"can_do": "serve models",
				"telemetry": {"rig": "msi", "service": "ollama"},
			},
			{
				"id": "openclaw-msi", "name": "OpenClaw gateway", "kind": "service",
				"machine": "msi", "grade": "U", "cost_class": "mixed",
				"state": "live", "evidence": "probe 2026-11-08",
				"can_do": "agent gateway",
				"discrepancy": "hub #13 UNVERIFIED vs Lane B LIVE; entry follows Lane B",
				"telemetry": {"rig": "msi", "service": "openclaw"},
			},
			{
				"id": "oh-my-pi-msi", "name": "oh-my-pi", "kind": "harness",
				"machine": "msi", "grade": "D", "cost_class": "tokenless",
				"state": "not_detected", "evidence": "NOT INSTALLED 2026-11-08",
				"can_do": "bench-candidate label, not Pi",
			},
			{
				"id": "claude-i3", "name": "Claude Code", "kind": "agent",
				"machine": "i3", "grade": "C", "cost_class": "cloud",
				"state": "live", "evidence": "4 processes 2026-11-08",
				"can_do": "cloud coding seat",
				"telemetry": {"rig": "i3", "seat": "claude"},
			},
		],
	}


func _check_projection() -> void:
	# A valid document parses: every field admitted, telemetry maps kept.
	var parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(_good_doc()))
	if not bool(parsed.get("ok", false)):
		_fail("valid atlas rejected: %s" % str(parsed.get("reason", "")))
		return
	var atlas: Dictionary = parsed["atlas"]
	var entries: Array = atlas["entries"]
	if entries.size() != 4:
		_fail("valid atlas parsed %d entries, expected 4" % entries.size())
		return
	var openclaw: Dictionary = entries[1]
	if String(openclaw.get("discrepancy", "")).is_empty():
		_fail("OpenClaw discrepancy flag not admitted")
	if String((openclaw.get("telemetry", {}) as Dictionary).get("service", "")) != "openclaw":
		_fail("OpenClaw telemetry mapping not admitted")
	var omp: Dictionary = entries[2]
	if String(omp.get("grade", "")) != "D" or String(omp.get("state", "")) != "not_detected":
		_fail("oh-my-pi did not keep grade D / not_detected")

	# Negative controls: bad schema, oversized body, malformed JSON,
	# malformed entry, missing machine, unknown grade, unknown cost class.
	var wrong_schema := _good_doc()
	wrong_schema["schema"] = "kilocore.capability-atlas.v99"
	var rejected := CapabilityAtlasProjection.parse_atlas(JSON.stringify(wrong_schema))
	if bool(rejected.get("ok", true)) or String(rejected.get("reason", "")) != "unknown_atlas_schema":
		_fail("wrong-schema atlas was not rejected as unknown_atlas_schema")
	var big := "x".repeat(140000)
	var oversized := CapabilityAtlasProjection.parse_atlas(big)
	if bool(oversized.get("ok", true)) or String(oversized.get("reason", "")) != "atlas_response_too_large":
		_fail("oversized atlas was not rejected as atlas_response_too_large")
	var malformed := CapabilityAtlasProjection.parse_atlas("{not json")
	if bool(malformed.get("ok", true)) or String(malformed.get("reason", "")) != "malformed_json":
		_fail("malformed atlas was not rejected as malformed_json")
	var bad_entry := _good_doc()
	(bad_entry["entries"] as Array)[0] = "not a dict"
	var bad_entry_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(bad_entry))
	if bool(bad_entry_parsed.get("ok", true)) or String(bad_entry_parsed.get("reason", "")) != "malformed_entry":
		_fail("malformed entry was not rejected as malformed_entry")
	var no_machine := _good_doc()
	((no_machine["entries"] as Array)[0] as Dictionary).erase("machine")
	var no_machine_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(no_machine))
	if bool(no_machine_parsed.get("ok", true)) or String(no_machine_parsed.get("reason", "")) != "missing_machine":
		_fail("entry without a machine was not rejected as missing_machine")
	var bad_grade := _good_doc()
	((bad_grade["entries"] as Array)[0] as Dictionary)["grade"] = "Z"
	var bad_grade_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(bad_grade))
	if bool(bad_grade_parsed.get("ok", true)) or String(bad_grade_parsed.get("reason", "")) != "unknown_grade":
		_fail("unknown grade was not rejected as unknown_grade")
	var bad_cost := _good_doc()
	((bad_cost["entries"] as Array)[0] as Dictionary)["cost_class"] = "free"
	var bad_cost_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(bad_cost))
	if bool(bad_cost_parsed.get("ok", true)) or String(bad_cost_parsed.get("reason", "")) != "unknown_cost_class":
		_fail("unknown cost class was not rejected as unknown_cost_class")
	var bad_kind := _good_doc()
	((bad_kind["entries"] as Array)[0] as Dictionary)["kind"] = "mystery"
	var bad_kind_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(bad_kind))
	if bool(bad_kind_parsed.get("ok", true)) or String(bad_kind_parsed.get("reason", "")) != "unknown_kind":
		_fail("unknown kind was not rejected as unknown_kind")
	var bad_state := _good_doc()
	((bad_state["entries"] as Array)[0] as Dictionary)["state"] = "haunted"
	var bad_state_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(bad_state))
	if bool(bad_state_parsed.get("ok", true)) or String(bad_state_parsed.get("reason", "")) != "unknown_state":
		_fail("unknown state was not rejected as unknown_state")
	var dup := _good_doc()
	(dup["entries"] as Array).append(((dup["entries"] as Array)[0] as Dictionary).duplicate(true))
	var dup_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(dup))
	if bool(dup_parsed.get("ok", true)) or String(dup_parsed.get("reason", "")) != "duplicate_entry_id":
		_fail("duplicate entry id was not rejected as duplicate_entry_id")
	var too_many := _good_doc()
	var many: Array = []
	for i in 129:
		var e: Dictionary = ((too_many["entries"] as Array)[0] as Dictionary).duplicate(true)
		e["id"] = "entry-%d" % i
		many.append(e)
	too_many["entries"] = many
	var too_many_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(too_many))
	if bool(too_many_parsed.get("ok", true)) or String(too_many_parsed.get("reason", "")) != "too_many_entries":
		_fail("129-entry atlas was not rejected as too_many_entries")

	# Lenient on length, strict on shape: over-long evidence is truncated,
	# not fatal; a malformed telemetry map is dropped, not fatal.
	var long_evidence := _good_doc()
	((long_evidence["entries"] as Array)[0] as Dictionary)["evidence"] = "e".repeat(500)
	var long_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(long_evidence))
	if not bool(long_parsed.get("ok", false)):
		_fail("over-long evidence made the atlas fail")
	else:
		var long_entries: Array = (long_parsed["atlas"] as Dictionary)["entries"]
		if String((long_entries[0] as Dictionary).get("evidence", "")).length() > 300:
			_fail("over-long evidence was not truncated to 300 chars")
	var bad_map := _good_doc()
	((bad_map["entries"] as Array)[0] as Dictionary)["telemetry"] = {"rig": "nowhere", "service": "ollama"}
	var bad_map_parsed := CapabilityAtlasProjection.parse_atlas(JSON.stringify(bad_map))
	if not bool(bad_map_parsed.get("ok", false)):
		_fail("malformed telemetry map made the atlas fail")
	else:
		var map_entries: Array = (bad_map_parsed["atlas"] as Dictionary)["entries"]
		if not ((map_entries[0] as Dictionary).get("telemetry", {}) as Dictionary).is_empty():
			_fail("malformed telemetry map was not dropped")


func _fresh_telemetry() -> Dictionary:
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	return {
		"schema": "kilocore.fleet-telemetry.v1",
		"generated_at": "2026-11-08T07:50:42Z",
		"generated_unix_ms": now_ms,
		"probe_host": "MSI-KATANA",
		"rigs": {
			"msi": {
				"state": "live",
				"services": {"ollama": "up", "openclaw": "down", "studio": "unknown"},
			},
			"i3": {"state": "live", "seats": "claude,claude,ollama"},
		},
	}


func _check_reader_overlay() -> void:
	var entries: Array = (_good_doc()["entries"] as Array).duplicate(true)
	# Fresh telemetry: "up" -> live + live_probe; "down" -> unavailable +
	# live_probe; "unknown" -> static state kept; seat present -> live.
	var overlaid := CapabilityAtlasReader.apply_overlay(entries, _fresh_telemetry(), true)
	if overlaid.size() != 4:
		_fail("overlay changed the entry count")
		return
	if String((overlaid[0] as Dictionary).get("state", "")) != "live":
		_fail("ollama with an 'up' probe did not read live")
	if String((overlaid[0] as Dictionary).get("overlay", "")) != "live_probe":
		_fail("ollama with an 'up' probe was not flagged live_probe")
	if String((overlaid[1] as Dictionary).get("state", "")) != "unavailable":
		_fail("openclaw with a 'down' probe did not read unavailable")
	if String((overlaid[1] as Dictionary).get("overlay", "")) != "live_probe":
		_fail("openclaw with a 'down' probe was not flagged live_probe")
	if String((overlaid[2] as Dictionary).get("state", "")) != "not_detected":
		_fail("oh-my-pi (no mapping) changed state under the overlay")
	if String((overlaid[2] as Dictionary).get("overlay", "")) != "static_only":
		_fail("oh-my-pi (no mapping) was not flagged static_only")
	if String((overlaid[3] as Dictionary).get("state", "")) != "live":
		_fail("claude-i3 with its seat present did not read live")
	if String((overlaid[3] as Dictionary).get("overlay", "")) != "live_probe":
		_fail("claude-i3 with its seat present was not flagged live_probe")

	# Stale telemetry never makes anything live: every entry keeps its
	# static state, and no entry claims a live probe.
	var stale := CapabilityAtlasReader.apply_overlay(entries, _fresh_telemetry(), false)
	for entry in stale:
		if String((entry as Dictionary).get("overlay", "")) != "static_only":
			_fail("stale telemetry left a live_probe overlay on %s" % String((entry as Dictionary).get("id", "?")))
	if String((stale[0] as Dictionary).get("state", "")) != "live":
		_fail("stale telemetry changed the static live state")
	# Absent seat proves nothing: the entry keeps its static state.
	var no_seat_telemetry := _fresh_telemetry()
	((no_seat_telemetry["rigs"] as Dictionary)["i3"] as Dictionary)["seats"] = "ollama"
	var no_seat := CapabilityAtlasReader.apply_overlay(entries, no_seat_telemetry, true)
	if String((no_seat[3] as Dictionary).get("overlay", "")) != "static_only":
		_fail("absent seat was treated as a probe verdict")
	# Empty telemetry: everything static.
	var empty := CapabilityAtlasReader.apply_overlay(entries, {}, true)
	for entry in empty:
		if String((entry as Dictionary).get("overlay", "")) != "static_only":
			_fail("empty telemetry left a live_probe overlay on %s" % String((entry as Dictionary).get("id", "?")))


func _write_text_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("could not open %s for writing" % path)
		return
	f.store_string(text)
	f.close()


func _check_reader_file_states() -> void:
	# Fresh static + fresh telemetry -> live; static + stale telemetry ->
	# stale; malformed static -> unavailable; missing static -> unavailable.
	# Bounded history: two reads leave the entry count identical.
	var atlas_path := "user://capability-atlas-test.json"
	var telemetry_path := "user://fleet-telemetry-atlas-test.json"
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var telemetry := _fresh_telemetry()
	var reader := CapabilityAtlasReader.new()
	reader.atlas_path = atlas_path
	reader.telemetry_path = telemetry_path
	root.add_child(reader)

	_write_text_file(atlas_path, JSON.stringify(_good_doc()))
	_write_text_file(telemetry_path, JSON.stringify(telemetry))
	reader.read_now()
	var fresh := reader.current_atlas()
	if String(fresh.get("state", "")) != "live":
		_fail("fresh atlas + fresh telemetry did not read as live (state=%s error=%s)" % [str(fresh.get("state", "")), str(fresh.get("error", ""))])
	if (fresh.get("entries", []) as Array).size() != 4:
		_fail("fresh atlas read %d entries, expected 4" % (fresh.get("entries", []) as Array).size())
	if int(fresh.get("live_probe_entries", -1)) != 3:
		_fail("fresh overlay counted %d live-probe entries, expected 3" % int(fresh.get("live_probe_entries", -1)))
	if int(fresh.get("unverified_entries", -1)) != 1:
		_fail("fresh atlas counted %d unverified entries, expected 1" % int(fresh.get("unverified_entries", -1)))
	reader.read_now()
	var fresh_again := reader.current_atlas()
	if (fresh_again.get("entries", []) as Array).size() != 4:
		_fail("second read grew or shrank the atlas (bounded history broken)")

	telemetry["generated_unix_ms"] = now_ms - 600000
	_write_text_file(telemetry_path, JSON.stringify(telemetry))
	reader.read_now()
	var stale := reader.current_atlas()
	if String(stale.get("state", "")) != "stale":
		_fail("10-minute-old telemetry did not read as stale (state=%s)" % str(stale.get("state", "")))
	if int(stale.get("live_probe_entries", -1)) != 0:
		_fail("stale telemetry still claimed %d live-probe entries" % int(stale.get("live_probe_entries", -1)))

	_write_text_file(atlas_path, "{bad json")
	reader.read_now()
	var broken := reader.current_atlas()
	if String(broken.get("state", "")) != "unavailable":
		_fail("malformed atlas did not read as unavailable (state=%s)" % str(broken.get("state", "")))

	DirAccess.remove_absolute(atlas_path)
	DirAccess.remove_absolute(telemetry_path)
	reader.read_now()
	var missing := reader.current_atlas()
	if String(missing.get("state", "")) != "unavailable":
		_fail("missing atlas did not read as unavailable (state=%s)" % str(missing.get("state", "")))

	reader.queue_free()


func _check_real_data_file() -> void:
	# The shipped static file parses under the contract and carries the
	# §7 shape: 75 entries, the OpenClaw discrepancy, and the unverified
	# nodes present as explicit D rows — never omitted.
	if not FileAccess.file_exists(ATLAS_DATA_PATH):
		_fail("shipped atlas data file missing: %s" % ATLAS_DATA_PATH)
		return
	var f := FileAccess.open(ATLAS_DATA_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed := CapabilityAtlasProjection.parse_atlas(text)
	if not bool(parsed.get("ok", false)):
		_fail("shipped atlas data file rejected: %s" % str(parsed.get("reason", "")))
		return
	var entries: Array = (parsed["atlas"] as Dictionary)["entries"]
	if entries.size() != 75:
		_fail("shipped atlas has %d entries, expected 75" % entries.size())
		return
	var by_id := {}
	for entry in entries:
		by_id[String((entry as Dictionary).get("id", ""))] = entry
	for required in ["openclaw-msi", "oh-my-pi-msi", "wrapper-msi", "soulclaw", "metaclaw", "ollama-server-msi", "ollama-l9", "icecast-xanadu"]:
		if not by_id.has(required):
			_fail("shipped atlas is missing entry %s" % required)
	if by_id.has("openclaw-msi"):
		if String((by_id["openclaw-msi"] as Dictionary).get("discrepancy", "")).is_empty():
			_fail("shipped OpenClaw entry carries no discrepancy flag")
		if String((by_id["openclaw-msi"] as Dictionary).get("cost_class", "")) != "mixed":
			_fail("shipped OpenClaw entry cost class is not mixed")
	for unverified in ["oh-my-pi-msi", "wrapper-msi", "soulclaw", "metaclaw"]:
		if by_id.has(unverified):
			var e: Dictionary = by_id[unverified]
			if String(e.get("grade", "")) != "D" or String(e.get("state", "")) != "not_detected":
				_fail("unverified entry %s is not D / not_detected" % unverified)


func _check_layer() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 5.0)
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await process_frame

	var layer := CapabilityAtlasLayer.new()
	root.add_child(layer)
	await process_frame
	var entries: Array = (_good_doc()["entries"] as Array).duplicate(true)
	layer.build_from(entries)
	if layer.entry_count() != 4:
		_fail("atlas layer built %d entries, expected 4" % layer.entry_count())
	if layer.unverified_count() != 1:
		_fail("atlas layer counted %d unverified entries, expected 1" % layer.unverified_count())
	if layer.header_node() == null:
		_fail("atlas layer has no header node")
	# Collapsed at rest: no entry nodes visible until pulled.
	if layer.visible_count() != 0:
		_fail("collapsed atlas layer showed %d entries" % layer.visible_count())
	# Slice axes: machine, cost class, grade — each filters the shelf.
	if not layer.set_slice_view("msi"):
		_fail("atlas layer rejected the 'msi' slice view")
	layer.set_pulled(true)
	layer.update_frame(1.0, camera)
	if layer.visible_count() != 3:
		_fail("msi slice showed %d entries, expected 3" % layer.visible_count())
	layer.set_slice_view("proven")
	if layer.visible_count() != 2:
		_fail("proven slice showed %d entries, expected 2" % layer.visible_count())
	layer.set_slice_view("unverified")
	if layer.visible_count() != 1:
		_fail("unverified slice showed %d entries, expected 1" % layer.visible_count())
	layer.set_slice_view("cloud")
	if layer.visible_count() != 1:
		_fail("cloud slice showed %d entries, expected 1" % layer.visible_count())
	layer.set_slice_view("all")
	if layer.visible_count() != 4:
		_fail("all slice showed %d entries, expected 4" % layer.visible_count())
	if layer.set_slice_view("no-such-view"):
		_fail("atlas layer accepted an unknown slice view")
	# Pull-up: one long frame drives pull to its target, the shelf moves
	# along camera-forward and scales up (HoloLayer's pull semantics).
	if not is_equal_approx(layer.pull, 1.0):
		_fail("atlas layer pull did not reach 1.0 after a full frame")
	if is_equal_approx(layer.position.z, CapabilityAtlasLayer.BASE_POSITION.z):
		_fail("pulled atlas layer did not move (pos = %s)" % str(layer.position))
	if layer.scale.x < 1.5:
		_fail("pulled atlas layer did not scale up (scale = %f)" % layer.scale.x)
	# Rebuild is idempotent: no node accumulation across rebuilds (bounded).
	layer.build_from(entries)
	if layer.entry_count() != 4 or layer.visible_count() != 4:
		_fail("atlas rebuild changed the counts (%d entries, %d visible)" % [layer.entry_count(), layer.visible_count()])
	layer.set_pulled(false)
	layer.update_frame(1.0, camera)
	if layer.visible_count() != 0:
		_fail("released atlas layer still showed %d entries" % layer.visible_count())

	layer.queue_free()
	camera.queue_free()


func _check_holo_room_atlas() -> void:
	var scene := load(HOLO_ROOM_SCENE) as PackedScene
	if scene == null:
		_fail("could not load %s" % HOLO_ROOM_SCENE)
		return
	var room := scene.instantiate() as HoloRoom
	if room == null:
		_fail("HoloRoom scene did not instantiate as HoloRoom")
		return
	root.add_child(room)
	await process_frame
	await process_frame
	await process_frame
	if room.get_node_or_null("CapabilityAtlasReader") == null:
		_fail("HoloRoom did not mount the atlas reader")
	if room.get_node_or_null("CapabilityAtlasLayer") == null:
		_fail("HoloRoom did not mount the atlas layer")
	# The room's own registry layers are untouched by the atlas (still 14).
	if room.layer_count() != 14:
		_fail("HoloRoom built %d layers, expected 14" % room.layer_count())
	var reader := room.get_node_or_null("CapabilityAtlasReader") as CapabilityAtlasReader
	if reader != null:
		reader.read_now()
		if room.atlas_entry_count() != 75:
			_fail("HoloRoom atlas has %d entries, expected 75" % room.atlas_entry_count())
		if String(room.atlas_state().get("state", "")) not in ["live", "stale", "unavailable"]:
			_fail("HoloRoom atlas state is dishonest: %s" % str(room.atlas_state().get("state", "")))
		var first_slice := room.cycle_atlas_slice()
		if first_slice != "msi":
			_fail("first atlas slice cycle landed on '%s', expected 'msi'" % first_slice)
	room.queue_free()
	await process_frame


func _check_live_canary() -> void:
	# Opt-in only (GSV_STUDIO_LIVE=1). Accepts live OR honest unavailable —
	# never fabricated live. Reads the real static file + the real fleet
	# snapshot; the atlas must report one of its honest states and, when it
	# reports live/stale, the full 75-entry inventory.
	var reader := CapabilityAtlasReader.new()
	root.add_child(reader)
	reader.read_now()
	var atlas := reader.current_atlas()
	var state := String(atlas.get("state", "unknown"))
	print("[atlas-test] live canary: atlas state = %s, entries = %d, live-probe = %d" % [
		state, (atlas.get("entries", []) as Array).size(), int(atlas.get("live_probe_entries", -1)),
	])
	if state != "live" and state != "stale" and state != "unavailable":
		_fail("live canary: atlas stayed '%s'" % state)
	if (state == "live" or state == "stale") and (atlas.get("entries", []) as Array).size() != 75:
		_fail("live canary: atlas reported %d entries, expected 75" % (atlas.get("entries", []) as Array).size())
	reader.queue_free()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[atlas-test] PASS")
		quit(0)
		return
	for message in _failures:
		printerr("[atlas-test] FAIL: %s" % message)
	print("[atlas-test] FAILED (%d)" % _failures.size())
	quit(1)
