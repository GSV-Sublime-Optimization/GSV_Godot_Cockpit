class_name WarRoomOutbox
extends RefCounted

## "Assign to seat" from a pulled-up card: the war room's only write, and it
## is a LOCAL file append, never a remote write.
##
## The room appends one work-order line to an outbox JSONL file that sits next
## to the fleet-telemetry snapshot. The colony's feeder (outside Godot) relays
## outbox lines to the shared channel; Godot never talks to the channel, never
## POSTs, never runs a shell. Order line (key order is fixed):
##   {"at","from":"keath","kind":"order","id":"o-...","to":SEAT,
##    "text":CARD_TITLE,"via":"muse-war-room"}
##
## Fail-closed: with no outbox path configured (GSV_WAR_ROOM_OUTBOX_PATH,
## the same override pattern as GSV_FLEET_TELEMETRY_PATH) the action is
## disabled and says why. Remote-looking paths (URLs, UNC shares) and res://
## are refused. The outbox is capped: a feeder that is not draining shows as
## "outbox full", not as a silently growing file.
##
## Status: when a local copy of the channel (GSV_WAR_ROOM_CHANNEL_PATH,
## channel.jsonl) is configured, the room reads its tail (bounded) and shows
## the latest "order-status" line whose id matches. No copy configured ->
## status unknown, with the reason.

const OUTBOX_PATH_ENV := "GSV_WAR_ROOM_OUTBOX_PATH"
const CHANNEL_PATH_ENV := "GSV_WAR_ROOM_CHANNEL_PATH"
const FROM := "keath"
const VIA := "muse-war-room"
const MAX_TEXT := 160
const MAX_OUTBOX_BYTES := 1048576
const MAX_CHANNEL_TAIL_BYTES := 262144

var outbox_path: String = ""
var channel_path: String = ""


func _init() -> void:
	outbox_path = OS.get_environment(OUTBOX_PATH_ENV).strip_edges()
	channel_path = OS.get_environment(CHANNEL_PATH_ENV).strip_edges()


## {ok, reason}. ok=false means the action must render disabled with reason.
func availability() -> Dictionary:
	var refusal := path_refusal(outbox_path)
	if not refusal.is_empty():
		return {"ok": false, "reason": refusal}
	var dir := outbox_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		return {"ok": false, "reason": "outbox folder missing: " + dir}
	if FileAccess.file_exists(outbox_path):
		var f := FileAccess.open(outbox_path, FileAccess.READ)
		if f == null:
			return {"ok": false, "reason": "outbox unreadable"}
		var size := f.get_length()
		f.close()
		if size >= MAX_OUTBOX_BYTES:
			return {"ok": false, "reason": "outbox full (feeder not draining)"}
	return {"ok": true, "reason": ""}


## Empty string = acceptable local path; otherwise the reason it is refused.
static func path_refusal(path: String) -> String:
	if path.is_empty():
		return "no outbox configured (set %s)" % OUTBOX_PATH_ENV
	if path.begins_with("user://"):
		return ""
	if path.contains("://"):
		return "refused: not a local file path (the feeder relays; Godot never writes remotely)"
	if path.begins_with("\\\\") or path.begins_with("//"):
		return "refused: network share (the feeder relays; Godot never writes remotely)"
	if not path.is_absolute_path():
		return "refused: outbox path must be absolute"
	if path.get_extension().to_lower() != "jsonl":
		return "refused: outbox must be a .jsonl file"
	return ""


static func new_order_id() -> String:
	return "o-%d-%04x" % [int(Time.get_unix_time_from_system() * 1000.0), randi() % 0x10000]


static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


## One-line, bounded, printable text (card titles carry newlines on 3D cards).
static func clean_text(text: String) -> String:
	var out := ""
	for ch in text.replace("\r", " ").replace("\n", " ").replace("\t", " "):
		if ch.unicode_at(0) >= 32:
			out += ch
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.length() > MAX_TEXT:
		out = out.substr(0, MAX_TEXT - 3) + "..."
	return out


## The order line as a Dictionary, keys in contract order.
static func make_order(seat_id: String, card_title: String, at: String, order_id: String) -> Dictionary:
	var order := {}
	order["at"] = at
	order["from"] = FROM
	order["kind"] = "order"
	order["id"] = order_id
	order["to"] = seat_id
	order["text"] = clean_text(card_title)
	order["via"] = VIA
	return order


static func order_line(order: Dictionary) -> String:
	return JSON.stringify(order, "", false)


## Append one order. {ok, id, line, reason}. Never writes when unavailable,
## when the seat is not a registry seat, or when the title is empty.
func assign(seat_id: String, card_title: String) -> Dictionary:
	var avail := availability()
	if not bool(avail.get("ok", false)):
		return {"ok": false, "reason": String(avail.get("reason", "unavailable"))}
	if not HoloLayerRegistry.is_seat_id(seat_id):
		return {"ok": false, "reason": "unknown seat: " + seat_id}
	if clean_text(card_title).is_empty():
		return {"ok": false, "reason": "no card pulled up"}
	var order := make_order(seat_id, card_title, now_iso(), new_order_id())
	var line := order_line(order)
	var f: FileAccess
	if FileAccess.file_exists(outbox_path):
		f = FileAccess.open(outbox_path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(outbox_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "outbox not writable (error %d)" % FileAccess.get_open_error()}
	f.store_string(line + "\n")
	f.close()
	return {"ok": true, "id": String(order["id"]), "line": line, "reason": ""}


## {state, detail}. state: unknown (no channel copy / unreadable) / pending
## (not on the channel yet) / relayed (order line seen, no status yet) /
## the latest matching order-status's status text.
func order_status(order_id: String) -> Dictionary:
	if channel_path.is_empty():
		return {"state": "unknown", "detail": "no channel copy configured (set %s)" % CHANNEL_PATH_ENV}
	if not FileAccess.file_exists(channel_path):
		return {"state": "unknown", "detail": "channel copy missing"}
	var f := FileAccess.open(channel_path, FileAccess.READ)
	if f == null:
		return {"state": "unknown", "detail": "channel copy unreadable"}
	var size := f.get_length()
	if size > MAX_CHANNEL_TAIL_BYTES:
		f.seek(size - MAX_CHANNEL_TAIL_BYTES)
	var text := f.get_buffer(mini(size, MAX_CHANNEL_TAIL_BYTES)).get_string_from_utf8()
	f.close()
	return status_from_lines(text, order_id)


static func status_from_lines(text: String, order_id: String) -> Dictionary:
	var result := {"state": "pending", "detail": "not on the channel copy yet"}
	for raw in text.split("\n", false):
		var line := raw.strip_edges()
		if line.is_empty() or not line.begins_with("{"):
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var row := parsed as Dictionary
		var kind := String(row.get("kind", ""))
		if kind == "order" and String(row.get("id", "")) == order_id:
			if String(result["state"]) == "pending":
				result = {"state": "relayed", "detail": "on the channel, no order-status yet"}
		elif kind == "order-status":
			var matches := false
			for key in ["order", "order_id", "ref", "id"]:
				if String(row.get(key, "")) == order_id:
					matches = true
			if not matches:
				continue
			var status := clean_text(String(row.get("status", row.get("text", "status"))))
			if status.length() > 48:
				status = status.substr(0, 45) + "..."
			result = {
				"state": status if not status.is_empty() else "status",
				"detail": "%s · from %s" % [clean_text(String(row.get("at", "?"))), clean_text(String(row.get("from", "?")))],
			}
	return result
