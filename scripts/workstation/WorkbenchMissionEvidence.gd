extends RefCounted

## Narrow read model over Studio's canonical GET /api/missions/{id}.
## A success state alone is not evidence. Never display raw prompts or tool payloads.

const STATES := ["proposed", "awaiting_approval", "approved", "queued",
	"running", "succeeded", "failed", "cancelled", "rejected"]
const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")
const CONTRACT = preload("res://scripts/workstation/WorkbenchMissionContract.gd")

static func parse(text: String, expected_id: String) -> Dictionary:
	if text.length() > 131072 or not CATALOG.valid_mission_id(expected_id):
		return {"ok": false, "reason": "evidence_oversized_or_bad_id"}
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_evidence_json"}
	var raw: Dictionary = parser.data
	if raw.get("id", "") != expected_id:
		return {"ok": false, "reason": "wrong_mission"}
	var status: Variant = raw.get("status")
	var risk: Variant = raw.get("risk")
	if typeof(status) != TYPE_STRING or not STATES.has(status):
		return {"ok": false, "reason": "unknown_lifecycle"}
	if typeof(risk) != TYPE_STRING or not ["R0", "R1", "R2", "R3"].has(risk):
		return {"ok": false, "reason": "unknown_risk"}
	var repository := ""
	var repo: Variant = raw.get("repo", "")
	if typeof(repo) == TYPE_STRING and CONTRACT._safe_path(repo):
		repository = repo
	var proof := {
		"id": expected_id, "status": status, "risk": risk, "repo": repository,
		"review": raw.get("review", false) == true,
		"mergeable": raw.get("mergeable", false) == true,
		"receipt": "NOT REPORTED", "validator": "NOT REPORTED",
		"report": "NOT REPORTED", "audit": "NOT REPORTED", "commits": [], "changed_paths": []
	}
	# Studio owns merge admission. Never infer a PASS from an executor exit code.
	var gate: Variant = raw.get("validator_admission")
	if typeof(gate) == TYPE_DICTIONARY:
		var gate_state: Variant = gate.get("state")
		if typeof(gate_state) == TYPE_STRING and ["PASS", "BLOCKED", "NOT_REQUIRED"].has(gate_state):
			var gate_reason := ""
			if typeof(gate.get("reason")) == TYPE_STRING:
				gate_reason = String(gate["reason"]).replace("\\n", " ").replace("\\r", " ").substr(0, 180)
			proof["validator"] = String(gate_state) + (" / " + gate_reason if not gate_reason.is_empty() else "")
	var result: Variant = raw.get("result")
	if typeof(result) != TYPE_DICTIONARY:
		return {"ok": true, "proof": proof}
	var receipt: Variant = result.get("receipt_id")
	if typeof(receipt) == TYPE_STRING and receipt.length() >= 8 and receipt.length() <= 120:
		proof["receipt"] = receipt.strip_escapes()
	# The acceptance audit is owner-reconciled against immutable criteria.
	var audit: Variant = result.get("acceptance_audit")
	if typeof(audit) == TYPE_DICTIONARY:
		var audit_state: Variant = audit.get("status")
		if typeof(audit_state) == TYPE_STRING and ["reported_complete", "incomplete", "missing_report"].has(audit_state):
			proof["audit"] = String(audit_state).to_upper()
	var report: Variant = result.get("report")
	if typeof(report) == TYPE_DICTIONARY and typeof(report.get("raw_ok")) == TYPE_BOOL:
		var acc: Variant = report.get("acceptance", [])
		if typeof(acc) == TYPE_ARRAY and acc.size() <= 32:
			var total := 0
			var met := 0
			for row in acc:
				if typeof(row) != TYPE_DICTIONARY or typeof(row.get("met")) != TYPE_BOOL:
					continue
				total += 1
				if row["met"]:
					met += 1
			proof["report"] = ("executor self-report: %d/%d claimed met" % [met, total]
				if report["raw_ok"] else "executor report explicitly invalid")
	var commits: Variant = result.get("commits", [])
	if typeof(commits) == TYPE_ARRAY:
		for sha in commits.slice(0, 8):
			if typeof(sha) == TYPE_STRING and sha.length() == 40 and sha.is_valid_hex_number():
				proof["commits"].append(sha)
	var changed: Variant = result.get("changed_paths", [])
	if typeof(changed) == TYPE_ARRAY:
		for path in changed.slice(0, 24):
			if typeof(path) == TYPE_STRING and path.length() <= 180:
				proof["changed_paths"].append(path.strip_escapes())
	return {"ok": true, "proof": proof}

static func format(proof: Dictionary) -> String:
	var lines := PackedStringArray([
		"MISSION EVIDENCE / STUDIO SOURCE", "",
		"ID               " + String(proof.get("id", "")),
		"REPO             " + String(proof.get("repo", "NOT REPORTED")),
		"STATUS           " + String(proof.get("status", "unknown")),
		"RISK             " + String(proof.get("risk", "unknown")),
		"REVIEW FLAG      " + ("YES" if proof.get("review", false) else "NO"),
		"MERGE ELIGIBLE   " + ("YES (still owner-gated)" if proof.get("mergeable", false) else "NO / UNKNOWN"),
		"RECEIPT ID       " + String(proof.get("receipt", "NOT REPORTED")),
		"VALIDATOR        " + String(proof.get("validator", "NOT REPORTED")),
		"ACCEPTANCE AUDIT " + String(proof.get("audit", "NOT REPORTED")),
		"REPORT           " + String(proof.get("report", "NOT REPORTED")), "",
		"COMMITS"
	])
	var commits: Array = proof.get("commits", [])
	if commits.is_empty():
		lines.append("  None reported")
	else:
		for sha in commits:
			lines.append("  " + String(sha))
	lines.append("")
	lines.append("CHANGED PATHS")
	var paths: Array = proof.get("changed_paths", [])
	if paths.is_empty():
		lines.append("  None reported")
	else:
		for path in paths:
			lines.append("  " + String(path))
	lines.append("")
	lines.append("Studio is authoritative for mission lifecycle and receipt links.")
	lines.append("Studio validator_admission and acceptance_audit are owner projections; executor self-report is not independent evidence.")
	lines.append("No merge, deployment, runner admission or approval originates here.")
	return "\n".join(lines)
