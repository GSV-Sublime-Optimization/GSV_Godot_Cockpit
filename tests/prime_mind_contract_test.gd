extends SceneTree

const CONTRACT = preload("res://tools/prime_mind/FeedContract.gd")
const FIXTURE := "res://tests/fixtures/prime_mind_feed.json"
const WORK_FIXTURE := "res://tests/fixtures/prime_mind_work_feed.json"
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var text := FileAccess.get_file_as_string(FIXTURE)
	var result: Dictionary = CONTRACT.parse_text(text, "PINNED_SHARED_SNAPSHOT")
	_check(result.get("ok", false), "actual shared competitor fixture admitted")
	if result.get("ok", false):
		_check(result["events"].size() == 13, "13 recorded shared fixture events")
		_check(result["bodies"].size() == 4, "exact four body source map")
		_check(CONTRACT.source_state(result, true) == "PINNED FIXTURE",
			"snapshot does not counterfeit fresh telemetrics")
		var model_count := 0
		var observer_count := 0
		for e in result["events"]:
			if e["identity"] == "model_summary":
				model_count += 1
			if e["identity"] == "monitor":
				observer_count += 1
		_check(model_count > 0 and observer_count > 0,
			"model summaries and deterministic monitor lines distinguishable")
		var sources: Dictionary = result["bodies"]
		_check(sources["i3"]["status"] == "red", "i3 recorded failing state preserved")
		_check(sources["xanadu"]["status"] == "green", "xanadu source status preserved")
		var malicious: Dictionary = JSON.parse_string(text)
		malicious["bodies"]["i3"]["status"] = "I am a root shell!"
		_check(not CONTRACT.parse_text(JSON.stringify(malicious)).get("ok", false),
			"unrecognized health status fails closed")
		malicious = JSON.parse_string(text)
		malicious["events"][0]["reasons"] = ["x".repeat(400)]
		_check(not CONTRACT.parse_text(JSON.stringify(malicious)).get("ok", false),
			"oversized rationale rejected")
		malicious = JSON.parse_string(text)
		malicious["events"][0]["focus"] = "fake-machine"
		_check(not CONTRACT.parse_text(JSON.stringify(malicious)).get("ok", false),
			"unverified focus ID rejected")
	if result.get("ok", false):
		_check(result["work"].is_empty(), "pinned fixture has no work lines; none are invented")
	_check_work()
	_check(not CONTRACT.parse_text("{bad").get("ok", false), "bad JSON rejected")
	_check(not CONTRACT.parse_text("x".repeat(CONTRACT.MAX_BYTES + 1)).get("ok", false),
		"oversize bytes rejected before JSON parsing")
	if failures.is_empty():
		print("PRIME_CONTRACT_PASS")
		quit(0)
	else:
		for reason in failures:
			printerr("PRIME_CONTRACT_FAIL: " + reason)
		quit(1)

## Colony work: orders, receipts, decisions and rig changes from the
## loom-work fixture, projected by collect_once.py --from-dir.
func _check_work() -> void:
	var text := FileAccess.get_file_as_string(WORK_FIXTURE)
	var result: Dictionary = CONTRACT.parse_text(text, "PINNED_SHARED_SNAPSHOT")
	_check(result.get("ok", false), "work fixture admitted: " + String(result.get("reason", "")))
	if not result.get("ok", false):
		return
	_check(result["events"].size() == 13, "work fixture keeps the 13 thought events")
	_check(result["work"].size() == 16, "16 work lines admitted")
	var kinds: Dictionary = {}
	for w in result["work"]:
		kinds[w["kind"]] = int(kinds.get(w["kind"], 0)) + 1
		_check(w["identity"] == "work" and w["model"] == null, "work is never a model summary")
	_check(kinds == {"order": 3, "order-status": 7, "decision": 1, "rig-change": 5},
		"work kinds counted: " + str(kinds))
	for e in result["events"]:
		_check(e["identity"] != "work", "thought events never carry the work identity")
	var receipts: PackedStringArray = []
	for w in result["work"]:
		if w["kind"] == "order-status" and w["status"] == "done":
			receipts.append(w["receipt"])
	_check(receipts == PackedStringArray(["reported", "reported", "linked", "reported"]),
		"done without a link is reported; only an https link makes it linked: " + str(receipts))
	var original: Dictionary = JSON.parse_string(text)
	var bad: Dictionary = original.duplicate(true)
	bad["work"][1]["status"] = "approved-by-root"
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "unknown receipt status rejected")
	bad = original.duplicate(true)
	bad["work"][13]["link"] = "javascript:alert(1)"
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "non-https receipt link rejected")
	bad = original.duplicate(true)
	bad["work"][0]["kind"] = "shell"
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "unknown work kind rejected")
	bad = original.duplicate(true)
	bad["work"][0]["verified"] = true
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "extra field (e.g. verified) rejected")
	bad = original.duplicate(true)
	bad["work"][3]["rig"] = "xanadu"
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "rig change for an unheartbeated rig rejected")
	bad = original.duplicate(true)
	bad["work"][0]["note"] = "x".repeat(281)
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "oversized note rejected")
	bad = original.duplicate(true)
	bad["work"][0]["at"] = "yesterday"
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "unnormalised work time rejected")
	bad = original.duplicate(true)
	bad["work"][0]["rig"] = "i3"
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "only rig changes may name a rig")
	bad = original.duplicate(true)
	for k in CONTRACT.MAX_WORK:
		bad["work"].append(original["work"][0])
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "more than MAX_WORK lines rejected")
	bad = original.duplicate(true)
	bad["work"] = "not a list"
	_check(not CONTRACT.parse_text(JSON.stringify(bad)).get("ok", false), "non-array work rejected")

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
