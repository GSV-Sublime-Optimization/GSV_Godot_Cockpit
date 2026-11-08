extends SceneTree

const CONTRACT = preload("res://tools/prime_mind/FeedContract.gd")
const FIXTURE := "res://tests/fixtures/prime_mind_feed.json"
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
		var sources := result["bodies"]
		_check(sources["i3"]["status"] == "red", "i3 recorded failing state preserved")
		_check(sources["xanadu"]["status"] == "green", "xanadu source status preserved")
		var malicious := JSON.parse_string(text)
		malicious["bodies"]["i3"]["status"] = "I am a root shell!"
		_check(not CONTRACT.parse_text(JSON.stringify(malicious)).get("ok", false),
			"unrecognized health status fails closed")
		malicious = JSON.parse_string(text)
		malicious["events"][0]["reasons"] = ["x" * 400]
		_check(not CONTRACT.parse_text(JSON.stringify(malicious)).get("ok", false),
			"oversized rationale rejected")
		malicious = JSON.parse_string(text)
		malicious["events"][0]["focus"] = "fake-machine"
		_check(not CONTRACT.parse_text(JSON.stringify(malicious)).get("ok", false),
			"unverified focus ID rejected")
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

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
