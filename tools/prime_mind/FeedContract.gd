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
	return {
		"ok": true, "schema": SCHEMA,
		"source_at": data["at"], "source_ok": data["source_ok"],
		"provenance": provenance.substr(0, 40),
		"bodies": bodies, "events": events,
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

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
