extends SceneTree

## Slice 7 sync-doors tests: every named sync target renders as a door
## (design §4) — including the four NOT-A-THING verdicts, which are visible
## in the room as DERIVED views, not silently dropped.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/slice7_doors_test.gd
##
## Exit 0 = pass, 1 = fail.
## Also run by tests/godot_smoke_gate.py as the "slice7-doors" case.

const DOORS = preload("res://scripts/holo/SyncDoors.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_all_doors_present()
	_check_omnisynapse_is_sibling_not_source()
	_check_pu_stale_label()
	_check_derived_verdicts_visible()
	_check_ledger_line()
	_finish()


func _facts() -> Dictionary:
	return {
		"omnisynapse_checkout": true,
		"vault_newest_age": "14 min old",
		"gitnexus_note": "process check owed via fleet feed processes block",
		"pu": {
			"total": 222,
			"file_age": "52 d old",
			"stale": true,
			"api_down": true,
			"counts": {"approved": 222, "failed": 0},
		},
	}


func _door(doors: Array, door_id: String) -> Dictionary:
	for door in doors:
		if typeof(door) == TYPE_DICTIONARY and String(door.get("id", "")) == door_id:
			return door
	return {}


func _check_all_doors_present() -> void:
	var doors := DOORS.build_doors(_facts())
	var want := ["omnisynapse", "gitnexus", "vault", "pu-queue", "techniques", "relationships", "cross-references"]
	if doors.size() != want.size():
		_fail("built %d doors, expected %d" % [doors.size(), want.size()])
	for door_id in want:
		if _door(doors, door_id).is_empty():
			_fail("door %s missing" % door_id)


func _check_omnisynapse_is_sibling_not_source() -> void:
	var door := _door(DOORS.build_doors(_facts()), "omnisynapse")
	if String(door.get("state", "")) != "not_connected":
		_fail("omnisynapse door state is %s, expected not_connected" % String(door.get("state", "")))
	if String(door.get("detail", "")).find("NOT a data source") < 0:
		_fail("omnisynapse door does not say it is not a data source")


func _check_pu_stale_label() -> void:
	var door := _door(DOORS.build_doors(_facts()), "pu-queue")
	if String(door.get("state", "")) != "stale":
		_fail("PU door state is %s, expected stale" % String(door.get("state", "")))
	var detail := String(door.get("detail", ""))
	if detail.find("52 d old") < 0 or detail.find(":5002 DOWN") < 0:
		_fail("PU door hides the staleness: %s" % detail)
	var fresh_facts := _facts()
	fresh_facts["pu"] = {"total": 3, "file_age": "10 min old", "stale": false, "api_down": true, "counts": {"approved": 3}}
	var fresh := _door(DOORS.build_doors(fresh_facts), "pu-queue")
	if String(fresh.get("state", "")) != "live":
		_fail("fresh PU door state is %s, expected live" % String(fresh.get("state", "")))


func _check_derived_verdicts_visible() -> void:
	var doors := DOORS.build_doors(_facts())
	for door_id in ["techniques", "relationships", "cross-references"]:
		var door := _door(doors, door_id)
		if String(door.get("state", "")) != "derived":
			_fail("%s door state is %s, expected derived" % [door_id, String(door.get("state", ""))])
		if String(door.get("detail", "")).find("DERIVED") < 0:
			_fail("%s door does not carry the DERIVED label" % door_id)
	if String(_door(doors, "techniques").get("detail", "")).find("no techniques registry exists") < 0:
		_fail("techniques door does not state the NOT-A-THING verdict")


func _check_ledger_line() -> void:
	var line := DOORS.ledger_line(DOORS.build_doors(_facts()))
	if line.find("omnisynapse not_connected") < 0:
		_fail("ledger line misses omnisynapse: %s" % line)
	if line.find("pu-queue stale") < 0:
		_fail("ledger line misses pu-queue stale: %s" % line)
	if line.find("techniques derived") < 0:
		_fail("ledger line misses techniques derived: %s" % line)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[slice7-test] PASS")
		quit(0)
		return
	for message in _failures:
		printerr("[slice7-test] FAIL: %s" % message)
	print("[slice7-test] FAILED (%d)" % _failures.size())
	quit(1)
