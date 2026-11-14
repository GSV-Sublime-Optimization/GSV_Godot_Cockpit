extends RefCounted

## A narrow Studio-owned mission transport contract. It cannot grant executor authority.
## Every repo choice originates in a fresh canonical Project Constellation read.

const PROJECT_SCHEMA := "kilocore-studio.projects-scan.v2"
const MISSION_STATES := ["proposed", "awaiting_approval", "approved", "queued", "running", "succeeded", "failed", "cancelled", "rejected"]

static func parse_projects(text: String) -> Dictionary:
	if text.length() > 524288:
		return {"ok": false, "reason": "oversized_projects"}
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_projects_json"}
	var raw: Dictionary = json.data
	if raw.get("schema", "") != PROJECT_SCHEMA or raw.get("state", "") != "OBSERVED":
		return {"ok": false, "reason": "projects_not_observed"}
	var source: Variant = raw.get("projects")
	if typeof(source) != TYPE_ARRAY or source.size() > 512:
		return {"ok": false, "reason": "invalid_projects_array"}
	var eligible: Array[Dictionary] = []
	var seen := {}
	for entry in source:
		if typeof(entry) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_project"}
		var git: Variant = entry.get("git")
		if typeof(git) != TYPE_DICTIONARY or git.get("is_repo", false) != true:
			continue
		var path: Variant = entry.get("path")
		var branch: Variant = git.get("branch")
		var name: Variant = entry.get("name")
		if typeof(path) != TYPE_STRING or typeof(branch) != TYPE_STRING or typeof(name) != TYPE_STRING:
			continue
		if not _safe_path(path) or not _safe_branch(branch) or name.is_empty() or name.length() > 128:
			continue
		if seen.has(path):
			return {"ok": false, "reason": "duplicate_project_path"}
		seen[path] = true
		eligible.append({"name": name, "path": path, "branch": branch})
	return {"ok": true, "projects": eligible}

static func _safe_path(path: String) -> bool:
	return (path.length() >= 3 and path.length() <= 500
		and path.is_absolute_path() and not path.contains("\n")
		and not path.contains("\r") and not path.contains("..")
		and not path.contains("://"))

static func _safe_branch(branch: String) -> bool:
	if branch.is_empty() or branch.length() > 160 or branch.contains("..") or branch.contains("@{"):
		return false
	if branch.begins_with("/") or branch.ends_with("/") or branch.ends_with("."):
		return false
	for ch in branch:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-".contains(ch):
			return false
	return true

static func make_spec(project: Dictionary, title: String, objective: String,
		acceptance_text: String, risk: String) -> Dictionary:
	var repo: Variant = project.get("path")
	var branch: Variant = project.get("branch")
	if typeof(repo) != TYPE_STRING or not _safe_path(repo):
		return {"ok": false, "reason": "project_not_qualified"}
	if typeof(branch) != TYPE_STRING or not _safe_branch(branch):
		return {"ok": false, "reason": "branch_not_qualified"}
	var clean_title := title.strip_edges()
	var clean_objective := objective.strip_edges()
	if clean_title.length() < 6 or clean_title.length() > 120:
		return {"ok": false, "reason": "title_must_be_6_to_120_chars"}
	if clean_objective.length() < 20 or clean_objective.length() > 6000:
		return {"ok": false, "reason": "objective_must_be_20_to_6000_chars"}
	if not ["R0", "R1", "R2"].has(risk):
		return {"ok": false, "reason": "risk_not_supported_here"}
	var criteria: Array[String] = []
	for line in acceptance_text.split("\n"):
		var criterion := line.strip_edges()
		if criterion.is_empty():
			continue
		if criterion.length() > 300 or criteria.size() >= 8:
			return {"ok": false, "reason": "acceptance_limit"}
		criteria.append(criterion)
	if criteria.is_empty():
		return {"ok": false, "reason": "acceptance_required"}
	return {"ok": true, "body": {
		"title": clean_title, "objective": clean_objective, "acceptance": criteria,
		"repo": repo, "base_branch": branch, "risk": risk,
		"posted_by": "godot-workstation"
	}}

static func parse_post_result(status: int, text: String, expected_repo: String,
		expected_risk: String) -> Dictionary:
	if status != 201 or text.length() > 65536:
		return {"ok": false, "reason": "no_201_acknowledgement"}
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_mission_ack"}
	var raw: Dictionary = json.data
	var mission_id: Variant = raw.get("id")
	var state: Variant = raw.get("status")
	if typeof(mission_id) != TYPE_STRING or not _mission_id(mission_id):
		return {"ok": false, "reason": "invalid_mission_id"}
	if typeof(state) != TYPE_STRING or not MISSION_STATES.has(state):
		return {"ok": false, "reason": "invalid_mission_state"}
	if raw.get("repo") != expected_repo or raw.get("risk") != expected_risk:
		return {"ok": false, "reason": "mission_identity_mismatch"}
	return {"ok": true, "id": mission_id, "status": state,
		"needs_approval": state == "awaiting_approval"}

static func _mission_id(value: String) -> bool:
	if not value.begins_with("msn_") or value.length() != 16:
		return false
	for i in range(4, 16):
		if not "0123456789abcdef".contains(value.substr(i, 1)):
			return false
	return true
