extends RefCounted

## Static discovery hints are not running instances or attachable terminals.
## Actual sessions come only from a validated owning service observation.

const RIGS := [
	{"id": "kilo-core-msi", "name": "MSI", "role": "Primary / orchestration"},
	{"id": "desktop-i3anuvp", "name": "I3", "role": "Interactive / game lab"},
	{"id": "desktop-l9v3emb", "name": "L9", "role": "CI / evaluation"},
	{"id": "imac-xanadu", "name": "Xanadu", "role": "Continuity / radio-first"}
]
const AGENTS := [
	{"id": "openclaw", "name": "OpenClaw", "role": "Agent gateway / sessions"},
	{"id": "soulclaw", "name": "SoulClaw", "role": "Agent concept / harness"},
	{"id": "metaclaw", "name": "MetaClaw", "role": "Agent concept / harness"},
	{"id": "skyclaw", "name": "SkyClaw", "role": "Agent harness"},
	{"id": "hermes", "name": "Hermes Agent", "role": "Persistent skills / reasoning"},
	{"id": "chatdev", "name": "ChatDev", "role": "Multi-agent software workflow"},
	{"id": "serena", "name": "Serena", "role": "Semantic code intelligence"},
	{"id": "claude", "name": "Claude", "role": "Coding / review harness"},
	{"id": "codex", "name": "Codex", "role": "Coding / review harness"},
	{"id": "goose", "name": "Goose", "role": "Tool/agent runner"},
	{"id": "culture-ship", "name": "Culture Ship", "role": "Introspection / event council"}
]
const PROJECTS := [
	{"id": "Kilo_Core", "name": "Kilo_Core", "role": "Governance, policy and execution admission"},
	{"id": "NuSyQ-Hub", "name": "NuSyQ-Hub", "role": "Colony coordination"},
	{"id": "KiloCore-Studio", "name": "KiloCore Studio", "role": "Mission loop and approvals"},
	{"id": "Dev-Mentor", "name": "Dev-Mentor", "role": "Learning and tool guidance"},
	{"id": "TerminalDepths", "name": "Terminal Depths", "role": "Terminal-native game / agent environment"},
	{"id": "FleetBridge", "name": "FleetBridge", "role": "Host topology and evidence"},
	{"id": "SimulatedVerse", "name": "SimulatedVerse", "role": "Simulated systems and experiments"},
	{"id": "Kilos_Factory", "name": "Kilos Factory", "role": "Scene and artifact factory"},
	{"id": "Trueform-Forge", "name": "Trueform Forge", "role": "Creative / tool concept"}
]
const GAMES := [
	{"id": "Furyline", "name": "Furyline", "role": "3D vehicle combat and cinematic missions"},
	{"id": "Ash-and-Anvil", "name": "Ash & Anvil", "role": "Tactile forge and dungeon"},
	{"id": "Chronicles-of-the-Eternal-Bastion", "name": "Chronicles of the Eternal Bastion", "role": "Tower-defense bakeoff variants"},
	{"id": "Gridfall", "name": "Gridfall", "role": "Experimental strategy/gameplay"},
	{"id": "Echoes", "name": "Echoes", "role": "Experimental game world"}
]

static func valid_mission_id(value: String) -> bool:
	if not value.begins_with("msn_") or value.length() != 16:
		return false
	for index in range(4, 16):
		var character := value.substr(index, 1)
		if not "0123456789abcdef".contains(character):
			return false
	return true

static func parse_mission_list(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "reason": "invalid_json"}
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("missions")) != TYPE_ARRAY:
		return {"ok": false, "reason": "invalid_mission_collection"}
	var missions: Array = data["missions"]
	if missions.size() > 500:
		return {"ok": false, "reason": "mission_collection_oversized"}
	var out: Array[Dictionary] = []
	var ids: Dictionary = {}
	for raw in missions:
		if typeof(raw) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "mission_item_not_object"}
		var id: Variant = raw.get("id")
		var title: Variant = raw.get("title")
		var state: Variant = raw.get("status")
		var risk: Variant = raw.get("risk")
		if typeof(id) != TYPE_STRING or not valid_mission_id(id) or ids.has(id):
			return {"ok": false, "reason": "mission_identity_rejected"}
		if typeof(title) != TYPE_STRING or title.strip_edges().is_empty():
			return {"ok": false, "reason": "mission_title_missing"}
		if typeof(state) != TYPE_STRING or not [
			"proposed", "awaiting_approval", "approved", "queued", "running",
			"succeeded", "failed", "cancelled", "rejected"
		].has(state):
			return {"ok": false, "reason": "mission_state_unrecognized"}
		if typeof(risk) != TYPE_STRING or not ["R0", "R1", "R2", "R3"].has(risk):
			return {"ok": false, "reason": "mission_risk_unrecognized"}
		ids[id] = true
		out.append({
			"id": id,
			"title": title.strip_edges().substr(0, 110),
			"status": state,
			"risk": risk,
			"source": "KiloCore-Studio/api/missions",
			"session_kind": "mission_log",
			"interactive": false
		})
	return {"ok": true, "missions": out}

static func parse_mission_log(text: String, expected_id: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "reason": "invalid_json"}
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY or data.get("id", "") != expected_id:
		return {"ok": false, "reason": "mission_log_identity_mismatch"}
	var lines: Variant = data.get("lines")
	if typeof(lines) != TYPE_ARRAY or lines.size() > 5000:
		return {"ok": false, "reason": "mission_log_shape_invalid"}
	var out := PackedStringArray()
	for line in lines.slice(maxi(0, lines.size() - 100)):
		if typeof(line) != TYPE_STRING:
			return {"ok": false, "reason": "invalid_log_line"}
		out.append(line.substr(0, 800).replace("\u0000", ""))
	return {"ok": true, "lines": out}

static func parse_services(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false}
	var raw: Variant = parser.data
	if typeof(raw) != TYPE_DICTIONARY or raw.get("schema", "") != "kilocore-studio.cockpit-health.v2":
		return {"ok": false}
	var colony: Variant = raw.get("colony_observation", {})
	var out: Array[Dictionary] = []
	if typeof(colony) != TYPE_DICTIONARY:
		return {"ok": true, "services": out}
	if colony.get("available", false) != true or colony.get("state", "") != "OBSERVED":
		return {"ok": true, "services": out}
	var projection: Variant = colony.get("projection", {})
	if typeof(projection) != TYPE_DICTIONARY:
		return {"ok": true, "services": out}
	var facts: Variant = projection.get("facts", {})
	if typeof(facts) != TYPE_DICTIONARY:
		return {"ok": true, "services": out}
	var observed: Variant = facts.get("services", [])
	if typeof(observed) != TYPE_ARRAY:
		return {"ok": true, "services": out}
	for item in observed.slice(0, 64):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var service_id: Variant = item.get("service_id")
		if typeof(service_id) != TYPE_STRING or service_id.is_empty() or service_id.length() > 64:
			continue
		var name: Variant = item.get("display_name", service_id)
		if typeof(name) != TYPE_STRING:
			name = service_id
		var semantic: Variant = item.get("semantic_health", {})
		var status := "unknown"
		if typeof(semantic) == TYPE_DICTIONARY:
			var value: Variant = semantic.get("value", "unknown")
			if typeof(value) == TYPE_STRING:
				status = value.substr(0, 32)
		out.append({
			"id": service_id,
			"name": String(name).substr(0, 70),
			"status": status,
			"source": "Kilo_Core Colony Observatory via Studio"
		})
	return {"ok": true, "services": out}
