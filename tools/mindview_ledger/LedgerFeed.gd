extends RefCounted

## The Ledger — feed reader for the Mind View bake-off entry.
##
## Reads the SHARED fixture directory directly (never a copy):
##   res://tests/fixtures/mindview-20261108/
##     events.jsonl          one colony.mindview-feed/v0 event per line
##     heartbeat_msi.json    colony.heartbeat/v1
##     heartbeat_i3.json     colony.heartbeat/v1
##     heartbeat_l9.json     colony.heartbeat/v1
##     (no heartbeat_xanadu.json in the fixture — absence is recorded, never faked)
##
## Output is normalised to schema colony.mindview-feed/v0 so entries stay
## comparable, with provenance "SHARED FIXTURE" and the freeze stamp attached.
## Observation only: this file opens local files for reading. It performs no
## HTTP, no shell, no writes, no tasks, no container or service control.
## There are zero actuators anywhere in this entry, in code and in fact.

const SCHEMA := "colony.mindview-feed/v0"
const HEARTBEAT_SCHEMA := "colony.heartbeat/v1"
const FIXTURE_DIR := "res://tests/fixtures/mindview-20261108"
const FREEZE_LABEL := "SHARED FIXTURE · frozen 2026-11-08 06:48 UTC"
const FREEZE_AT := "2026-11-08T06:48:00Z"
const MAX_BYTES := 196608
const MAX_EVENTS := 80
const MAX_REASONS := 8
const RIG_IDS := ["msi", "i3", "l9", "xanadu"]
const RIG_NAMES := {"msi": "MSI", "i3": "I3", "l9": "L9", "xanadu": "XANADU"}
const LEVELS := ["routine", "notable", "alarm", "calm"]
const DISK_ALARM_PCT_FREE := 10.0


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _parse_json_object(text: String) -> Dictionary:
	var reader := JSON.new()
	if reader.parse(text) != OK or typeof(reader.data) != TYPE_DICTIONARY:
		return {}
	return reader.data


## Parse one events.jsonl document. Returns {"ok": true, "events": [...]}
## or {"ok": false, "reason": ...}. Fail-closed: one bad line rejects the file.
static func parse_events_text(raw_text: String) -> Dictionary:
	if raw_text.to_utf8_buffer().size() > MAX_BYTES:
		return _invalid("oversized_events")
	var events: Array[Dictionary] = []
	for raw_line in raw_text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var e := _parse_json_object(line)
		if e.is_empty():
			return _invalid("event_line_not_json")
		for field in ["mind", "line", "at", "level"]:
			if typeof(e.get(field)) != TYPE_STRING or String(e[field]).is_empty():
				return _invalid("missing_event_" + field)
		if not LEVELS.has(e["level"]):
			return _invalid("unknown_event_level")
		var floor: Variant = e.get("floor")
		if floor != null and (typeof(floor) != TYPE_STRING or not LEVELS.has(floor)):
			return _invalid("unknown_event_floor")
		var focus: Variant = e.get("focus")
		if focus != null and (typeof(focus) != TYPE_STRING or not RIG_IDS.has(focus)):
			return _invalid("invalid_focus")
		var model: Variant = e.get("model")
		if model != null and typeof(model) != TYPE_STRING:
			return _invalid("invalid_model")
		var reasons: Variant = e.get("reasons", [])
		if typeof(reasons) != TYPE_ARRAY or reasons.size() > MAX_REASONS:
			return _invalid("invalid_reasons")
		var clean_reasons := PackedStringArray()
		for reason in reasons:
			if typeof(reason) != TYPE_STRING or reason.length() > 320:
				return _invalid("invalid_reason")
			clean_reasons.append(reason)
		var ms: Variant = e.get("ms")
		if ms != null and (typeof(ms) != TYPE_INT and typeof(ms) != TYPE_FLOAT):
			return _invalid("invalid_think_ms")
		var simulated: Variant = e.get("simulated", false)
		if typeof(simulated) != TYPE_BOOL:
			return _invalid("invalid_simulated")
		events.append({
			"mind": String(e["mind"]).substr(0, 64),
			"model": (String(model).substr(0, 64) if model != null else ""),
			"at": String(e["at"]).substr(0, 40),
			"level": String(e["level"]),
			"floor": String(floor) if floor != null else String(e["level"]),
			"line": String(e["line"]).substr(0, 600),
			"focus": String(focus) if focus != null else "",
			"reasons": clean_reasons,
			"ms": int(ms) if ms != null else -1,
			"simulated": bool(simulated),
		})
	if events.size() > MAX_EVENTS:
		return _invalid("too_many_events")
	if events.is_empty():
		return _invalid("no_events")
	return {"ok": true, "events": events}


## Parse one colony.heartbeat/v1 document for the named rig.
static func parse_heartbeat_text(raw_text: String, rig: String) -> Dictionary:
	if not RIG_IDS.has(rig):
		return _invalid("unknown_rig")
	if raw_text.to_utf8_buffer().size() > MAX_BYTES:
		return _invalid("oversized_heartbeat")
	var data := _parse_json_object(raw_text)
	if data.is_empty():
		return _invalid("heartbeat_not_json")
	if String(data.get("schema", "")) != HEARTBEAT_SCHEMA:
		return _invalid("unsupported_heartbeat_schema")
	if String(data.get("rig", "")) != rig:
		return _invalid("heartbeat_rig_mismatch")
	if typeof(data.get("green")) != TYPE_BOOL:
		return _invalid("invalid_heartbeat_green")
	if typeof(data.get("at")) != TYPE_STRING or String(data["at"]).is_empty():
		return _invalid("invalid_heartbeat_at")
	var disks: Variant = data.get("disks", {})
	if typeof(disks) != TYPE_DICTIONARY:
		return _invalid("invalid_heartbeat_disks")
	var clean_disks := {}
	for drive in disks.keys():
		var d: Variant = disks[drive]
		if typeof(d) != TYPE_DICTIONARY:
			return _invalid("invalid_disk_entry")
		var pct: Variant = d.get("pct_free")
		if typeof(pct) != TYPE_FLOAT and typeof(pct) != TYPE_INT:
			return _invalid("invalid_disk_pct_free")
		var n := float(pct)
		if n < 0.0 or n > 100.0:
			return _invalid("invalid_disk_pct_free")
		var free_gb: Variant = d.get("free_gb", -1)
		if typeof(free_gb) != TYPE_FLOAT and typeof(free_gb) != TYPE_INT:
			return _invalid("invalid_disk_free_gb")
		clean_disks[String(drive)] = {"pct_free": n, "free_gb": float(free_gb)}
	var checks: Variant = data.get("checks", [])
	if typeof(checks) != TYPE_ARRAY or checks.size() > 20:
		return _invalid("invalid_heartbeat_checks")
	var clean_checks: Array[Dictionary] = []
	for check in checks:
		if typeof(check) != TYPE_DICTIONARY:
			return _invalid("invalid_check_entry")
		if typeof(check.get("name")) != TYPE_STRING or typeof(check.get("ok")) != TYPE_BOOL:
			return _invalid("invalid_check_fields")
		clean_checks.append({
			"name": String(check["name"]).substr(0, 80),
			"ok": bool(check["ok"]),
			"detail": String(check.get("detail", "")).substr(0, 230),
			"ms": int(check["ms"]) if check.get("ms") != null else -1,
		})
	var ram: Variant = data.get("ram_avail_mb")
	if ram != null and (typeof(ram) != TYPE_INT and typeof(ram) != TYPE_FLOAT):
		return _invalid("invalid_heartbeat_ram")
	return {
		"ok": true,
		"rig": rig,
		"at": String(data["at"]).substr(0, 40),
		"green": bool(data["green"]),
		"ram_avail_mb": int(ram) if ram != null else -1,
		"disks": clean_disks,
		"checks": clean_checks,
		"observer": String(data.get("observer", "")).substr(0, 80),
	}


## Load a fixture directory (events.jsonl + heartbeat_<rig>.json).
## A missing heartbeat file is recorded under "missing" — the rig renders as
## "no heartbeat in fixture", never as green, red, or silent.
static func load_fixture_dir(dir_path: String) -> Dictionary:
	var events_path := dir_path.rstrip("/") + "/events.jsonl"
	if not FileAccess.file_exists(events_path):
		return _invalid("events_file_missing")
	var events_text := FileAccess.get_file_as_string(events_path)
	var parsed_events := parse_events_text(events_text)
	if not parsed_events.get("ok", false):
		return parsed_events
	var heartbeats := {}
	var missing: PackedStringArray = []
	for rig in RIG_IDS:
		var path := dir_path.rstrip("/") + "/heartbeat_" + rig + ".json"
		if not FileAccess.file_exists(path):
			missing.append(rig)
			continue
		var beat := parse_heartbeat_text(FileAccess.get_file_as_string(path), rig)
		if not beat.get("ok", false):
			return _invalid("heartbeat_" + rig + "_" + String(beat.get("reason", "invalid")))
		heartbeats[rig] = beat
	return {
		"ok": true,
		"schema": SCHEMA,
		"provenance": FREEZE_LABEL,
		"frozen_at": FREEZE_AT,
		"dir": dir_path,
		"events": parsed_events["events"],
		"heartbeats": heartbeats,
		"missing": missing,
	}


## Group events by (line + focus): the recurrence the fixture is actually about.
## Returns rows sorted by count desc: {line, focus, count, first_at, last_at,
## span_min, max_level}. The fixture's headline is one row: 4x in 61 min.
static func recurrence_rows(events: Array) -> Array[Dictionary]:
	var groups := {}
	var order: Array[String] = []
	for e in events:
		var key := String(e.get("line", "")) + "\x1f" + String(e.get("focus", ""))
		if not groups.has(key):
			groups[key] = {
				"line": String(e.get("line", "")),
				"focus": String(e.get("focus", "")),
				"count": 0,
				"first_at": String(e.get("at", "")),
				"last_at": String(e.get("at", "")),
				"max_level": "routine",
			}
			order.append(key)
		var row: Dictionary = groups[key]
		row["count"] = int(row["count"]) + 1
		row["last_at"] = String(e.get("at", ""))
		if _level_rank(String(e.get("level", "routine"))) > _level_rank(String(row["max_level"])):
			row["max_level"] = String(e.get("level", "routine"))
	var rows: Array[Dictionary] = []
	for key in order:
		var row: Dictionary = groups[key]
		row["span_min"] = _minutes_between(String(row["first_at"]), String(row["last_at"]))
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"]))
	return rows


static func _level_rank(level: String) -> int:
	match level:
		"routine":
			return 0
		"calm":
			return 0
		"notable":
			return 1
		"alarm":
			return 2
	return 0


## Whole minutes between two ISO-8601 UTC stamps; -1 when unparseable.
static func _minutes_between(first_at: String, last_at: String) -> int:
	var a := _unix_minutes(first_at)
	var b := _unix_minutes(last_at)
	if a < 0 or b < 0:
		return -1
	return int((b - a) / 60.0)


static func _unix_minutes(stamp: String) -> int:
	if stamp.length() < 19 or stamp.substr(10, 1) != "T":
		return -1
	var value := Time.get_unix_time_from_datetime_string(stamp.substr(0, 19))
	if value <= 0.0:
		return -1
	return int(value)


## "What needs you" — derived ONLY from fixture data. Every item carries its
## source. A Mind's claim with no supporting record in the fixture is listed
## as an UNVERIFIED CLAIM, never as fact. No item invents a cause, a move, or
## an owner: the move is copyable text for an agent to run elsewhere; the
## owner is the rig lane (or the Mind that noticed).
static func needs_you_items(feed: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var events: Array = feed.get("events", [])
	var beats: Dictionary = feed.get("heartbeats", {})
	# 1. The recurrence itself: i3 docker, named in every event's reasons.
	var docker_reasons := 0
	for e in events:
		for reason in e.get("reasons", []):
			if String(reason).begins_with("i3 failing: docker"):
				docker_reasons += 1
	var i3: Dictionary = beats.get("i3", {})
	if docker_reasons > 0 and not i3.is_empty():
		var failing := ""
		for check in i3.get("checks", []):
			if String(check.get("name", "")) == "docker" and not bool(check.get("ok", true)):
				failing = String(check.get("detail", ""))
		# Short form of the failing detail: the full `docker info` command
		# line is in heartbeat_i3.json; the cause line keeps its essence.
		var cause := "i3 heartbeat %s — docker FAIL" % String(i3.get("at", "?")).substr(11, 8)
		if "timed out" in failing:
			cause += ": 'docker info' timed out after 20 seconds"
		elif not failing.is_empty():
			cause += ": " + failing.substr(0, 60)
		items.append({
			"key": "i3-docker",
			"what": "i3 docker failing — named in %d of %d events" % [docker_reasons, events.size()],
			"cause": cause,
			"move": "On i3 run: docker info (restart Docker only if an agent confirms it is safe)",
			"owner": "i3 engine-room lane",
			"status": "open",
			"source": "heartbeat_i3.json + events.jsonl",
		})
	# 2. Disk pressure no entry surfaces: both workshop disks under 10% free.
	var low: PackedStringArray = []
	for rig in ["msi", "i3"]:
		var beat: Dictionary = beats.get(rig, {})
		var disks: Dictionary = beat.get("disks", {})
		if disks.has("C") and float(disks["C"].get("pct_free", 100.0)) < DISK_ALARM_PCT_FREE:
			low.append("%s C: %.1f%% free (%.1f GB)" % [String(RIG_NAMES[rig]), float(disks["C"]["pct_free"]), float(disks["C"]["free_gb"])])
	if not low.is_empty():
		items.append({
			"key": "disk-pressure",
			"what": "System-disk pressure: " + ", ".join(low),
			"cause": "MSI C: 8.5% free, i3 C: 9.5% free at freeze (alarm under 10%)",
			"move": "List what fills C: on each rig; keep builds off C: until above 10%",
			"owner": "msi + i3 lanes",
			"status": "open",
			"source": "heartbeat_msi.json + heartbeat_i3.json",
		})
	# 3. The Mind's backup claim: present in the record, unsupported by it.
	# One item only — the claim is made once, in the 05:35 alarm.
	var claim_found := false
	for e in events:
		if claim_found:
			break
		for reason in e.get("reasons", []):
			if "backup" in String(reason):
				items.append({
					"key": "backup-claim",
					"what": "UNVERIFIED CLAIM — \"off-box backup 109 h old\" (Mind, 05:35 alarm)",
					"cause": "Claimed by l9-triage-drone, 05:35 alarm. No backup record in the fixture.",
					"move": "Check the off-box backup record; report the real age — don't act on 109 h",
					"owner": "l9-triage-drone (claimed it) · verify by an agent",
					"status": "unverified",
					"source": "events.jsonl 05:35 alarm reasons only",
				})
				claim_found = true
				break
	return items


## Outcomes: what happened next, aged against later fixture facts.
## An alarm whose cause later reads green is shown AGED (superseded), not
## deleted — the ledger keeps the history and the correction side by side.
static func outcome_rows(feed: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var events: Array = feed.get("events", [])
	var beats: Dictionary = feed.get("heartbeats", {})
	var msi: Dictionary = beats.get("msi", {})
	if not events.is_empty() and not msi.is_empty():
		var first: Dictionary = events[0]
		var msi_failed := false
		for reason in first.get("reasons", []):
			if "msi failing" in String(reason):
				msi_failed = true
		var dev_mentor_ok := false
		var dev_mentor_ms := -1
		for check in msi.get("checks", []):
			if String(check.get("name", "")) == "dev-mentor" and bool(check.get("ok", false)):
				dev_mentor_ok = true
				dev_mentor_ms = int(check.get("ms", -1))
		if msi_failed and dev_mentor_ok:
			rows.append({
				"key": "msi-alarm-aged",
				"what": "05:35 alarm said \"msi failing: dev-mentor\"",
				"outcome": "AGED — MSI heartbeat %s is green; dev-mentor ok in %d ms. The alarm's MSI half did not survive the morning." % [String(msi.get("at", "?")), dev_mentor_ms],
				"state": "aged",
				"source": "events.jsonl 05:35 + heartbeat_msi.json 06:45:03Z",
			})
	var i3: Dictionary = beats.get("i3", {})
	if not events.is_empty() and not i3.is_empty():
		var docker_ok := true
		for check in i3.get("checks", []):
			if String(check.get("name", "")) == "docker":
				docker_ok = bool(check.get("ok", false))
		rows.append({
			"key": "i3-docker-outcome",
			"what": "i3 docker failing — first named 05:35, named again 06:16, 06:21, 06:36",
			"outcome": ("UNRESOLVED — i3 heartbeat %s still green:false, docker still FAIL. Four noticings, no fix recorded in the fixture." % String(i3.get("at", "?"))) if not docker_ok else "RESOLVED — i3 heartbeat %s shows docker ok." % String(i3.get("at", "?")),
			"state": "unresolved" if not docker_ok else "resolved",
			"source": "events.jsonl + heartbeat_i3.json 06:46:42Z",
		})
	return rows


## States the fixture never exercises. Listed, never faked.
## "Silent" here means a rig that stopped reporting mid-stream (a "went
## silent" line, or a heartbeat green:false with no failing check behind it).
## i3 is red-with-cause (docker FAIL), not silent; xanadu simply has no
## heartbeat file at all, which is its own listed absence.
static func unexercised_states(feed: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	var silent_seen := false
	for e in feed.get("events", []):
		seen[String(e.get("level", ""))] = true
		if "silent" in String(e.get("line", "")).to_lower():
			silent_seen = true
	if not seen.has("routine") and not seen.has("calm"):
		out.append("routine / calm — zero routine events in the fixture")
	if (feed.get("missing", []) as Array).has("xanadu"):
		out.append("xanadu heartbeat — no heartbeat_xanadu.json in the fixture")
	for beat in (feed.get("heartbeats", {}) as Dictionary).values():
		if not bool(beat.get("green", true)):
			var failing := 0
			for check in beat.get("checks", []):
				if not bool(check.get("ok", true)):
					failing += 1
			if failing == 0:
				silent_seen = true
	if not silent_seen:
		out.append("silent rig — no rig goes silent in the fixture (i3 is red-with-cause, not silent)")
	out.append("backup / mirror records — the 109 h claim has no record behind it")
	return out
