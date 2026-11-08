extends Node

## A Godot runtime body for an *observed*, not fabricated, colony self-model.
## The owning Studio/Kilo_Core services remain outside the scene tree.
## Frame ticks measure local embodiment, not determinism of external systems.

signal self_model_changed(model: Dictionary)

const STUDIO_SENSOR = preload("res://scripts/entity/StudioObservationBridge.gd")
const CONSTELLATION_SENSOR = preload("res://scripts/entity/StudioConstellationBridge.gd")
const GATEWAY_SENSOR = preload("res://scripts/entity/GatewayObservationBridge.gd")
const MAX_HISTORY := 64
const SELF_SCHEMA := "kilocore.entity-session.v0"
const DEFAULT_CONSTELLATION_PERIOD_SECONDS := 180.0

@export var auto_observe: bool = false
@export_range(2.0, 300.0, 1.0) var observe_period_seconds: float = 15.0

var _sensor: Node
var _constellation: Node
var _gateway: Node
var _tick: int = 0
var _time_to_observe: float = 0.0
var _time_to_constellation: float = 0.0
var _history: Array[Dictionary] = []

func _ready() -> void:
	_sensor = STUDIO_SENSOR.new()
	add_child(_sensor)
	_sensor.observation_changed.connect(_on_studio_observation)
	_constellation = CONSTELLATION_SENSOR.new()
	add_child(_constellation)
	_constellation.observation_changed.connect(_on_constellation_observation)
	_gateway = GATEWAY_SENSOR.new()
	add_child(_gateway)
	_gateway.observation_changed.connect(_on_gateway_observation)
	_time_to_observe = observe_period_seconds
	_time_to_constellation = DEFAULT_CONSTELLATION_PERIOD_SECONDS
	if auto_observe:
		_sensor.observe()
		_constellation.observe()
		_gateway.observe()

func _physics_process(delta: float) -> void:
	_tick += 1
	if not auto_observe:
		return
	_time_to_observe -= delta
	if _time_to_observe <= 0.0:
		_time_to_observe = maxf(2.0, observe_period_seconds)
		_sensor.observe()  # one request in flight; skip instead of stacking
		_gateway.observe()  # fast health sense; shares the 15s tick
	_time_to_constellation -= delta
	if _time_to_constellation <= 0.0:
		_time_to_constellation = maxf(60.0, DEFAULT_CONSTELLATION_PERIOD_SECONDS)
		_constellation.observe()  # cached sensor; no-op inside its refresh window

func observe_now() -> bool:
	return _sensor != null and _sensor.observe()

func observe_constellation_now(force: bool = false) -> bool:
	return _constellation != null and _constellation.observe(force)

func observe_gateway_now() -> bool:
	return _gateway != null and _gateway.observe()

func self_model() -> Dictionary:
	var observation: Dictionary = (
		_sensor.current_observation()
		if _sensor != null
		else {"state": "unknown", "error": "sensor_not_ready"}
	)
	var constellation: Dictionary = (
		_constellation.current_observation()
		if _constellation != null
		else {"state": "unknown", "error": "sensor_not_ready"}
	)
	var gateway: Dictionary = (
		_gateway.current_observation()
		if _gateway != null
		else {"state": "unknown", "error": "sensor_not_ready"}
	)
	return {
		"schema": SELF_SCHEMA,
		"phase": "observation_only",
		"tick": _tick,
		"sensor": observation,
		"constellation": constellation,
		"gateway": gateway,
		"capabilities": [{
			"id": "studio.health.read",
			"source": "KiloCore-Studio",
			"observed_state": observation.get("state", "unknown"),
			"mutation": false
		}, {
			"id": "studio.projects.read",
			"source": "KiloCore-Studio",
			"observed_state": constellation.get("state", "unknown"),
			"mutation": false
		}, {
			"id": "gateway.health.read",
			"source": "KiloCore-Gateway",
			"observed_state": gateway.get("state", "unknown"),
			"mutation": false
		}],
		"authorized_actuators": [],
		"local_history_events": _history.size()
	}

func recent_events() -> Array[Dictionary]:
	return _history.duplicate(true)

func _on_studio_observation(observation: Dictionary) -> void:
	_record_event("studio_health_observation", observation)

func _on_constellation_observation(observation: Dictionary) -> void:
	_record_event("constellation_observation", observation)

func _on_gateway_observation(observation: Dictionary) -> void:
	_record_event("gateway_health_observation", observation)

func _record_event(kind: String, observation: Dictionary) -> void:
	_history.append({
		"tick": _tick,
		"kind": kind,
		"source": observation.get("source", "unknown"),
		"state": observation.get("state", "unknown"),
		"error": observation.get("error", "")
	})
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	self_model_changed.emit(self_model())
