extends SceneTree

const PROJECTION = preload("res://scripts/workstation/WorkbenchSpatialProjection.gd")
var errors: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var empty: Dictionary = PROJECTION.project({})
	_assert(empty["nodes"].size() == 4, "unknown fleet still has four discoverable bodies")
	_assert(empty["edges"].size() == 0, "never invent relations")
	for rig in empty["nodes"]:
		_assert(rig["kind"] == "rig" and rig["status"] == "unknown", "unknown not offline or live")
	var fixture := {
		"body_feed_state": "observed",
		"bodies": [{"body_id": "kilo-core-msi", "state": "reported_fresh"}],
		"project_feed_state": "observed",
		"projects": [
			{"name": "Demo", "path": "C:/dev/active/demo", "branch": "main"},
			{"name": "Other", "path": "C:/dev/active/other", "branch": "feature"}
		],
		"mission_feed_state": "observed",
		"missions": [
			{"id": "msn_012345abcdef", "title": "Improve actual build", "status": "running",
				"risk": "R2", "repo": "C:/dev/active/demo", "updated_at": "2026-11-08T07:00:00Z"},
			{"id": "msn_deadbeefcafe", "title": "Unrelated", "status": "failed", "risk": "R0"}
		],
		"service_feed_state": "observed",
		"services": [{"id": "studio", "name": "Studio", "status": "up"}]
	}
	var result: Dictionary = PROJECTION.project(fixture)
	_assert(result["nodes"].size() == 9, "4 rigs + 2 real projects + 2 missions + 1 service")
	_assert(result["edges"].size() == 1, "only mission's proven repo produces a link")
	_assert(result["edges"][0]["from"] == "project:C:/dev/active/demo", "link points to actual repo")
	var lookup := {}
	for node in result["nodes"]:
		lookup[node["key"]] = node
		_assert(node.has("source") and node.has("position"), "every mesh has provenance and 3D position")
	_assert(lookup["rig:kilo-core-msi"]["status"] == "reported_fresh", "fresh rig stays fresh")
	_assert(lookup["rig:desktop-i3anuvp"]["status"] == "unknown", "missing body not fabricated")
	_assert(lookup["mission:msn_deadbeefcafe"]["status"] == "failed", "mission failure not painted healthy")
	_assert(lookup["project:C:/dev/active/demo"]["observed"], "explicit project observed")
	_assert(PROJECTION.color_for("failed") != PROJECTION.color_for("succeeded"), "truth colours differ")
	var again := PROJECTION.project(fixture)
	_assert(again["nodes"][4]["position"] == result["nodes"][4]["position"], "stable 3D layout")
	fixture["project_feed_state"] = "stale"
	var stale: Dictionary = PROJECTION.project(fixture)
	_assert(stale["edges"].is_empty(), "stale project cannot authorize a verified link")
	_assert(stale["nodes"].size() == 7, "stale projects disappear, not remain live")
	fixture["project_feed_state"] = "observed"
	fixture["projects"] = [{"name": "Sneaky", "path": "../wrong/place", "branch": "main"}]
	var unsafe: Dictionary = PROJECTION.project(fixture)
	_assert(unsafe["nodes"].size() == 7, "relative project refuses a working surface")
	fixture["mission_feed_state"] = "unavailable"
	var failed_source: Dictionary = PROJECTION.project(fixture)
	_assert(failed_source["nodes"].size() == 5, "unavailable mission index cannot fake current missions")
	if errors.is_empty():
		print("WORKSTATION_SPATIAL_PASS")
		quit(0)
	else:
		for e in errors:
			printerr("WORKSTATION_SPATIAL_FAIL: " + e)
		quit(1)

func _assert(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
