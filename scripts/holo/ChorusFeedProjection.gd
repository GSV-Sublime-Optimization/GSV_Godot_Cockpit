extends RefCounted

## Schema-pinned parser for the CHORUS feed (feed.json), the live-activity
## surface other tools already read (Terminal Depths fleet mode reads the
## same file). Written by chorus/mindview_feed.py (stdlib, 15 s poll of
## xanadu over one SSH call); this room only READS the file — no HTTP, no
## POST, no shell. The feeder's own POST surface (/say /order /act) is NOT
## used here: CHORUS #22 ("merged and live", 2026-11-08T08:33:54Z) added a
## loopback-Host + same-origin + JSON Content-Type guard to those POSTs, but
## /act still runs scheduled tasks / docker restarts / git push by default
## (the --allow-actions flag is still only proposed) — so Slice 7 composes
## the READ side only (smiths / prs_waiting / doctor / spine) and never
## touches the actuator side. See the comparison doc §9 R3.
##
## Validation is fail-closed (Loom rule): unexpected types, oversized
## strings, or unknown severities are rejected, never mapped down to calm.
## Missing optional arrays are empty, not an error — a feed without smiths
## is a feed without live seats, and the room says so.

const MAX_BYTES := 1048576
const MAX_SMITHS := 64
const MAX_PRS_WAITING := 32
const MAX_DOCTOR := 32
const MAX_SPINE := 32
const MAX_NAME := 80
const MAX_DOING := 160
const MAX_TITLE := 200
const MAX_VERDICT := 280
const MAX_EVIDENCE := 8
const MAX_EVIDENCE_LEN := 200

static func parse_feed(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BYTES:
		return _invalid("feed_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	var feed := {
		"smiths": [],
		"prs_waiting": [],
		"doctor": [],
		"spine": {"up": 0, "total": 0, "services": []},
		"served_at": -1.0,
	}
	var served: Variant = body.get("served_at", null)
	if served != null:
		if typeof(served) != TYPE_INT and typeof(served) != TYPE_FLOAT:
			return _invalid("invalid_served_at")
		feed["served_at"] = float(served)
	var smiths := _parse_smiths(body.get("smiths", []))
	if not smiths["ok"]:
		return _invalid(String(smiths["reason"]))
	feed["smiths"] = smiths["items"]
	var prs := _parse_prs_waiting(body.get("prs_waiting", []))
	if not prs["ok"]:
		return _invalid(String(prs["reason"]))
	feed["prs_waiting"] = prs["items"]
	var doctor := _parse_doctor(body.get("doctor", []))
	if not doctor["ok"]:
		return _invalid(String(doctor["reason"]))
	feed["doctor"] = doctor["items"]
	var spine := _parse_spine(body.get("spine", {}))
	if not spine["ok"]:
		return _invalid(String(spine["reason"]))
	feed["spine"] = spine["spine"]
	return {"ok": true, "feed": feed}


static func _parse_smiths(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY:
		return {"ok": false, "reason": "invalid_smiths"}
	var items: Array = []
	for entry in raw:
		if items.size() >= MAX_SMITHS:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_smith_entry"}
		var name := _bounded_string(entry.get("name", null), MAX_NAME)
		var doing := _bounded_string(entry.get("doing", null), MAX_DOING)
		if name.is_empty() or doing.is_empty():
			return {"ok": false, "reason": "invalid_smith_entry"}
		var t: Variant = entry.get("t", null)
		if typeof(t) != TYPE_INT and typeof(t) != TYPE_FLOAT:
			return {"ok": false, "reason": "invalid_smith_entry"}
		items.append({
			"name": name,
			"doing": doing,
			"t": float(t),
			"at": _bounded_string(entry.get("at", ""), MAX_NAME),
			"station": _bounded_string(entry.get("station", ""), MAX_NAME),
			"rig": _bounded_string(entry.get("rig", ""), MAX_NAME),
		})
	return {"ok": true, "items": items}


static func _parse_prs_waiting(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY:
		return {"ok": false, "reason": "invalid_prs_waiting"}
	var items: Array = []
	for entry in raw:
		if items.size() >= MAX_PRS_WAITING:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_prs_waiting_entry"}
		var repo := _bounded_string(entry.get("repo", null), MAX_NAME)
		var title := _bounded_string(entry.get("title", null), MAX_TITLE)
		var url := _bounded_string(entry.get("url", null), 300)
		if repo.is_empty() or title.is_empty() or url.is_empty():
			return {"ok": false, "reason": "invalid_prs_waiting_entry"}
		var number: Variant = entry.get("number", null)
		if typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT:
			return {"ok": false, "reason": "invalid_prs_waiting_entry"}
		items.append({
			"repo": repo,
			"number": int(number),
			"title": title,
			"url": url,
			"created": _bounded_string(entry.get("created", ""), MAX_NAME),
		})
	return {"ok": true, "items": items}


static func _parse_doctor(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY:
		return {"ok": false, "reason": "invalid_doctor"}
	var items: Array = []
	for entry in raw:
		if items.size() >= MAX_DOCTOR:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_doctor_entry"}
		var key := _bounded_string(entry.get("key", null), MAX_NAME)
		var verdict := _bounded_string(entry.get("verdict", null), MAX_VERDICT)
		if key.is_empty() or verdict.is_empty():
			return {"ok": false, "reason": "invalid_doctor_entry"}
		var evidence: Array = []
		var raw_evidence: Variant = entry.get("evidence", [])
		if typeof(raw_evidence) != TYPE_ARRAY:
			return {"ok": false, "reason": "invalid_doctor_entry"}
		for line in raw_evidence:
			if evidence.size() >= MAX_EVIDENCE:
				break
			evidence.append(_bounded_string(line, MAX_EVIDENCE_LEN))
		items.append({
			"key": key,
			"verdict": verdict,
			"evidence": evidence,
			"at": _bounded_string(entry.get("at", ""), MAX_NAME),
		})
	return {"ok": true, "items": items}


static func _parse_spine(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_spine"}
	var services: Array = []
	var raw_services: Variant = raw.get("services", [])
	if typeof(raw_services) != TYPE_ARRAY:
		return {"ok": false, "reason": "invalid_spine"}
	for entry in raw_services:
		if services.size() >= MAX_SPINE:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_spine_entry"}
		var name := _bounded_string(entry.get("name", null), MAX_NAME)
		if name.is_empty():
			return {"ok": false, "reason": "invalid_spine_entry"}
		var up: Variant = entry.get("up", null)
		if typeof(up) != TYPE_BOOL:
			return {"ok": false, "reason": "invalid_spine_entry"}
		var ms: Variant = entry.get("ms", 0)
		if typeof(ms) != TYPE_INT and typeof(ms) != TYPE_FLOAT:
			return {"ok": false, "reason": "invalid_spine_entry"}
		services.append({
			"name": name,
			"tier": _bounded_string(entry.get("tier", ""), MAX_NAME),
			"up": bool(up),
			"ms": int(ms),
		})
	var up_count := 0
	for svc in services:
		if bool(svc["up"]):
			up_count += 1
	return {"ok": true, "spine": {"up": up_count, "total": services.size(), "services": services}}


## A missing/empty value reads as "" (caller decides whether that is an
## error); a present-but-wrong-typed or over-long value is also "" — the
## callers above treat "" as invalid only for required fields.
static func _bounded_string(value: Variant, max_len: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	if value.length() > max_len:
		return ""
	return value


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
