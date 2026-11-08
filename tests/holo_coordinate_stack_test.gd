extends SceneTree

## Hologram tests for the cockpit bake-off entry (Slice 4), following the #8
## pattern: negative controls on fake data + an opt-in live canary that
## accepts live OR honest unavailable, never fabricated live.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/holo_coordinate_stack_test.gd
##
## Exit 0 = pass, 1 = fail. The live canary runs only with GSV_STUDIO_LIVE=1.
## Also run by tests/godot_smoke_gate.py as the "holo" case.

const HOLO_ROOM_SCENE := "res://scenes/HoloRoom.tscn"
# Slice 7: FleetTelemetryProjection has no class_name — the codebase pattern
# is a preload const (FleetTelemetryReader.gd). Without this the test fails
# to parse at the first FleetTelemetryProjection.parse_telemetry call.
const FleetTelemetryProjection = preload("res://scripts/holo/FleetTelemetryProjection.gd")
const FleetTelemetryReader = preload("res://scripts/holo/FleetTelemetryReader.gd")
const SURFACE_SHADER := "res://shaders/holo_surface.gdshader"

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_perspective_f()
	_check_view_and_clip()
	_check_ray_and_hit_layer()
	_check_pull()
	_check_depth_sort()
	_check_parallax_and_gaze()
	_check_billboard()
	_check_density()
	_check_registry()
	_check_fleet_projection()
	_check_fleet_reader()
	await _check_holo_layer_pull()
	await _check_holo_room_scene()
	if OS.get_environment("GSV_STUDIO_LIVE") == "1":
		await _check_live_canary()
	_finish()


func _check_perspective_f() -> void:
	# fov 90 -> tan(45) = 1 -> f = 1. fov 55 -> 1/tan(27.5) ~= 1.921.
	if not is_equal_approx(HoloCoordinateStack.perspective_f(90.0), 1.0):
		_fail("perspective_f(90) != 1.0")
	var f55 := HoloCoordinateStack.perspective_f(55.0)
	if absf(f55 - 1.921) > 0.005:
		_fail("perspective_f(55) = %f, expected ~1.921" % f55)


func _check_view_and_clip() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 5.0)
	camera.fov = 90.0
	camera.near = 0.1
	camera.far = 100.0
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await process_frame

	# World origin is 5 units in front of the camera: view (0, 0, -5).
	var view := HoloCoordinateStack.view_space_point(camera, Vector3.ZERO)
	if not view.is_equal_approx(Vector3(0.0, 0.0, -5.0)):
		_fail("view_space_point(origin) = %s, expected (0, 0, -5)" % str(view))

	# Clip space: point (0,0,-10), fov 90, aspect 16/9, near 0.1, far 100.
	# w = 10; NDC z ~= 0.982.
	var clip := HoloCoordinateStack.clip_space_point(camera, Vector3(0.0, 0.0, -10.0), 16.0 / 9.0)
	if not is_equal_approx(clip.w, 10.0):
		_fail("clip w = %f, expected 10.0" % clip.w)
	if absf(clip.z / clip.w - 0.982) > 0.01:
		_fail("clip NDC z = %f, expected ~0.982" % (clip.z / clip.w))

	# Forward projection: the origin projects to the screen centre.
	var centre := root.size * 0.5
	var screen := HoloCoordinateStack.screen_point(camera, Vector3.ZERO)
	if screen.distance_to(centre) > 2.0:
		_fail("screen_point(origin) = %s, expected near centre %s" % [str(screen), str(centre)])

	camera.queue_free()


func _check_ray_and_hit_layer() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 5.0)
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await process_frame

	# Ray through the screen centre points straight down -Z.
	var centre := root.size * 0.5
	var ray := HoloCoordinateStack.ray_from_screen(camera, centre)
	var dir: Vector3 = ray["direction"]
	if dir.z > -0.99:
		_fail("centre ray direction = %s, expected ~ (0, 0, -1)" % str(dir))

	# Layer at the origin, billboarded at the camera.
	var layer := Node3D.new()
	root.add_child(layer)
	layer.global_transform = Transform3D(
		HoloCoordinateStack.billboard_basis(layer.global_position, camera.global_position),
		Vector3.ZERO
	)
	var half := Vector2(1.2, 0.75)
	var hit_centre := HoloCoordinateStack.hit_layer(camera, centre, layer, half)
	if not bool(hit_centre.get("hit", false)):
		_fail("centre ray missed a layer dead ahead")
	else:
		var local: Vector2 = hit_centre["local"]
		if local.length() > 0.05:
			_fail("centre hit local = %s, expected ~(0, 0)" % str(local))

	# Top-left corner ray hits the plane far outside the rect: no hit.
	var hit_corner := HoloCoordinateStack.hit_layer(camera, Vector2.ZERO, layer, half)
	if bool(hit_corner.get("hit", false)):
		_fail("corner ray hit a 2.4x1.5 layer it should have missed")

	# Layer behind the camera: the ray runs away from the plane -> no hit.
	layer.global_position = Vector3(0.0, 0.0, 10.0)
	var hit_behind := HoloCoordinateStack.hit_layer(camera, centre, layer, half)
	if bool(hit_behind.get("hit", false)):
		_fail("ray hit a layer behind the camera")

	# Negative control on the primitive itself: a ray parallel to a plane
	# never intersects it.
	var plane := Plane(Vector3(0.0, 0.0, 1.0), 0.0)
	var parallel: Variant = plane.intersects_ray(Vector3(0.0, 0.0, 5.0), Vector3(1.0, 0.0, 0.0))
	if parallel != null:
		_fail("parallel ray intersected its plane")

	layer.queue_free()
	camera.queue_free()


func _check_pull() -> void:
	# d(lambda) = d_base + lambda * delta_d; s(lambda) = s_base * (1 + lambda * kappa).
	if not is_equal_approx(HoloCoordinateStack.pull_distance(2.0, 0.0, 2.5), 2.0):
		_fail("pull_distance at lambda 0 moved the plane")
	if not is_equal_approx(HoloCoordinateStack.pull_distance(2.0, 1.0, 2.5), 4.5):
		_fail("pull_distance at lambda 1 != 4.5")
	if not is_equal_approx(HoloCoordinateStack.pull_distance(2.0, 2.0, 2.5), 4.5):
		_fail("pull_distance did not clamp lambda above 1")
	if not is_equal_approx(HoloCoordinateStack.pull_distance(2.0, -1.0, 2.5), 2.0):
		_fail("pull_distance did not clamp lambda below 0")
	if not is_equal_approx(HoloCoordinateStack.pull_scale(1.0, 1.0, 0.6), 1.6):
		_fail("pull_scale at lambda 1 != 1.6")
	if not is_equal_approx(HoloCoordinateStack.pull_scale(1.0, 0.0, 0.6), 1.0):
		_fail("pull_scale at lambda 0 != 1.0")


func _check_depth_sort() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 5.0)
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await process_frame

	var near_node := Node3D.new()
	near_node.position = Vector3(0.0, 0.0, -2.0)
	var mid_node := Node3D.new()
	mid_node.position = Vector3(0.0, 0.0, -5.0)
	var far_node := Node3D.new()
	far_node.position = Vector3(0.0, 0.0, -8.0)
	root.add_child(near_node)
	root.add_child(mid_node)
	root.add_child(far_node)

	# Closer (less negative view z) first.
	var entries: Array = [
		{"node": far_node, "render_priority": 0, "index": 2},
		{"node": near_node, "render_priority": 0, "index": 0},
		{"node": mid_node, "render_priority": 0, "index": 1},
	]
	var ordered: Array = HoloCoordinateStack.sort_layers_by_depth(camera, entries)
	if ordered[0]["node"] != near_node or ordered[1]["node"] != mid_node or ordered[2]["node"] != far_node:
		_fail("depth sort did not order closer-first")

	# Equal depths: render_priority breaks the tie, then insertion index.
	var twin_a := Node3D.new()
	twin_a.position = Vector3(0.0, 0.0, -5.0)
	var twin_b := Node3D.new()
	twin_b.position = Vector3(0.0, 0.0, -5.0)
	root.add_child(twin_a)
	root.add_child(twin_b)
	var ties: Array = [
		{"node": twin_b, "render_priority": 20, "index": 1},
		{"node": twin_a, "render_priority": 10, "index": 0},
	]
	var tied: Array = HoloCoordinateStack.sort_layers_by_depth(camera, ties)
	if tied[0]["node"] != twin_a:
		_fail("depth sort did not prefer lower render_priority on equal depth")

	near_node.queue_free()
	mid_node.queue_free()
	far_node.queue_free()
	twin_a.queue_free()
	twin_b.queue_free()
	camera.queue_free()


func _check_parallax_and_gaze() -> void:
	# offset = k * (z - z_ref) * (p_cam - p_ref). Zero at the reference depth.
	var off := HoloCoordinateStack.parallax_offset(1.0, 2.0, 0.0, Vector3(1.0, 0.0, 0.0), Vector3.ZERO)
	if not off.is_equal_approx(Vector3(2.0, 0.0, 0.0)):
		_fail("parallax_offset = %s, expected (2, 0, 0)" % str(off))
	var zero := HoloCoordinateStack.parallax_offset(1.0, 0.0, 0.0, Vector3(1.0, 0.0, 0.0), Vector3.ZERO)
	if not zero.is_equal_approx(Vector3.ZERO):
		_fail("parallax_offset at the reference depth was not zero")
	var still := HoloCoordinateStack.parallax_offset(0.0, 5.0, 0.0, Vector3(1.0, 0.0, 0.0), Vector3.ZERO)
	if not still.is_equal_approx(Vector3.ZERO):
		_fail("parallax_offset with k = 0 was not zero")

	# Gaze: g-hat = normalize(p_cam - p_holo).
	var gaze := HoloCoordinateStack.gaze_direction(Vector3(0.0, 3.0, 4.0), Vector3.ZERO)
	if not gaze.is_equal_approx(Vector3(0.0, 0.6, 0.8)):
		_fail("gaze_direction = %s, expected (0, 0.6, 0.8)" % str(gaze))


func _check_billboard() -> void:
	# A card at the origin facing a camera on +Z ends up +Z toward the camera.
	var basis := HoloCoordinateStack.billboard_basis(Vector3.ZERO, Vector3(0.0, 0.0, 5.0))
	if basis.z.dot(Vector3(0.0, 0.0, 1.0)) < 0.99:
		_fail("billboard basis +Z does not face the camera")
	# Degenerate: camera on the layer -> IDENTITY, never a NaN basis.
	var degenerate := HoloCoordinateStack.billboard_basis(Vector3.ZERO, Vector3.ZERO)
	if degenerate != Basis.IDENTITY:
		_fail("billboard at zero distance was not IDENTITY")


func _check_density() -> void:
	# Empty model, real mode: all-zero field, no live senses, honest label.
	var empty := HoloDensity.build_grid({}, false)
	if bool(empty.get("simulated", true)):
		_fail("real density build reported simulated")
	if int(empty.get("live_senses", -1)) != 0:
		_fail("empty model reported live senses")
	if String(empty.get("state", "")) != "empty":
		_fail("empty model state was not 'empty'")
	var empty_grid: PackedByteArray = empty["grid"]
	if HoloDensity.density_at(empty_grid, 4, 8, 8) != 0:
		_fail("empty model had nonzero density at the Studio blob")
	if HoloDensity.density_at(empty_grid, 0, 0, 0) != 0:
		_fail("empty model had nonzero density at the origin")
	if HoloDensity.density_at(empty_grid, -1, 0, 0) != -1:
		_fail("density_at did not return -1 out of bounds")
	if HoloDensity.density_at(empty_grid, 16, 0, 0) != -1:
		_fail("density_at did not return -1 past the edge")

	# Live model: Studio + gateway live, constellation unavailable, 4 fleet
	# bodies fresh. Blobs present exactly where the senses are live.
	var model := {
		"sensor": {"state": "live", "mission_counts": {"awaiting": 0, "running": 0, "queued": 0}},
		"gateway": {"state": "live"},
		"constellation": {"state": "unavailable", "error": "constellation_scan_unavailable"},
		"fleet_bodies": [
			{"state": "reported_fresh"}, {"state": "reported_fresh"},
			{"state": "reported_fresh"}, {"state": "reported_fresh"},
		],
	}
	var live := HoloDensity.build_grid(model, false)
	if int(live.get("live_senses", -1)) != 3:
		_fail("live model reported %d live senses, expected 3" % int(live.get("live_senses", -1)))
	var live_grid: PackedByteArray = live["grid"]
	if HoloDensity.density_at(live_grid, 4, 8, 8) <= 0:
		_fail("live Studio sense left no density at its blob")
	if HoloDensity.density_at(live_grid, 11, 8, 8) <= 0:
		_fail("live gateway sense left no density at its blob")
	if HoloDensity.density_at(live_grid, 8, 4, 8) != 0:
		_fail("unavailable constellation left density at its blob")
	if HoloDensity.density_at(live_grid, 8, 12, 8) <= 0:
		_fail("four fresh fleet bodies left no density at their blob")

	# Unknown states contribute nothing.
	var unknown := HoloDensity.build_grid({"sensor": {"state": "unknown"}}, false)
	if int(unknown.get("live_senses", -1)) != 0:
		_fail("unknown sensor counted as a live sense")

	# Simulated mode: fixed demo pattern, labelled SIMULATED in full.
	var sim := HoloDensity.build_grid({}, true)
	if not bool(sim.get("simulated", false)):
		_fail("simulated density build did not flag simulated")
	if not String(sim.get("label", "")).contains("SIMULATED"):
		_fail("simulated density label does not say SIMULATED")
	var sim_grid: PackedByteArray = sim["grid"]
	if HoloDensity.density_at(sim_grid, 5, 8, 8) <= 0:
		_fail("simulated pattern left no density at its first blob")


func _check_registry() -> void:
	var layers: Array = HoloLayerRegistry.layer_defs()
	if layers.size() < 10:
		_fail("registry has %d layers, expected >= 10" % layers.size())
	var seen: Dictionary = {}
	var terminals := 0
	for def in layers:
		var layer_id := String(def.get("id", ""))
		if layer_id.is_empty():
			_fail("registry layer without an id")
		if seen.has(layer_id):
			_fail("duplicate registry layer id: %s" % layer_id)
		seen[layer_id] = true
		if not HoloLayerRegistry.is_honest_state(String(def.get("state", ""))):
			_fail("registry layer %s has a dishonest state" % layer_id)
		if String(def.get("source", "")).is_empty():
			_fail("registry layer %s has no source" % layer_id)
		if String(def.get("kind", "")) == "terminal":
			terminals += 1
	if terminals != 4:
		_fail("registry has %d terminal layers, expected 4" % terminals)
	if HoloLayerRegistry.layer_def("studio-health").is_empty():
		_fail("registry lookup missed studio-health")
	if not HoloLayerRegistry.layer_def("no-such-layer").is_empty():
		_fail("registry lookup invented a layer")

	var seats: Array = HoloLayerRegistry.seat_defs()
	if seats.size() != 16:
		_fail("registry has %d seats, expected 16" % seats.size())
	for seat in seats:
		if not HoloLayerRegistry.is_honest_state(String(seat.get("state", ""))):
			_fail("seat %s has a dishonest state" % String(seat.get("id", "?")))


func _check_fleet_projection() -> void:
	# A valid snapshot parses: states, RAM, services, tasks all admitted.
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var good := {
		"schema": "kilocore.fleet-telemetry.v1",
		"generated_at": "2026-11-08T07:11:24Z",
		"generated_unix_ms": now_ms,
		"probe_host": "MSI-KATANA",
		"rigs": {
			"msi": {
				"state": "live", "ram_free_mb": 4527, "ram_total_mb": 32472,
				"ram_free_pct": 13.9, "cpu_load_pct": 2,
				"services": {"studio": "up", "gateway": "up", "devmentor": "unknown"},
				"tasks": {"KiloCore-Public-Gateway": "Running"},
				"seats": "", "note": "MSI-KATANA, probed locally",
			},
			"i3": {
				"state": "live", "ram_free_mb": 14986, "ram_total_mb": 24524,
				"services": {}, "tasks": {},
				"seats": "claude,claude,claude,claude,ollama",
				"note": "SSH session works",
			},
			"l9": {"state": "live", "ram_free_mb": 5993, "ram_total_mb": 16329},
			"xanadu": {"state": "live", "services": {"icecast": "up"}},
		},
	}
	var parsed := FleetTelemetryProjection.parse_telemetry(JSON.stringify(good))
	if not bool(parsed.get("ok", false)):
		_fail("valid fleet snapshot rejected: %s" % str(parsed.get("reason", "")))
		return
	var telemetry: Dictionary = parsed["telemetry"]
	var rigs: Dictionary = telemetry["rigs"]
	var msi: Dictionary = rigs["msi"]
	if String(msi.get("state", "")) != "live":
		_fail("MSI rig state was not 'live'")
	if int(msi.get("ram_free_mb", -1)) != 4527:
		_fail("MSI ram_free_mb not admitted")
	var msi_services: Dictionary = msi["services"]
	if String(msi_services.get("devmentor", "")) != "unknown":
		_fail("MSI devmentor service state not admitted as unknown")
	var msi_tasks: Dictionary = msi["tasks"]
	if String(msi_tasks.get("KiloCore-Public-Gateway", "")) != "Running":
		_fail("MSI task state not admitted")
	var i3: Dictionary = rigs["i3"]
	if String(i3.get("seats", "")) != "claude,claude,claude,claude,ollama":
		_fail("i3 seat list not admitted")

	# Negative controls: wrong schema, malformed JSON, oversized body, bad
	# timestamp, missing rigs block.
	var wrong_schema := good.duplicate(true)
	wrong_schema["schema"] = "kilocore.fleet-telemetry.v99"
	var rejected := FleetTelemetryProjection.parse_telemetry(JSON.stringify(wrong_schema))
	if bool(rejected.get("ok", true)) or String(rejected.get("reason", "")) != "unknown_telemetry_schema":
		_fail("wrong-schema snapshot was not rejected as unknown_telemetry_schema")
	var malformed := FleetTelemetryProjection.parse_telemetry("{not json")
	if bool(malformed.get("ok", true)) or String(malformed.get("reason", "")) != "malformed_json":
		_fail("malformed snapshot was not rejected as malformed_json")
	var big := "x".repeat(70000)
	var oversized := FleetTelemetryProjection.parse_telemetry(big)
	if bool(oversized.get("ok", true)) or String(oversized.get("reason", "")) != "telemetry_response_too_large":
		_fail("oversized snapshot was not rejected as telemetry_response_too_large")
	var bad_time := good.duplicate(true)
	bad_time["generated_unix_ms"] = "soon"
	var bad_time_parsed := FleetTelemetryProjection.parse_telemetry(JSON.stringify(bad_time))
	if bool(bad_time_parsed.get("ok", true)) or String(bad_time_parsed.get("reason", "")) != "invalid_generated_at":
		_fail("bad generated_unix_ms was not rejected as invalid_generated_at")
	var no_rigs := good.duplicate(true)
	no_rigs.erase("rigs")
	var no_rigs_parsed := FleetTelemetryProjection.parse_telemetry(JSON.stringify(no_rigs))
	if bool(no_rigs_parsed.get("ok", true)) or String(no_rigs_parsed.get("reason", "")) != "missing_rigs":
		_fail("snapshot without rigs was not rejected as missing_rigs")

	# Lenient on values, strict on shape: a weird service state becomes
	# "unknown", never fatal; a missing rig reads as unknown, never invented.
	var weird := good.duplicate(true)
	var weird_rigs: Dictionary = weird["rigs"]
	var weird_msi: Dictionary = weird_rigs["msi"]
	var weird_services: Dictionary = weird_msi["services"]
	weird_services["studio"] = "maybe"
	var weird_parsed := FleetTelemetryProjection.parse_telemetry(JSON.stringify(weird))
	if not bool(weird_parsed.get("ok", false)):
		_fail("weird service value made the whole snapshot fail")
	else:
		# GDScript locals are function-scoped: these cannot reuse the
		# weird_rigs / weird_services names declared above (Slice 7 fix).
		var weird_rigs_parsed: Dictionary = (weird_parsed["telemetry"] as Dictionary)["rigs"]
		var weird_services_parsed: Dictionary = (weird_rigs_parsed["msi"] as Dictionary)["services"]
		if String(weird_services_parsed.get("studio", "")) != "unknown":
			_fail("weird service value was not mapped to unknown")
	var sparse := good.duplicate(true)
	(sparse["rigs"] as Dictionary).erase("l9")
	var sparse_parsed := FleetTelemetryProjection.parse_telemetry(JSON.stringify(sparse))
	if not bool(sparse_parsed.get("ok", false)):
		_fail("snapshot missing one rig was rejected")
	else:
		var sparse_rigs: Dictionary = (sparse_parsed["telemetry"] as Dictionary)["rigs"]
		if String((sparse_rigs["l9"] as Dictionary).get("state", "")) != "unknown":
			_fail("missing rig was not reported unknown")

	# Over-long notes are truncated, not fatal.
	var long_note := good.duplicate(true)
	var long_rigs: Dictionary = long_note["rigs"]
	var long_msi: Dictionary = long_rigs["msi"]
	long_msi["note"] = "n".repeat(500)
	var long_parsed := FleetTelemetryProjection.parse_telemetry(JSON.stringify(long_note))
	if not bool(long_parsed.get("ok", false)):
		_fail("over-long note made the snapshot fail")
	else:
		# Same function-scope rule as weird_rigs above (Slice 7 fix).
		var long_rigs_parsed: Dictionary = (long_parsed["telemetry"] as Dictionary)["rigs"]
		if String((long_rigs_parsed["msi"] as Dictionary).get("note", "")).length() > 200:
			_fail("over-long note was not truncated to 200 chars")


func _check_fleet_reader() -> void:
	# The reader is a bounded file read: fresh -> live, old -> stale,
	# malformed -> unavailable, missing -> unavailable. No shell, no network.
	var path := "user://fleet-telemetry-test.json"
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var snapshot := {
		"schema": "kilocore.fleet-telemetry.v1",
		"generated_at": "2026-11-08T07:11:24Z",
		"generated_unix_ms": now_ms,
		"probe_host": "MSI-KATANA",
		"rigs": {"msi": {"state": "live", "ram_free_mb": 4527, "ram_total_mb": 32472}},
	}
	var reader := FleetTelemetryReader.new()
	reader.snapshot_path = path
	root.add_child(reader)

	_write_text_file(path, JSON.stringify(snapshot))
	reader.read_now()
	var fresh := reader.current_telemetry()
	if String(fresh.get("state", "")) != "live":
		_fail("fresh snapshot did not read as live (state=%s error=%s)" % [str(fresh.get("state", "")), str(fresh.get("error", ""))])
	if int(fresh.get("age_ms", -1)) < 0 or int(fresh.get("age_ms", 999999)) > 5000:
		_fail("fresh snapshot age_ms out of range: %s" % str(fresh.get("age_ms", "")))

	snapshot["generated_unix_ms"] = now_ms - 600000
	_write_text_file(path, JSON.stringify(snapshot))
	reader.read_now()
	var stale := reader.current_telemetry()
	if String(stale.get("state", "")) != "stale":
		_fail("10-minute-old snapshot did not read as stale (state=%s)" % str(stale.get("state", "")))

	_write_text_file(path, "{bad json")
	reader.read_now()
	var broken := reader.current_telemetry()
	if String(broken.get("state", "")) != "unavailable":
		_fail("malformed snapshot did not read as unavailable (state=%s)" % str(broken.get("state", "")))

	DirAccess.remove_absolute(path)
	reader.read_now()
	var missing := reader.current_telemetry()
	if String(missing.get("state", "")) != "unavailable":
		_fail("missing snapshot did not read as unavailable (state=%s)" % str(missing.get("state", "")))

	reader.queue_free()


func _write_text_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("could not open %s for writing" % path)
		return
	f.store_string(text)
	f.close()


func _check_holo_layer_pull() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 5.0)
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await process_frame

	var shader := load(SURFACE_SHADER) as Shader
	if shader == null:
		_fail("could not load %s" % SURFACE_SHADER)
		camera.queue_free()
		return
	var layer := HoloLayer.new()
	root.add_child(layer)
	layer.setup(HoloLayerRegistry.layer_def("studio-health"), shader)
	if layer.pull_target != 0.0:
		_fail("fresh layer did not start unpulled")
	layer.toggle_pull()
	if layer.pull_target != 1.0:
		_fail("toggle_pull did not arm the pull")
	# One long frame drives pull to its target: the plane moves toward the
	# camera along camera-forward by PULL_DISTANCE and scales up.
	layer.update_frame(1.0, camera)
	if not is_equal_approx(layer.pull, 1.0):
		_fail("layer pull did not reach 1.0 after a full frame")
	if layer.position.z > -2.0:
		_fail("pulled layer did not move toward the camera (z = %f)" % layer.position.z)
	if layer.scale.x < 1.5:
		_fail("pulled layer did not scale up (scale = %f)" % layer.scale.x)
	layer.toggle_pull()
	if layer.pull_target != 0.0:
		_fail("second toggle_pull did not release the pull")

	layer.queue_free()
	camera.queue_free()


func _check_holo_room_scene() -> void:
	var scene := load(HOLO_ROOM_SCENE) as PackedScene
	if scene == null:
		_fail("could not load %s" % HOLO_ROOM_SCENE)
		return
	var room := scene.instantiate() as HoloRoom
	if room == null:
		_fail("HoloRoom scene did not instantiate as HoloRoom")
		return
	root.add_child(room)
	# Let _ready build the volume and the deferred paint timer fire, so the
	# room's own probe starts before the room is freed (no resume-after-free).
	await process_frame
	await process_frame
	await process_frame
	if room.camera_node() == null:
		_fail("HoloRoom has no camera")
	if room.layer_count() != 14:
		_fail("HoloRoom built %d layers, expected 14" % room.layer_count())
	if room.seat_count() != 16:
		_fail("HoloRoom built %d seats, expected 16" % room.seat_count())
	if room.get_session() == null:
		_fail("HoloRoom did not mount the Mind (EntitySession)")
	if room.get_node_or_null("FleetTelemetryReader") == null:
		_fail("HoloRoom did not mount the fleet snapshot reader")
	var density: Dictionary = room.density_state()
	if not String(density.get("label", "")).contains("DENSITY"):
		_fail("HoloRoom density state has no label: %s" % str(density.get("label", "")))
	room.queue_free()
	await process_frame


func _check_live_canary() -> void:
	# Opt-in only (GSV_STUDIO_LIVE=1). Accepts live OR honest unavailable —
	# never fabricated live. The Mind's own bridges do the sensing; this only
	# reads the mounted session's self-model.
	var scene := load(HOLO_ROOM_SCENE) as PackedScene
	var room := scene.instantiate() as HoloRoom
	root.add_child(room)
	var state := "unknown"
	for _i in 80:
		await create_timer(0.1).timeout
		var session := room.get_session()
		if session == null:
			continue
		var model: Dictionary = session.self_model()
		var sensor: Dictionary = model.get("sensor", {})
		state = String(sensor.get("state", "unknown"))
		if state == "live" or state == "stale" or state == "unavailable":
			break
	print("[holo-test] live canary: Studio sensor state = %s" % state)
	if state != "live" and state != "stale" and state != "unavailable":
		_fail("live canary: Studio sensor stayed '%s' after 8 s" % state)
	room.queue_free()
	await process_frame


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[holo-test] PASS")
		quit(0)
		return
	for message in _failures:
		printerr("[holo-test] FAIL: %s" % message)
	print("[holo-test] FAILED (%d)" % _failures.size())
	quit(1)
