class_name HoloDensity
extends RefCounted

## The volumetric density field rho(p) for the companion's thought-volume.
##
## HONESTY RULE (Keath's brief): rho is driven by the Mind's REAL senses
## (the three sensors from PRs #8–#11: Studio health, gateway health,
## constellation, plus fleet bodies) or by explicitly-marked simulated data.
## Never present a fabricated density field as live agent state. Where a real
## density source does not exist yet, the layer is labelled simulated/planned.
##
## The field is a 16^3 grid. Axes are DATA axes, not decoration:
##   x — sense index (studio | gateway | constellation | fleet bodies)
##   y — magnitude (how strong the sense is reporting)
##   z — age / time (the observation's freshness)
## Each live sense contributes one Gaussian blob whose amplitude is its
## liveness (live 1.0, stale 0.5, unavailable/unknown 0.0). The Studio blob
## also scales with mission activity (awaiting + running + queued, capped).
## No live senses => an all-zero field and the state "empty": the volume
## renders nothing and says so, rather than inventing thought.
##
## Simulated mode is a local display toggle only (default OFF). When on, the
## field is a fixed demo pattern and the label says SIMULATED in full — the
## volume never claims demo density is agent state.

const SIZE := 16
const SIGMA := 2.5

## Pure: Mind self-model + simulated flag -> density build. No scene tree,
## no I/O, no rendering-server use, so tests can drive it directly.
static func build_grid(model: Dictionary, simulated: bool) -> Dictionary:
	var grid := PackedByteArray()
	grid.resize(SIZE * SIZE * SIZE)
	grid.fill(0)
	if simulated:
		_add_blob(grid, Vector3(5, 8, 8), 1.0)
		_add_blob(grid, Vector3(11, 8, 8), 0.7)
		_add_blob(grid, Vector3(8, 8, 4), 0.5)
		return {
			"grid": grid,
			"size": Vector3i(SIZE, SIZE, SIZE),
			"simulated": true,
			"live_senses": 0,
			"state": "simulated",
			"label": "SIMULATED DENSITY — demo pattern, NOT live agent state",
		}

	var live := 0
	var sensor: Dictionary = model.get("sensor", {})
	var gateway: Dictionary = model.get("gateway", {})
	var constellation: Dictionary = model.get("constellation", {})
	var bodies: Array = model.get("fleet_bodies", [])

	var studio_amp := _liveness(sensor)
	if studio_amp > 0.0:
		live += 1
		var counts: Dictionary = sensor.get("mission_counts", {})
		var activity := clampf(float(
			int(counts.get("awaiting", 0))
			+ int(counts.get("running", 0))
			+ int(counts.get("queued", 0))
		) / 10.0, 0.0, 1.0)
		_add_blob(grid, Vector3(4, 8, 8), studio_amp * (0.4 + 0.6 * activity))

	var gateway_amp := _liveness(gateway)
	if gateway_amp > 0.0:
		live += 1
		_add_blob(grid, Vector3(11, 8, 8), gateway_amp)

	var constellation_amp := _liveness(constellation)
	if constellation_amp > 0.0:
		live += 1
		_add_blob(grid, Vector3(8, 4, 8), constellation_amp)

	var reported := 0
	for entry in bodies:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("state", "")) == "reported_fresh":
			reported += 1
	if reported > 0:
		live += 1
		_add_blob(grid, Vector3(8, 12, 8), clampf(float(reported) / 4.0, 0.0, 1.0))

	var label := ""
	var state := "empty"
	if live > 0:
		state = "live"
		label = "LIVE DENSITY — rho from %d live sense(s)" % live
	else:
		label = "NO LIVE DENSITY — senses unknown/unavailable"
	return {
		"grid": grid,
		"size": Vector3i(SIZE, SIZE, SIZE),
		"simulated": false,
		"live_senses": live,
		"state": state,
		"label": label,
	}


## Liveness amplitude: live 1.0, stale 0.5, anything else 0.0.
static func _liveness(observation: Dictionary) -> float:
	match String(observation.get("state", "unknown")):
		"live":
			return 1.0
		"stale":
			return 0.5
	return 0.0


static func _add_blob(grid: PackedByteArray, center: Vector3, amplitude: float) -> void:
	var r := int(ceil(SIGMA * 3.0))
	for z in range(maxi(0, int(center.z) - r), mini(SIZE, int(center.z) + r + 1)):
		for y in range(maxi(0, int(center.y) - r), mini(SIZE, int(center.y) + r + 1)):
			for x in range(maxi(0, int(center.x) - r), mini(SIZE, int(center.x) + r + 1)):
				var d2 := Vector3(x, y, z).distance_squared_to(center)
				var v := amplitude * exp(-d2 / (2.0 * SIGMA * SIGMA))
				var idx := _index(x, y, z)
				grid[idx] = mini(255, int(grid[idx]) + int(v * 255.0))


static func _index(x: int, y: int, z: int) -> int:
	return (z * SIZE + y) * SIZE + x


## Density sample for tests and debugging. Returns -1 out of bounds.
static func density_at(grid: PackedByteArray, x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= SIZE or y >= SIZE or z >= SIZE:
		return -1
	return int(grid[_index(x, y, z)])


## Turns a built grid into a Texture3D for the raymarcher (one R8 Image per
## depth slice). Called by HoloRoom on a new observation only — 16^3 voxels,
## cheap. The shader samples .r as rho.
static func make_texture(grid: PackedByteArray) -> ImageTexture3D:
	var slices: Array[Image] = []
	for z in range(SIZE):
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
		for y in range(SIZE):
			for x in range(SIZE):
				var v := int(grid[_index(x, y, z)])
				img.set_pixel(x, y, Color(v / 255.0, 0.0, 0.0, 1.0))
		slices.append(img)
	var tex := ImageTexture3D.new()
	tex.create(SIZE, SIZE, SIZE, false, Image.FORMAT_R8, slices)
	return tex
