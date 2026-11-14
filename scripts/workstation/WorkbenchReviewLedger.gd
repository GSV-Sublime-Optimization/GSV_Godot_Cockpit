extends RefCounted

## Strict read-only adapter for externally produced GitHub/GSV investigation queues.
## A PR state observation is NOT a gsv approval, a merge gate, or actor capacity.

const SCHEMA := "gsv.review-operations.v1"
const MAX_BYTES := 131072
const MAX_ITEMS := 48
const LANES := ["gate_recheck_candidate", "independent_review", "verify_check",
	"repair_ci", "repair_conflict", "author_changes", "author_provenance",
	"dependency_review", "author_admission", "inspect_source"]
const STATUSES := ["passed", "failed", "pending", "unobserved"]
const REVIEWS := ["APPROVED", "CHANGES_REQUESTED", "UNVERIFIED"]
const MERGEABLE := ["MERGEABLE", "CONFLICTING", "UNKNOWN"]

static func _slug(s: String) -> bool:
	if s.is_empty() or s.length() > 120:
		return false
	for char in s:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-".contains(char):
			return false
	return true

static func _sha(s: String) -> bool:
	if s.is_empty():
		return true
	if s.length() != 40:
		return false
	for c in s:
		if not "0123456789abcdef".contains(c):
			return false
	return true

static func parse(text: String, now_unix: float = -1.0) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok": false, "reason": "oversized"}
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_json"}
	var root: Dictionary = json.data
	if root.get("schema", "") != SCHEMA:
		return {"ok": false, "reason": "wrong_schema"}
	var generated: Variant = root.get("generated_utc")
	if typeof(generated) != TYPE_STRING or generated.length() != 20 or not generated.ends_with("Z"):
		return {"ok": false, "reason": "missing_source_timestamp"}
	var at := Time.get_unix_time_from_datetime_string(generated)
	if at <= 0:
		return {"ok": false, "reason": "invalid_source_timestamp"}
	var now := Time.get_unix_time_from_system() if now_unix < 0 else now_unix
	var age := now - at
	var ttl: Variant = root.get("ttl_seconds")
	if typeof(ttl) != TYPE_INT and typeof(ttl) != TYPE_FLOAT:
		return {"ok": false, "reason": "invalid_ttl"}
	if int(ttl) < 1 or int(ttl) > 900 or ttl != int(ttl):
		return {"ok": false, "reason": "invalid_ttl"}
	if age < -30.0:
		return {"ok": false, "reason": "future_dated"}
	if age > float(ttl):
		return {"ok": false, "reason": "stale_source", "age_seconds": age}
	if root.get("gate", "") != "advisory_only_exact_head_gsv_merge_dry_run_required":
		return {"ok": false, "reason": "unsafe_authority_claim"}
	var raw: Variant = root.get("items")
	if typeof(raw) != TYPE_ARRAY or raw.size() > MAX_ITEMS:
		return {"ok": false, "reason": "invalid_collection"}
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	for record in raw:
		if typeof(record) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_row"}
		var key: Variant = record.get("key")
		var repo: Variant = record.get("repo")
		var number: Variant = record.get("number")
		var head: Variant = record.get("head")
		var lane: Variant = record.get("lane")
		if typeof(repo) != TYPE_STRING or not repo.begins_with("GSV-Sublime-Optimization/"):
			return {"ok": false, "reason": "untrusted_repo"}
		if not _slug(repo.trim_prefix("GSV-Sublime-Optimization/")):
			return {"ok": false, "reason": "invalid_repo"}
		if (typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT) or (
			number < 1 or number > 9999999 or float(number) != float(int(number))):
			return {"ok": false, "reason": "invalid_pr_number"}
		var expected := "https://github.com/%s/pull/%d" % [repo, number]
		if typeof(record.get("url")) != TYPE_STRING or record.get("url") != expected:
			return {"ok": false, "reason": "untrusted_url"}
		if typeof(key) != TYPE_STRING or key != "%s#%d" % [repo, number] or seen.has(key):
			return {"ok": false, "reason": "identity_mismatch"}
		if typeof(head) != TYPE_STRING or not _sha(head):
			return {"ok": false, "reason": "invalid_head"}
		if typeof(lane) != TYPE_STRING or not LANES.has(lane):
			return {"ok": false, "reason": "unknown_review_lane"}
		if not STATUSES.has(record.get("ci")) or not REVIEWS.has(record.get("review")):
			return {"ok": false, "reason": "untrusted_status"}
		if not MERGEABLE.has(record.get("mergeable")):
			return {"ok": false, "reason": "untrusted_mergeability"}
		if record.get("assignment_authorized", true) != false:
			return {"ok": false, "reason": "false_assignment_authority"}
		var blockers: Variant = record.get("blockers", [])
		if typeof(blockers) != TYPE_ARRAY or blockers.size() > 20:
			return {"ok": false, "reason": "invalid_blockers"}
		for blocker in blockers:
			if typeof(blocker) != TYPE_STRING or blocker.length() > 60:
				return {"ok": false, "reason": "invalid_blocker"}
		var title: Variant = record.get("title", "")
		if typeof(title) != TYPE_STRING or title.length() > 130:
			return {"ok": false, "reason": "invalid_title"}
		var actor: Variant = record.get("suggested_actor", "")
		if typeof(actor) != TYPE_STRING or actor.length() > 80 or (
			not actor.is_empty() and not actor.begins_with("agent/")):
			return {"ok": false, "reason": "invalid_actor"}
		var score: Variant = record.get("score")
		if (typeof(score) != TYPE_INT and typeof(score) != TYPE_FLOAT) or (
			score < 0 or score > 120 or float(score) != float(int(score))):
			return {"ok": false, "reason": "invalid_score"}
		var branch: Variant = record.get("base", "")
		if typeof(branch) != TYPE_STRING or branch.length() > 90:
			return {"ok": false, "reason": "invalid_base"}
		seen[key] = true
		entries.append({
			"key": key, "repo": repo, "number": int(number), "url": expected,
			"title": String(title).strip_escapes(), "head": head,
			"base": String(branch).strip_escapes(), "draft": record.get("draft") == true,
			"ci": record["ci"], "review": record["review"], "mergeable": record["mergeable"],
			"lane": lane, "score": int(score),
			"blockers": blockers.duplicate(true),
			"suggested_actor": actor,
			"routing_reason": String(record.get("routing_reason", "")).substr(0, 140).strip_escapes(),
			"detail_observed": record.get("detail_observed", false) == true,
			"provenance": record.get("provenance", false) == true,
			"updated_at": String(record.get("updated_at", "")).substr(0, 36)
		})
	return {
		"ok": true, "items": entries, "count": entries.size(), "generated_utc": generated,
		"age_seconds": age, "source": "GitHub gh-cli read-only",
		"gate": "advisory_only_exact_head_gsv_merge_dry_run_required"
	}

static func read_optional() -> Dictionary:
	var paths: Array[String] = []
	var supplied := OS.get_environment("GSV_REVIEW_QUEUE_PATH")
	if not supplied.is_empty() and supplied.is_absolute_path() and not supplied.contains(".."):
		paths.append(supplied)
	var local := OS.get_environment("LOCALAPPDATA")
	if not local.is_empty() and local.is_absolute_path():
		paths.append(local.path_join("GSV_Cockpit").path_join("review_queue.json"))
	paths.append("user://review_queue.json")
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return {"ok": false, "reason": "cannot_read_export", "source": path}
		if f.get_length() > MAX_BYTES:
			f.close()
			return {"ok": false, "reason": "oversized_file", "source": path}
		var text := f.get_as_text()
		f.close()
		var parsed := parse(text)
		parsed["source_path"] = path
		return parsed
	return {"ok": false, "reason": "not_exported",
		"source_path": "GSV_REVIEW_QUEUE_PATH or LOCALAPPDATA/GSV_Cockpit/review_queue.json"}

static func brief(row: Dictionary) -> String:
	var repo := String(row.get("repo", ""))
	var number := int(row.get("number", 0))
	var head := String(row.get("head", ""))
	if not _sha(head) or head.is_empty() or not repo.begins_with("GSV-Sublime-Optimization/"):
		return ""
	return ("[GSV REVIEW INVESTIGATION / ADVISORY ONLY]\n"
		+ "PR: " + repo + "#" + str(number)
		+ "\nEXACT HEAD: " + head
		+ "\nTITLE: " + String(row.get("title", ""))
		+ "\nBASE: " + String(row.get("base", ""))
		+ "\nSTATE: " + String(row.get("lane", ""))
		+ "\nCHECK: " + String(row.get("ci", ""))
		+ "\nBLOCKERS: " + ", ".join(row.get("blockers", []))
		+ "\nSUGGESTED ACTOR (NOT ASSIGNED): " +
			(String(row.get("suggested_actor", "")) if not String(row.get("suggested_actor", "")).is_empty()
			else "UNOBSERVED")
		+ "\nOPEN: https://github.com/" + repo + "/pull/" + str(number)
		+ "\nREVIEW: inspect patch and exact-head tests, verify actor independence,"
		+ " author provenance and the source owning execution route.\n"
		+ "Never merge on this snapshot alone; run current gsv merge --dry-run."
	)
