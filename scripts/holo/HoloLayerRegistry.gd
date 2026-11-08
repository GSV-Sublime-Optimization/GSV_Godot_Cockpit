class_name HoloLayerRegistry
extends RefCounted

## Module registry for the holographic cockpit, adapted from the war-room
## design doc (~/workspace/colony-loop/cockpit-design-20261107.md §3–§4):
## modules are now LAYERS in the volume, each with a world position, a depth,
## and a real source. Registration is data, not code edits in Main.gd.
##
## Honest states only: live / stale / unavailable / unknown / planned /
## degraded / dimmed / away / not_detected / awaiting / incoming. A layer or
## seat with no real source behind it is labelled, never faked.
##
## Seat verdicts are Lane B's (probed 2026-11-07 23:21–23:35 MST). One known
## discrepancy is flagged, not hidden: bake-off hub issue #13 still lists
## OpenClaw as UNVERIFIED, while Lane B found its process live (node PID
## 18788, gateway :18789, started 17:58) and Studio lists it OBSERVED in the
## colony_observation feed. This registry follows the fresher Lane B evidence
## (source cited on the seat) and the PR body asks the bake-off coordinator
## to reconcile #13. Soul Claw and MetaClaw stay NOT DETECTED (no creature,
## no card — empty desks with "awaiting" signs).

## Layers in the volume. "depth" is the stack order (1.0 = nearest the
## camera's rest position); live depth sorting uses view-space z (see
## HoloCoordinateStack.sort_layers_by_depth). "pos" is the rest position on
## the table; pull-up moves the layer toward the camera from there.
static func layer_defs() -> Array[Dictionary]:
	return [
		{"id": "studio-health", "title": "STUDIO HEALTH", "kind": "sense",
			"source": "127.0.0.1:7340/api/health (Mind Slice 0)",
			"state": "unknown", "depth": 1.0, "pos": Vector3(-3.2, 2.6, -1.2)},
		{"id": "gateway-health", "title": "GATEWAY", "kind": "sense",
			"source": "127.0.0.1:8001/health (Mind Slice 2)",
			"state": "unknown", "depth": 1.4, "pos": Vector3(0.0, 2.8, -1.6)},
		{"id": "constellation", "title": "CONSTELLATION", "kind": "sense",
			"source": "127.0.0.1:7340/api/projects (Mind Slice 1)",
			"state": "unknown", "depth": 1.8, "pos": Vector3(3.2, 2.6, -1.2)},
		{"id": "fleet-bodies", "title": "FLEET BODIES", "kind": "sense",
			"source": "KiloCore-Studio entity-bodies (Mind, Keath 2026-11-07)",
			"state": "unknown", "depth": 2.2, "pos": Vector3(-1.6, 3.6, -2.2)},
		{"id": "dev-mentor-game", "title": "DEV-MENTOR · GAME", "kind": "game",
			"source": "127.0.0.1:7337/api/health (MSI local, slow: 10s+ async)",
			"state": "unknown", "depth": 2.6, "pos": Vector3(1.6, 3.6, -2.2)},
		{"id": "terminal-msi", "title": "TERMINAL · MSI", "kind": "terminal",
			"source": "broker: none — PLANNED (mssh lanes only)",
			"state": "planned", "depth": 3.0, "pos": Vector3(-3.4, 2.2, 1.6)},
		{"id": "terminal-i3", "title": "TERMINAL · i3", "kind": "terminal",
			"source": "broker: none — PLANNED (SSH hangs from session-0)",
			"state": "planned", "depth": 3.2, "pos": Vector3(-1.1, 2.2, 1.6)},
		{"id": "terminal-l9", "title": "TERMINAL · L9", "kind": "terminal",
			"source": "broker: none — PLANNED (off tailnet)",
			"state": "planned", "depth": 3.4, "pos": Vector3(1.1, 2.2, 1.6)},
		{"id": "terminal-xanadu", "title": "TERMINAL · XANADU", "kind": "terminal",
			"source": "broker: none — PLANNED (SSH hangs from session-0)",
			"state": "planned", "depth": 3.6, "pos": Vector3(3.4, 2.2, 1.6)},
		{"id": "mind-view", "title": "MIND VIEW", "kind": "incoming",
			"source": "PR #12 (Claude, unmerged) — fleet map + transcript",
			"state": "incoming", "depth": 4.0, "pos": Vector3(0.0, 2.4, 2.6)},
	]


static func layer_def(layer_id: String) -> Dictionary:
	for def in layer_defs():
		if String(def.get("id", "")) == layer_id:
			return def
	return {}


## Verified seats (Lane B). "creature" = a working/dimmed figure at the desk;
## false = an empty chair or an empty desk with an honest reason. The war-room
## spirit (embodied agents, visible work) with the hologram form: the seats
## ring the table the volume floats above.
static func seat_defs() -> Array[Dictionary]:
	return [
		{"id": "openclaw", "name": "OpenClaw", "state": "live",
			"note": "node PID 18788, :18789, Studio OBSERVED",
			"creature": true},
		{"id": "chatdev", "name": "ChatDev", "state": "live",
			"note": ":7338, ai_ok + redis_ok",
			"creature": true},
		{"id": "claude", "name": "Claude", "state": "dimmed",
			"note": "live process, rate-limited, OAuth expired",
			"creature": true},
		{"id": "codex", "name": "Codex", "state": "live",
			"note": "app-server daemon 0.167.0",
			"creature": true},
		{"id": "jev", "name": "Jev / OpenJev", "state": "live",
			"note": "the judge at its desk",
			"creature": true},
		{"id": "serena", "name": "Serena", "state": "live",
			"note": "serena.exe + wrappers",
			"creature": true},
		{"id": "ollama", "name": "Ollama", "state": "live",
			"note": "the model shelf",
			"creature": true},
		{"id": "devmentor", "name": "Dev-Mentor MCP", "state": "live",
			"note": "MCP server + launcher",
			"creature": true},
		{"id": "skyclaw", "name": "Skyclaw", "state": "degraded",
			"note": "scanner running, DB locked; down-verdicts unreliable",
			"creature": true},
		{"id": "hermes", "name": "Hermes", "state": "away",
			"note": "harness installed, not running",
			"creature": false},
		{"id": "gordon", "name": "Gordon", "state": "not_detected",
			"note": "docs only",
			"creature": false},
		{"id": "aider", "name": "Aider", "state": "not_detected",
			"note": "qualified, not running",
			"creature": false},
		{"id": "goose", "name": "Goose", "state": "not_detected",
			"note": "qualified, not running",
			"creature": false},
		{"id": "copilot", "name": "Copilot", "state": "not_detected",
			"note": "quota exhausted",
			"creature": false},
		{"id": "soulclaw", "name": "Soul Claw", "state": "awaiting",
			"note": "not detected — empty desk",
			"creature": false},
		{"id": "metaclaw", "name": "MetaClaw", "state": "awaiting",
			"note": "not detected — empty desk",
			"creature": false},
	]


## States a layer or seat may honestly carry. Anything else is a bug.
const HONEST_STATES: PackedStringArray = [
	"live", "stale", "unavailable", "unknown", "planned",
	"degraded", "dimmed", "away", "not_detected", "awaiting", "incoming",
	"simulated", "empty",
]


static func is_honest_state(state: String) -> bool:
	return HONEST_STATES.has(state)
