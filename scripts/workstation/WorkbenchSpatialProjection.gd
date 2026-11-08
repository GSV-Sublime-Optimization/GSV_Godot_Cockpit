extends RefCounted

## A deterministic, bounded spatial projection of owning Studio observations.
## Geometry is the visualization, not another colony topology or mission authority.
## Coordinates encode four axes: resource domain (Y), owner grouping (azimuth),
## state (emission), and recorded mission age (radial drift when a timestamp exists).

const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")
const MAX_PROJECTS := 32
const MAX_MISSIONS := 24
const MAX_SERVICES := 24
const BODY_POSITIONS := [
	Vector3(-8.0, -3.0, -4.0), Vector3(8.0, -3.0, -4.0),
	Vector3(-8.0, -3.0, 4.0), Vector3(8.0, -3.0, 4.0),
]

static func project(snapshot: Dictionary) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var by_key: Dictionary = {}
	var state: Dictionary = {}
	for key in ["body_feed_state", "project_feed_state", "mission_feed_state", "service_feed_state"]:
		state[key] = _feed_state(String(snapshot.get(key, "unknown")))
	var body_lookup: Dictionary = {}
	var bodies: Variant = snapshot.get("bodies", [])
	if typeof(bodies) == TYPE_ARRAY:
		for candidate in bodies.slice(0, 32):
			if typeof(candidate) == TYPE_DICTIONARY and typeof(candidate.get("body_id")) == TYPE_STRING:
				body_lookup[candidate["body_id"]] = candidate
	for i in range(CATALOG.RIGS.size()):
		var rig: Dictionary = CATALOG.RIGS[i]
		var id: String = rig["id"]
		var observed: Dictionary = body_lookup.get(id, {})
		var live_state := "unknown"
		if state["body_feed_state"] == "observed":
			live_state = _rig_state(String(observed.get("state", "unknown")))
		elif state["body_feed_state"] == "stale":
			live_state = "stale"
		_push(nodes, by_key, {
			"key": "rig:" + id, "kind": "rig", "id": id, "title": rig["name"],
			"detail": rig["role"], "status": live_state,
			"source": "Studio /api/entity/bodies", "position": BODY_POSITIONS[i],
			"resources": observed.get("observation", {}) if typeof(observed.get("observation", {})) == TYPE_DICTIONARY else {},
			"observed": state["body_feed_state"] == "observed"
		})
	var projects: Variant = snapshot.get("projects", [])
	if state["project_feed_state"] == "observed" and typeof(projects) == TYPE_ARRAY:
		var selected: Array = projects.slice(0, MAX_PROJECTS)
		for i in range(selected.size()):
			var p: Variant = selected[i]
			if typeof(p) != TYPE_DICTIONARY:
				continue
			if typeof(p.get("path")) != TYPE_STRING or typeof(p.get("branch")) != TYPE_STRING:
				continue
			var path: String = p["path"]
			if not path.is_absolute_path() or path.contains("..") or path.length() > 500:
				continue
			var is_game := false
			for candidate_game in CATALOG.GAMES:
				if String(candidate_game["id"]).to_lower() == String(p.get("name", "")).to_lower() or (
					String(candidate_game["id"]).to_lower() == path.get_file().to_lower()):
					is_game = true
			_push(nodes, by_key, {
				"key": "project:" + path, "kind": "project", "game": is_game,
				"id": path, "repo": path,
				"title": String(p.get("name", "Project")).substr(0, 72),
				"detail": String(p["branch"]).substr(0, 160),
				"status": "observed", "source": "Studio /api/projects",
				"position": _orbit(i, selected.size(), 7.5, 4.0, 0.0),
				"observed": true
			})
	var missions: Variant = snapshot.get("missions", [])
	if state["mission_feed_state"] == "observed" and typeof(missions) == TYPE_ARRAY:
		var selected: Array = missions.slice(0, MAX_MISSIONS)
		for i in range(selected.size()):
			var m: Variant = selected[i]
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var id: String = String(m.get("id", ""))
			if not CATALOG.valid_mission_id(id):
				continue
			var status := String(m.get("status", "unknown"))
			var repo_path := String(m.get("repo", ""))
			var updated := String(m.get("updated_at", ""))
			var drift := _age_drift(updated)
			var point := _orbit(i, selected.size(), 4.7 + drift, 0.6, 0.35)
			_push(nodes, by_key, {
				"key": "mission:" + id, "kind": "mission", "id": id,
				"title": String(m.get("title", "Mission")).substr(0, 72),
				"detail": String(m.get("risk", "?")) + " / " + status,
				"status": status, "repo": repo_path,
				"updated_at": updated, "position": point,
				"source": "Studio /api/missions", "observed": true
			})
			if by_key.has("project:" + repo_path):
				edges.append({"from": "project:" + repo_path, "to": "mission:" + id, "kind": "verified_repo"})
	var services: Variant = snapshot.get("services", [])
	if state["service_feed_state"] == "observed" and typeof(services) == TYPE_ARRAY:
		var selected: Array = services.slice(0, MAX_SERVICES)
		for i in range(selected.size()):
			var s: Variant = selected[i]
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var id := String(s.get("id", ""))
			if id.is_empty() or id.length() > 64:
				continue
			_push(nodes, by_key, {
				"key": "service:" + id, "kind": "service", "id": id,
				"title": String(s.get("name", id)).substr(0, 72),
				"detail": "Colony service / observed state only",
				"status": String(s.get("status", "unknown")).to_lower(),
				"source": "Studio colony health", "position": _orbit(i, selected.size(), 10.2, -0.1, 0.6),
				"observed": true
			})
	return {"nodes": nodes, "edges": edges, "feeds": state, "source": "KiloCore Studio", "is_fixture": false}

static func _push(nodes: Array[Dictionary], lookup: Dictionary, entry: Dictionary) -> void:
	if lookup.has(entry["key"]):
		return
	lookup[entry["key"]] = true
	nodes.append(entry)

static func _feed_state(value: String) -> String:
	return value if ["observed", "stale", "unknown", "unavailable"].has(value) else "unknown"

static func _rig_state(value: String) -> String:
	return value if ["reported_fresh", "stale", "unknown", "invalid", "unavailable"].has(value) else "unknown"

static func _orbit(index: int, count: int, radius: float, height: float, phase: float) -> Vector3:
	var angle: float = TAU * float(index) / float(maxi(1, count)) + phase
	return Vector3(cos(angle) * radius, height, sin(angle) * radius)

static func _age_drift(value: String) -> float:
	## Only a recorded timezone-aware ISO date permits a time coordinate.
	## No timestamp means no invented age.
	if value.length() < 20 or not value.ends_with("Z"):
		return 0.0
	var unix: float = Time.get_unix_time_from_datetime_string(value)
	if unix <= 0.0:
		return 0.0
	var age_h: float = (Time.get_unix_time_from_system() - unix) / 3600.0
	if age_h < 0.0:
		return 0.0
	return clampf(age_h / 24.0, 0.0, 3.0)

static func color_for(status: String) -> Color:
	match status:
		"reported_fresh", "observed", "succeeded", "healthy", "ok", "up":
			return Color("#39ecd0")
		"running", "queued", "approved":
			return Color("#56baff")
		"awaiting_approval", "proposed":
			return Color("#ffcf72")
		"failed", "invalid", "down", "error", "unhealthy", "degraded":
			return Color("#ff647f")
		"stale", "cancelled", "rejected":
			return Color("#b482ff")
		_:
			return Color("#6d788e")
