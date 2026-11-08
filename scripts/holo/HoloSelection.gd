class_name HoloSelection
extends RefCounted

## One selection model for every selectable thing in the room (design §3):
## rig, service, seat, pr, mission, Atlas entry, pu. A node is a plain
## Dictionary — kind / id / title / state / source / age / facts / links /
## focus / layer_id / anchor — built from the room's six live sources by
## build_nodes(). No special cases: a rig and a PR select the same way.
##
## Default focus is the local rig (MSI) — never Xanadu. Xanadu is one node
## among four (key 4); selecting it shows the library view, not an
## operations view. Compose-from-selection is PREFILL-ONLY: compose_prefill()
## returns copyable text; the room never submits anything.
##
## Pure logic — no scene tree — so the selection tests exercise it without
## a Godot run of the room. Colours live here only as the fixed language
## names; the room owns the actual materials.

const KINDS: PackedStringArray = ["rig", "service", "seat", "pr", "mission", "atlas", "pu"]
const LOCAL_RIG_ID := "msi"
const DIMMED_FACTOR := 0.4
const MAX_RAIL_NODES := 48
const MAX_PR_NODES := 6
const MAX_PU_NODES := 5
const MAX_ATLAS_NODES := 5

## Focus positions for the nodes that have a 3D anchor. Rig/service foci are
## their registry layer positions; seats ring the table (same formula as
## HoloRoom._build_seats); the Atlas shelf sits at its base position.
## Nodes without an anchor (PRs on the web, missions, PUs) focus the table
## centre and say so — the detail panel carries their facts.
const RIG_FOCUS := {
	"msi": Vector3(-3.4, 1.4, 2.8),
	"i3": Vector3(-1.1, 1.4, 2.8),
	"l9": Vector3(1.1, 1.4, 2.8),
	"xanadu": Vector3(3.4, 1.4, 2.8),
}
const SERVICE_FOCUS := {
	"studio": Vector3(-3.2, 2.6, -1.2),
	"gateway": Vector3(0.0, 2.8, -1.6),
	"constellation": Vector3(3.2, 2.6, -1.2),
	"fleet-bodies": Vector3(-1.6, 3.6, -2.2),
	"dev-mentor": Vector3(1.6, 3.6, -2.2),
}
const TABLE_FOCUS := Vector3(0.0, 2.6, -2.75)
const ATLAS_FOCUS := Vector3(0.0, 3.6, 2.4)
const RIG_LAYER := {
	"msi": "rig-msi", "i3": "rig-i3", "l9": "rig-l9", "xanadu": "rig-xanadu",
}
const SERVICE_LAYER := {
	"studio": "studio-health",
	"gateway": "gateway-health",
	"constellation": "constellation",
	"fleet-bodies": "fleet-bodies",
	"dev-mentor": "dev-mentor-game",
}

## Smiths-name (lowercase, CHORUS feed.json) -> seat id. Several Claudes
## share the one Claude seat; the freshest smiths entry wins there.
const SMITHS_SEAT := {
	"msi claude": "claude",
	"i3 claude": "claude",
	"a claude": "claude",
	"msi-claude": "claude",
	"openclaw": "openclaw",
	"chatdev": "chatdev",
	"codex": "codex",
	"jev": "jev",
	"openjev": "jev",
	"serena": "serena",
	"ollama": "ollama",
	"dev-mentor": "devmentor",
	"skyclaw": "skyclaw",
	"hermes": "hermes",
	"gordon": "gordon",
	"aider": "aider",
	"goose": "goose",
	"copilot": "copilot",
}

var _selected: Dictionary = {}


## Build the selectable node list from the room's six sources. Any source may
## be empty (no feed yet) — its nodes are then absent, never fabricated.
static func build_nodes(fleet: Dictionary, model: Dictionary, chorus: Dictionary, events: Dictionary, atlas: Dictionary, pu: Dictionary) -> Array:
	var nodes: Array = []
	nodes.append_array(_rig_nodes(fleet))
	nodes.append_array(_service_nodes(model, chorus))
	nodes.append_array(_seat_nodes(chorus))
	nodes.append_array(_pr_nodes(events, chorus))
	nodes.append_array(_mission_nodes(model))
	nodes.append_array(_atlas_nodes(atlas))
	nodes.append_array(_pu_nodes(pu))
	if nodes.size() > MAX_RAIL_NODES:
		nodes = nodes.slice(0, MAX_RAIL_NODES)
	return nodes


static func _rig_nodes(fleet: Dictionary) -> Array:
	var out: Array = []
	var rigs: Dictionary = fleet.get("rigs", {})
	for rig_id in ["msi", "i3", "l9", "xanadu"]:
		var rig: Dictionary = rigs.get(rig_id, {})
		var state := String(rig.get("state", "unknown"))
		var facts := {
			"rig": rig_id,
			"ram_free_mb": str(rig.get("ram_free_mb", "-")),
			"cpu_load_pct": str(rig.get("cpu_load_pct", "-")),
			"seats": String(rig.get("seats", "")),
			"note": String(rig.get("note", "")),
		}
		var role := "library / record-keeper" if rig_id == "xanadu" else "operations rig"
		if rig_id == "msi":
			role = "local rig — the cockpit runs here"
		out.append({
			"kind": "rig", "id": rig_id,
			"title": "RIG · " + rig_id.to_upper(),
			"state": state,
			"source": "fleet-telemetry snapshot (5 min)",
			"age": str(fleet.get("age_ms", -1)) + " ms snapshot age",
			"facts": facts,
			"links": [{"label": "fleet snapshot", "target": "C:/GSV/state/fleet-telemetry.json"}],
			"focus": RIG_FOCUS.get(rig_id, TABLE_FOCUS),
			"layer_id": String(RIG_LAYER.get(rig_id, "")),
			"anchor": "3d",
			"role": role,
		})
	return out


static func _service_nodes(model: Dictionary, chorus: Dictionary) -> Array:
	var out: Array = []
	var sensor: Dictionary = model.get("sensor", {})
	var gateway: Dictionary = model.get("gateway", {})
	var constellation: Dictionary = model.get("constellation", {})
	var bodies: Array = model.get("fleet_bodies", [])
	var reported := 0
	for entry in bodies:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("state", "")) == "reported_fresh":
			reported += 1
	var defs: Array = [
		{"id": "studio", "title": "STUDIO", "state": String(sensor.get("state", "unknown")),
			"source": "127.0.0.1:7340/api/health (Mind Slice 0)"},
		{"id": "gateway", "title": "GATEWAY", "state": String(gateway.get("state", "unknown")),
			"source": "127.0.0.1:8001/health (Mind Slice 2)"},
		{"id": "constellation", "title": "CONSTELLATION", "state": String(constellation.get("state", "unknown")),
			"source": "127.0.0.1:7340/api/projects (Mind Slice 1)"},
		{"id": "fleet-bodies", "title": "FLEET BODIES",
			"state": "live" if reported > 0 else "unknown",
			"source": "KiloCore-Studio entity-bodies (Mind)"},
		{"id": "dev-mentor", "title": "DEV-MENTOR · GAME", "state": "unknown",
			"source": "127.0.0.1:7337/api/health"},
	]
	for def in defs:
		out.append({
			"kind": "service", "id": String(def["id"]),
			"title": String(def["title"]),
			"state": String(def["state"]),
			"source": String(def["source"]),
			"age": "15 s observation tick",
			"facts": {},
			"links": [],
			"focus": SERVICE_FOCUS.get(String(def["id"]), TABLE_FOCUS),
			"layer_id": String(SERVICE_LAYER.get(String(def["id"]), "")),
			"anchor": "3d",
			"role": "service",
		})
	# Spine services from the CHORUS feed (live process truth): the web nodes
	# CHATDEV / OLLAMA / SKYCLAW used to be hardcoded literals — now they are
	# these nodes, and a missing feed means no node, not a fake "live".
	var spine: Array = (chorus.get("spine", {}) as Dictionary).get("services", [])
	var seen: PackedStringArray = ["studio", "gateway", "constellation", "fleet-bodies", "dev-mentor"]
	for svc in spine:
		if typeof(svc) != TYPE_DICTIONARY:
			continue
		var name := String(svc.get("name", ""))
		if name.is_empty() or seen.has(name):
			continue
		seen.append(name)
		out.append({
			"kind": "service", "id": name,
			"title": name.to_upper(),
			"state": "live" if bool(svc.get("up", false)) else "unavailable",
			"source": "CHORUS feed.json spine (Dev-Mentor /api/spine/services)",
			"age": "spine probe " + str(svc.get("ms", -1)) + " ms",
			"facts": {"tier": String(svc.get("tier", "")), "probe_ms": str(svc.get("ms", -1))},
			"links": [],
			"focus": TABLE_FOCUS,
			"layer_id": "",
			"anchor": "panel",
			"role": "spine service",
		})
	return out


static func _seat_nodes(chorus: Dictionary) -> Array:
	var out: Array = []
	var seats: Array = HoloLayerRegistry.seat_defs()
	# Freshest smiths entry per seat (CHORUS feed.json, last 3 h).
	var doing: Dictionary = {}
	var smiths: Array = chorus.get("smiths", [])
	for entry in smiths:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var seat_id := String(SMITHS_SEAT.get(String(entry.get("name", "")).to_lower(), ""))
		if seat_id.is_empty():
			continue
		var t := float(entry.get("t", 0.0))
		if not doing.has(seat_id) or t > float((doing[seat_id] as Dictionary).get("t", 0.0)):
			doing[seat_id] = entry
	for i in seats.size():
		var seat: Dictionary = seats[i]
		var seat_id := String(seat.get("id", ""))
		var side := 1.0 if i % 2 == 0 else -1.0
		var col := i / 2
		var pos := Vector3(-3.5 + float(col) * 1.0, 1.15, side * 2.6 + side * 0.45)
		var facts := {
			"lane_b_state": String(seat.get("state", "unknown")),
			"lane_b_note": String(seat.get("note", "")),
			"lane_b_seen": "2026-11-07",
		}
		var state := String(seat.get("state", "unknown"))
		var age := "seen 2026-11-07 (Lane B verdicts — not re-probed)"
		if doing.has(seat_id):
			var live: Dictionary = doing[seat_id]
			facts["doing"] = String(live.get("doing", ""))
			facts["doing_at"] = String(live.get("at", ""))
			facts["station"] = String(live.get("station", ""))
			age = "live activity " + age_text(float(live.get("t", 0.0)))
			# A seat with fresh activity is present; its Lane B state is the
			# fallback, never the claim.
			if state == "not_detected" or state == "awaiting":
				state = "live"
		out.append({
			"kind": "seat", "id": seat_id,
			"title": String(seat.get("name", "?")),
			"state": state,
			"source": "CHORUS feed.json smiths + Lane B 2026-11-07",
			"age": age,
			"facts": facts,
			"links": [],
			"focus": pos,
			"layer_id": "",
			"anchor": "3d",
			"role": "agent seat",
		})
	return out


static func _pr_nodes(events: Dictionary, chorus: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var evs: Array = events.get("events", [])
	for ev in evs:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var key := String(ev.get("repo", "")) + "#" + str(ev.get("number", 0))
		if seen.has(key):
			continue
		seen[key] = true
		out.append({
			"kind": "pr", "id": key,
			"title": String(ev.get("repo", "")) + "#" + str(ev.get("number", 0)),
			"state": _pr_state(String(ev.get("kind", ""))),
			"source": "cockpit_events.json (scheduled gh poll, 5 min)",
			"age": String(ev.get("at", "")),
			"facts": {
				"title": String(ev.get("title", "")),
				"last_event": String(ev.get("kind", "")),
				"actor": String(ev.get("actor", "")),
			},
			"links": [{"label": "open PR", "target": String(ev.get("url", ""))}],
			"focus": TABLE_FOCUS,
			"layer_id": "",
			"anchor": "panel",
			"role": "pull request",
		})
		if out.size() >= MAX_PR_NODES:
			break
	if out.size() < MAX_PR_NODES:
		for waiting in chorus.get("prs_waiting", []):
			if typeof(waiting) != TYPE_DICTIONARY:
				continue
			var key := String(waiting.get("repo", "")) + "#" + str(waiting.get("number", 0))
			if seen.has(key):
				continue
			seen[key] = true
			out.append({
				"kind": "pr", "id": key,
				"title": key,
				"state": "live",
				"source": "CHORUS feed.json prs_waiting (open, not draft, no review)",
				"age": "opened " + String(waiting.get("created", "")),
				"facts": {"title": String(waiting.get("title", "")), "last_event": "pr_opened"},
				"links": [{"label": "open PR", "target": String(waiting.get("url", ""))}],
				"focus": TABLE_FOCUS,
				"layer_id": "",
				"anchor": "panel",
				"role": "pull request",
			})
			if out.size() >= MAX_PR_NODES:
				break
	return out


static func _pr_state(kind: String) -> String:
	match kind:
		"pr_merged":
			return "live"
		"review_submitted":
			return "live"
		"check_failed":
			return "degraded"
		_:
			return "live"


static func _mission_nodes(model: Dictionary) -> Array:
	var sensor: Dictionary = model.get("sensor", {})
	var counts: Dictionary = sensor.get("mission_counts", {})
	var awaiting := int(counts.get("awaiting", 0))
	var running := int(counts.get("running", 0))
	var queued := int(counts.get("queued", 0))
	return [{
		"kind": "mission", "id": "missions-aggregate",
		"title": "MISSIONS",
		"state": String(sensor.get("state", "unknown")),
		"source": "127.0.0.1:7340/api/health (Mind Slice 0)",
		"age": "15 s observation tick",
		"facts": {
			"awaiting": str(awaiting),
			"running": str(running),
			"queued": str(queued),
			"thermal_gate": String(sensor.get("thermal_gate", "")),
		},
		"links": [],
		"focus": SERVICE_FOCUS.get("studio", TABLE_FOCUS),
		"layer_id": "studio-health",
		"anchor": "3d",
		"role": "mission aggregate — individual missions arrive with the Studio mission list",
	}]


static func _atlas_nodes(atlas: Dictionary) -> Array:
	var out: Array = []
	var entries: Array = atlas.get("entries", [])
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var grade := String(entry.get("grade", ""))
		if grade != "Q" and grade != "U":
			continue
		out.append({
			"kind": "atlas", "id": String(entry.get("id", "")),
			"title": String(entry.get("name", String(entry.get("id", "")))),
			"state": String(entry.get("state", "unknown")),
			"age": "static Atlas snapshot + fleet overlay",
			"source": "Capability Atlas (75 entries) + fleet-telemetry overlay",
			"facts": {
				"grade": grade,
				"machine": String(entry.get("machine", "")),
				"cost_class": String(entry.get("cost_class", "")),
				"overlay": String(entry.get("overlay", "")),
			},
			"links": [],
			"focus": ATLAS_FOCUS,
			"layer_id": "",
			"anchor": "panel",
			"role": "Atlas entry (proven Q/U only — the rail shows what can be routed on)",
		})
		if out.size() >= MAX_ATLAS_NODES:
			break
	return out


static func _pu_nodes(pu: Dictionary) -> Array:
	var out: Array = []
	var items: Array = pu.get("items", [])
	# Failed first (they await triage), then executing, then the rest.
	var ordered: Array = []
	for want in ["failed", "executing", "approved", "queued", "voting", "completed"]:
		for item in items:
			if typeof(item) == TYPE_DICTIONARY and String(item.get("status", "")) == want:
				ordered.append(item)
	for item in ordered:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var status := String(item.get("status", ""))
		out.append({
			"kind": "pu", "id": String(item.get("id", "")),
			"title": String(item.get("id", "")),
			"state": "degraded" if status == "failed" else "live",
			"source": "NuSyQ-Hub unified PU queue file (STALE — see rail header)",
			"age": String(pu.get("file_age", "unknown")),
			"facts": {
				"title": String(item.get("title", "")),
				"status": status,
				"repo": String(item.get("source_repo", "")),
				"priority": String(item.get("priority", "")),
			},
			"links": [],
			"focus": TABLE_FOCUS,
			"layer_id": "",
			"anchor": "panel",
			"role": "proof-gated work unit",
		})
		if out.size() >= MAX_PU_NODES:
			break
	return out


## "Ns ago" / "Nm ago" / "Nh ago" for a unix epoch. Future timestamps read
## as "in the future" — never rounded to "just now" (CHORUS #22 honesty fix).
static func age_text(epoch: float) -> String:
	var now := Time.get_unix_time_from_system()
	var diff := int(now - epoch)
	if diff < 0:
		return "timestamp in the future"
	if diff < 60:
		return "%ds ago" % diff
	if diff < 3600:
		return "%dm ago" % (diff / 60)
	if diff < 86400:
		return "%dh ago" % (diff / 3600)
	return "%dd ago" % (diff / 86400)


## The default node: the local rig (MSI). Never Xanadu.
static func default_node(nodes: Array) -> Dictionary:
	for node in nodes:
		if typeof(node) == TYPE_DICTIONARY and String(node.get("kind", "")) == "rig" and String(node.get("id", "")) == LOCAL_RIG_ID:
			return node
	for node in nodes:
		if typeof(node) == TYPE_DICTIONARY and String(node.get("kind", "")) == "rig":
			return node
	if not nodes.is_empty():
		return nodes[0]
	return {}


static func find_node(nodes: Array, kind: String, node_id: String) -> Dictionary:
	for node in nodes:
		if typeof(node) == TYPE_DICTIONARY and String(node.get("kind", "")) == kind and String(node.get("id", "")) == node_id:
			return node
	return {}


func select(node: Dictionary) -> void:
	_selected = node.duplicate(true)


func clear() -> void:
	_selected = {}


func has_selection() -> bool:
	return not _selected.is_empty()


func selected() -> Dictionary:
	return _selected.duplicate(true)


func selected_kind() -> String:
	return String(_selected.get("kind", ""))


func selected_id() -> String:
	return String(_selected.get("id", ""))


## Everything except the selected node dims to DIMMED_FACTOR (40%). With no
## selection nothing dims.
func is_dimmed(node: Dictionary) -> bool:
	if _selected.is_empty():
		return false
	return String(node.get("kind", "")) != selected_kind() or String(node.get("id", "")) != selected_id()


## Detail-panel lines for the selected node: exact-head facts, source, age,
## and deep links. Rendered by HoloTab with escaping (BBCode surface).
static func detail_lines(node: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(String(node.get("title", "?")))
	lines.append("kind: " + String(node.get("kind", "?")) + " · state: " + String(node.get("state", "unknown")))
	lines.append("source: " + String(node.get("source", "?")))
	lines.append("age: " + String(node.get("age", "?")))
	var role := String(node.get("role", ""))
	if not role.is_empty():
		lines.append(role)
	var facts: Dictionary = node.get("facts", {})
	for key in facts.keys():
		var value := String(facts[key])
		if not value.is_empty():
			lines.append(str(key) + ": " + value)
	var links: Array = node.get("links", [])
	for link in links:
		if typeof(link) == TYPE_DICTIONARY:
			lines.append("link: " + String(link.get("label", "")) + " — " + String(link.get("target", "")))
	if String(node.get("anchor", "")) == "panel":
		lines.append("no 3D anchor yet — the facts above are the node")
	return lines


## Compose-from-selection: PREFILL-ONLY text. The room never submits, posts,
## or executes — a human still takes this text to the Studio factory desk.
static func compose_prefill(node: Dictionary) -> String:
	if node.is_empty():
		return ""
	var facts: Dictionary = node.get("facts", {})
	var about := String(facts.get("title", String(node.get("title", ""))))
	return "PREFILL ONLY — no submit from the room.\nCompose a Studio mission about %s (%s %s).\nTake this text to the Studio factory desk; submission needs a fresh scan, a 45 s source lease, and a human SUBMIT." % [
		about, String(node.get("kind", "")), String(node.get("id", "")),
	]
