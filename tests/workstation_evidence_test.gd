extends SceneTree

const EVIDENCE = preload("res://scripts/workstation/WorkbenchMissionEvidence.gd")
const PANE = preload("res://scripts/workstation/WorkbenchSessionPane.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var id := "msn_012345abcdef"
	var sample := {
		"id": id, "risk": "R2", "status": "succeeded", "review": true,
		"mergeable": false, "secret": "DO_NOT_SHOW",
		"result": {
			"receipt_id": "rcpt_123456789012", "secret_key": "DO_NOT_SHOW",
			"validator": {"exit_code": 0, "timed_out": false, "command": "DO_NOT_SHOW"},
			"report": {"raw_ok": true, "acceptance": [
				{"criterion": "smoke", "met": true},
				{"criterion": "playtest", "met": false}
			]},
			"commits": ["0123456789abcdef0123456789abcdef01234567"],
			"changed_paths": ["scripts/Repair.gd"]
		}
	}
	var parsed: Dictionary = EVIDENCE.parse(JSON.stringify(sample), id)
	_check(parsed.get("ok", false), "canonical evidence accepted")
	if parsed.get("ok", false):
		var text: String = EVIDENCE.format(parsed["proof"])
		_check(text.contains("1/2 acceptance criteria met"), "partial acceptance visible")
		_check(text.contains("PASS (exit 0)"), "validator exit accurately labelled")
		_check(text.contains("rcpt_123456789012"), "receipt ID projected")
		_check(text.contains("MERGE ELIGIBLE   NO"), "unmerged is not green")
		_check(not text.contains("DO_NOT_SHOW"), "secret and raw command fields excluded")
	_check(not EVIDENCE.parse(JSON.stringify(sample), "msn_111111111111").get("ok", false),
		"cross-mission swap refused")
	sample["result"]["validator"]["exit_code"] = 1
	var failed: Dictionary = EVIDENCE.parse(JSON.stringify(sample), id)
	_check(failed.get("ok", false) and
		EVIDENCE.format(failed["proof"]).contains("FAILED or TIMED OUT"),
		"failed validator cannot be green")
	sample["result"] = {}
	sample["status"] = "succeeded"
	var bare: Dictionary = EVIDENCE.parse(JSON.stringify(sample), id)
	_check(bare.get("ok", false) and EVIDENCE.format(bare["proof"]).contains("NOT REPORTED"),
		"success status with missing receipt is not presented as proven")
	# The mission pane must use the same configurable loopback port
	# for both the source GET and OPEN STUDIO, not a hardcoded 7340.
	var previous_port := OS.get_environment("GSV_STUDIO_ENTITY_PORT")
	OS.set_environment("GSV_STUDIO_ENTITY_PORT", "17341")
	var pane: PanelContainer = PANE.new()
	pane.configure({"session_kind": "mission_log", "id": id, "name": "Fixture",
		"status": "succeeded"}, null)
	root.add_child(pane)
	await process_frame
	_check(pane._port == 17341, "pane obeys configured same-host Studio port")
	OS.set_environment("GSV_STUDIO_ENTITY_PORT", previous_port)
	_check(pane._read_evidence != null and not pane._read_evidence.disabled,
		"mission exposes explicitly requested evidence read")
	_check(pane._terminal.text.contains("No live terminal"), "no fake PTY")
	pane.queue_free()
	await process_frame
	if failures.is_empty():
		print("WORKSTATION_EVIDENCE_PASS")
		quit(0)
	else:
		for error in failures:
			printerr("WORKSTATION_EVIDENCE_FAIL: " + error)
		quit(1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
