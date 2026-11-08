extends RefCounted

## Schema-pinned projection for Dev-Mentor's health surface
## (GET http://127.0.0.1:7337/api/health, MSI local). The game layer's real
## source: Dev-Mentor is the colony's game host (Terminal Depths) and its
## health reports the live game engine + active game sessions.
##
## Same discipline as the Mind's projections (PRs #8–#11): admit only named
## fields, bounded; reject malformed / wrong-shape / oversized bodies with a
## fixed reason string. No bodies, paths, prompts, secrets, or tokens cross.
## The spine snapshot (/api/spine) is NOT admitted here — it was probed
## UNAVAILABLE (12 s timeout on MSI localhost, 15 s to the i3) and any
## spine-derived data shows UNKNOWN, never fabricated.

const EXPECTED_OK := true
const MAX_BODY_CHARS := 8192

static func parse_health(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BODY_CHARS:
		return _invalid("mentor_response_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	if bool(body.get("ok", false)) != EXPECTED_OK:
		return _invalid("mentor_not_ok")
	var uptime: Variant = body.get("uptime_s", null)
	if typeof(uptime) != TYPE_INT and typeof(uptime) != TYPE_FLOAT:
		return _invalid("invalid_uptime")
	var uptime_n := float(uptime)
	if uptime_n < 0.0 or uptime_n > 1000000000.0 or floorf(uptime_n) != uptime_n:
		return _invalid("invalid_uptime")
	var sessions: Variant = body.get("active_game_sessions", null)
	if typeof(sessions) != TYPE_INT and typeof(sessions) != TYPE_FLOAT:
		return _invalid("invalid_game_sessions")
	var sessions_n := float(sessions)
	if sessions_n < 0.0 or sessions_n > 1000000.0 or floorf(sessions_n) != sessions_n:
		return _invalid("invalid_game_sessions")
	var engine: Variant = body.get("game_engine", null)
	if typeof(engine) != TYPE_BOOL:
		return _invalid("invalid_game_engine")
	return {
		"ok": true,
		"observation": {
			"state": "live",
			"source": "Dev-Mentor/GET-api-health",
			"uptime_s": int(uptime_n),
			"game_engine": bool(engine),
			"active_game_sessions": int(sessions_n),
			"observed_at_ms": 0,
			"error": "",
		},
	}

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
