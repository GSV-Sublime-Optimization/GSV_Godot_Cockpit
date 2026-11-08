extends SceneTree

## Portability: the fleet telemetry snapshot path is the MSI's C:/GSV path by
## default, and GSV_FLEET_TELEMETRY_PATH moves it on any other rig or OS, for
## both readers that open it.

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var prior := OS.get_environment("GSV_FLEET_TELEMETRY_PATH")
	OS.set_environment("GSV_FLEET_TELEMETRY_PATH", "")
	var fleet: Node = load("res://scripts/holo/FleetTelemetryReader.gd").new()
	var atlas: Node = load("res://scripts/holo/CapabilityAtlasReader.gd").new()
	if fleet.snapshot_path != "C:/GSV/state/fleet-telemetry.json":
		_fail("default fleet path changed: %s" % fleet.snapshot_path)
	if atlas.telemetry_path != "C:/GSV/state/fleet-telemetry.json":
		_fail("default atlas telemetry path changed: %s" % atlas.telemetry_path)
	fleet.free()
	atlas.free()

	var path := ProjectSettings.globalize_path("user://fleet-telemetry-env-test.json")
	OS.set_environment("GSV_FLEET_TELEMETRY_PATH", path)
	fleet = load("res://scripts/holo/FleetTelemetryReader.gd").new()
	atlas = load("res://scripts/holo/CapabilityAtlasReader.gd").new()
	if fleet.snapshot_path != path:
		_fail("env override not used by FleetTelemetryReader: %s" % fleet.snapshot_path)
	if atlas.telemetry_path != path:
		_fail("env override not used by CapabilityAtlasReader: %s" % atlas.telemetry_path)
	fleet.free()
	atlas.free()
	OS.set_environment("GSV_FLEET_TELEMETRY_PATH", prior)

	if failures.is_empty():
		print("[fleet-env-test] PASS: default path kept; GSV_FLEET_TELEMETRY_PATH honoured by both readers")
		quit(0)
	else:
		for f in failures:
			printerr("[fleet-env-test] FAIL: " + f)
		quit(1)

func _fail(msg: String) -> void:
	failures.append(msg)
