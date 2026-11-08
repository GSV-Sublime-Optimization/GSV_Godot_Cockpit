extends RefCounted

## Inert, source-aware admission of Mind View observations.
## A mind's recorded summary is not access to private model chain-of-thought.
const SCHEMA := "colony.mindview-feed/v0"
const MAX_BYTES := 196608
const MAX_EVENTS := 80
const MAX_REASONS := 8
const RIG_IDS := ["msi", "i3", "l9", "xanadu"]
const STATUSES := ["green", "red", "silent", "unknown"]
const LEVELS := ["routine", "notable", "alarm", "calm"]
## Colony work on the tape: channel orders, receipts, decisions and rig
## changes between consecutive heartbeats. Kept apart from thought events.
const MAX_WORK := 60
const WORK_KINDS := ["order", "order-status", "decision", "rig-change"]
const ORDER_STATUSES := ["taken", "working", "done", "declined"]
const HEARTBEAT_RIGS := ["msi", "i3", "l9"]
const WORK_FIELDS := ["kind", "at", "id", "from", "to", "status", "text", "note", "link", "rig", "prev_status"]
const WORK_LIMITS := {"at": 40, "id": 100, "from": 64, "to": 64, "status": 32,
	"text": 280, "note": 280, "link": 300, "prev_status": 16}

static func parse_text(raw_text: String, provenance: String = "LOCAL_UNVERIFIED") -> Dictionary:
	if raw_text.to_utf8_buffer().size() > MAX_BYTES:
		return _invalid("oversized_feed")
	var reader := JSON.new()
	if reader.parse(raw_text) != OK or typeof(reader.data) != TYPE_DICTIONARY:
		return _invalid("invalid_json")
	var data: Dictionary = reader.data
	if data.get("schema", "") != SCHEMA:
		return _invalid("unsupported_schema")
	if typeof(data.get("source_ok")) != TYPE_BOOL:
		return _invalid("invalid_source_status")
	if typeof(data.get("at")) != TYPE_STRING or String(data["at"]).length() > 40:
		return _invalid("invalid_source_timestamp")
	if typeof(data.get("events")) != TYPE_ARRAY:
		return _invalid("invalid_event_collection")
	if data["events"].size() > MAX_EVENTS:
		return _invalid("too_many_events")
	var raw_bodies: Variant = data.get("bodies")
	if typeof(raw_bodies) != TYPE_DICTIONARY:
		return _invalid("invalid_body_map")
	var bodies: Dictionary = {}
	for id in RIG_IDS:
		if not raw_bodies.has(id) or typeof(raw_bodies[id]) != TYPE_DICTIONARY:
			return _invalid("body_missing_" + id)
		var b: Dictionary = raw_bodies[id]
		var status: Variant = b.get("status", "")
		if typeof(status) != TYPE_STRING or not STATUSES.has(status):
			return _invalid("invalid_body_status_" + id)
		var age: Variant = b.get("age_s")
		if age != null:
			if typeof(age) != TYPE_FLOAT and typeof(age) != TYPE_INT:
				return _invalid("invalid_body_age_" + id)
			var n := float(age)
			if n < 0.0 or n > 1.0e9 or floorf(n) != n:
				return _invalid("invalid_body_age_" + id)
		var failures: Variant = b.get("failing", [])
		if typeof(failures) != TYPE_ARRAY or failures.size() > 20:
			return _invalid("invalid_checks_" + id)
		var failed: PackedStringArray = []
		for name in failures:
			if typeof(name) != TYPE_STRING or name.length() > 80:
				return _invalid("invalid_check_name_" + id)
			failed.append(name)
		var detail: Variant = b.get("detail", "")
		if typeof(detail) != TYPE_STRING:
			return _invalid("invalid_body_detail_" + id)
		bodies[id] = {
			"id": id,
			"status": status,
			"age_s": int(age) if age != null else -1,
			"failing": failed,
			"detail": detail.substr(0, 230)
		}
	var events: Array[Dictionary] = []
	for entry in data["events"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return _invalid("event_not_object")
		var e: Dictionary = entry
		for field in ["mind", "line", "at", "level"]:
			if typeof(e.get(field)) != TYPE_STRING:
				return _invalid("missing_event_" + field)
		if not LEVELS.has(e["level"]):
			return _invalid("unknown_event_level")
		var focus: Variant = e.get("focus")
		if focus != null and (typeof(focus) != TYPE_STRING or not RIG_IDS.has(focus)):
			return _invalid("invalid_focus")
		var model: Variant = e.get("model")
		if model != null and typeof(model) != TYPE_STRING:
			return _invalid("invalid_model")
		var reasons: Variant = e.get("reasons", [])
		if typeof(reasons) != TYPE_ARRAY or reasons.size() > MAX_REASONS:
			return _invalid("invalid_reasons")
		var observed_reasons: PackedStringArray = []
		for reason in reasons:
			if typeof(reason) != TYPE_STRING or reason.length() > 320:
				return _invalid("invalid_reason")
			observed_reasons.append(reason)
		var mind: String = String(e["mind"]).substr(0, 64)
		var line: String = String(e["line"]).substr(0, 600)
		var stamp: String = String(e["at"]).substr(0, 40)
		var identity := "monitor" if model == null or mind == "observer" else "model_summary"
		if e.get("simulated", false) == true:
			identity = "simulated"
		events.append({
			"mind": mind, "model": model,
			"at": stamp, "level": e["level"],
			"line": line, "focus": focus,
			"reasons": observed_reasons,
			"identity": identity
		})
	var raw_work: Variant = data.get("work", [])
	if typeof(raw_work) != TYPE_ARRAY:
		return _invalid("invalid_work_collection")
	if raw_work.size() > MAX_WORK:
		return _invalid("too_much_work")
	var work: Array[Dictionary] = []
	for entry in raw_work:
		var admitted := _admit_work(entry)
		if not admitted.get("ok", false):
			return admitted
		work.append(admitted["work"])
	return {
		"ok": true, "schema": SCHEMA,
		"source_at": data["at"], "source_ok": data["source_ok"],
		"provenance": provenance.substr(0, 40),
		"bodies": bodies, "events": events, "work": work,
		"screen": String(data.get("screen", "")).substr(0, 100),
		"attention": String(data.get("attention", "")).substr(0, 16)
	}

static func feed_age_s(stamp: String) -> int:
	if stamp.length() < 19 or stamp.substr(10, 1) != "T":
		return -1
	# Producer sends timestamps in UTC. Do not guess another timezone.
	var value: float = Time.get_unix_time_from_datetime_string(stamp.substr(0, 19))
	if value <= 0.0:
		return -1
	return int(Time.get_unix_time_from_system() - value)

static func source_state(data: Dictionary, is_fixture: bool) -> String:
	if not data.get("ok", false):
		return "INVALID"
	if is_fixture:
		return "PINNED FIXTURE"
	if not data.get("source_ok", false):
		return "SOURCE UNAVAILABLE"
	var age := feed_age_s(String(data.get("source_at", "")))
	if age < -120 or age > 120:
		return "STALE / CLOCK UNKNOWN"
	return "OBSERVED"

## One work line, admitted whole or not at all. Exactly the collector's
## fields; a done receipt is "reported" unless it carries an https link,
## and a link is shown, never fetched, so "linked" is not "verified".
static func _admit_work(entry: Variant) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return _invalid("work_not_object")
	var w: Dictionary = entry
	if w.size() != WORK_FIELDS.size():
		return _invalid("work_fields")
	for field in WORK_FIELDS:
		if not w.has(field):
			return _invalid("work_fields")
	for field in WORK_LIMITS:
		if typeof(w[field]) != TYPE_STRING or String(w[field]).length() > int(WORK_LIMITS[field]):
			return _invalid("work_" + field)
		if _has_control(String(w[field])):
			return _invalid("work_" + field)
	var kind := String(w["kind"])
	if not WORK_KINDS.has(kind):
		return _invalid("work_kind")
	var stamp := String(w["at"])
	if stamp.length() != 20 or stamp.substr(10, 1) != "T" or not stamp.ends_with("Z"):
		return _invalid("work_at")
	if String(w["from"]).is_empty() or String(w["id"]).is_empty():
		return _invalid("work_identity")
	var link := String(w["link"])
	if not link.is_empty() and (not link.begins_with("https://") or link.contains(" ") or link.length() < 10):
		return _invalid("work_link")
	var status := String(w["status"])
	match kind:
		"order":
			if status != "posted":
				return _invalid("work_status")
		"order-status":
			if not ORDER_STATUSES.has(status):
				return _invalid("work_status")
		"decision":
			var verdict := RegEx.create_from_string("^[a-z][a-z0-9_-]{0,31}$")
			if verdict.search(status) == null:
				return _invalid("work_status")
		"rig-change":
			if not HEARTBEAT_RIGS.has(w["rig"]) or not ["green", "red"].has(status) or not ["green", "red"].has(w["prev_status"]):
				return _invalid("work_rig")
	if kind != "rig-change" and (w["rig"] != null or not String(w["prev_status"]).is_empty()):
		return _invalid("work_rig")
	var receipt := ""
	if kind == "order-status" and status == "done":
		receipt = "linked" if not link.is_empty() else "reported"
	var focus: Variant = w["rig"] if kind == "rig-change" else null
	return {"ok": true, "work": {
		"identity": "work", "kind": kind, "at": stamp, "id": String(w["id"]),
		"from": String(w["from"]), "to": String(w["to"]), "status": status,
		"text": String(w["text"]), "note": String(w["note"]), "link": link,
		"rig": w["rig"], "prev_status": String(w["prev_status"]),
		"receipt": receipt, "focus": focus,
		# Display fields shared with thought events; level is not a severity claim.
		"mind": String(w["from"]), "model": null, "level": "routine",
		"line": work_summary(kind, w), "reasons": PackedStringArray()
	}}

static func work_summary(kind: String, w: Dictionary) -> String:
	match kind:
		"order":
			return "%s -> %s: %s" % [w["from"], w["to"] if not String(w["to"]).is_empty() else "anyone", w["text"]]
		"order-status":
			return "%s %s %s%s" % [w["from"], String(w["status"]).to_upper(), w["id"],
				(": " + String(w["note"])) if not String(w["note"]).is_empty() else ""]
		"decision":
			return "%s decided %s on %s" % [w["from"], String(w["status"]).to_upper(), w["id"]]
		_:
			return "%s%s" % [w["text"], ("; " + String(w["note"])) if not String(w["note"]).is_empty() else ""]

static func _has_control(value: String) -> bool:
	for i in value.length():
		var code := value.unicode_at(i)
		if code < 0x20 or code == 0x7f:
			return true
	return false

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
