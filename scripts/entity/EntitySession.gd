extends Node

## A Godot runtime body for an *observed*, not fabricated, colony self-model.
## The owning Studio/Kilo_Core services remain outside the scene tree.
## Frame ticks measure local embodiment, not determinism of external systems.

signal self_model_changed(model: Dictionary)

const STUDIO_SENSOR = preload("res://scripts/entity/StudioObservationBridge.gd")
const MAX_HISTORY := 64
const SELF_SCHEMA := "kilocore.entity-session.v0"

@export var auto_observe: bool = false
@export_range(2.0, 300.0, 1.0) var observe_period_seconds: float = 15.0

var _sensor: Node
var _tick: int = 0
var _time_to_observe: float = 0.0
var _history: Array[Dictionary] = []

func _ready() -> void:
	_sensor = STUDIO_SENSOR.new()
	add_child(_sensor)
	_sensor.observation_changed.connect(_on_studio_observation)
	_time_to_observe = observe_period_seconds
	if auto_observe:
		_sensor.observe()

func _physics_process(delta: float) -> void:
	_tick += 1
	if not auto_observe:
		return
	_time_to_observe -= delta
	if _time_to_observe <= 0.0:
		_time_to_observe = maxf(2.0, observe_period_seconds)
		_sensor.observe()  # one request in flight; skip instead of stacking

func observe_now() -> bool:
	return _sensor != null and _sensor.observe()

func self_model() -> Dictionary:
	var observation: Dictionary = (
		_sensor.current_observation()
		if _sensor != null
		else {"state": "unknown", "error": "sensor_not_ready"}
	)
	return {
		"schema": SELF_SCHEMA,
		"phase": "observation_only",
		"tick": _tick,
		"sensor": observation,
		"capabilities": [{
			"id": "studio.health.read",
			"source": "KiloCore-Studio",
			"observed_state": observation.get("state", "unknown"),
			"mutation": false
		}],
		"authorized_actuators": [],
		"local_history_events": _history.size()
	}

func recent_events() -> Array[Dictionary]:
	return _history.duplicate(true)

func _on_studio_observation(observation: Dictionary) -> void:
	_history.append({
		"tick": _tick,
		"kind": "studio_health_observation",
		"source": observation.get("source", "unknown"),
		"state": observation.get("state", "unknown"),
		"error": observation.get("error", "")
	})
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	self_model_changed.emit(self_model())
