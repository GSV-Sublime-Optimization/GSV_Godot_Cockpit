extends Control

## Operator-readable, read-only view of the colony entity's sensory body.
## Launch this standalone scene while Studio is available on this same host.
## No mission POST, shell, model inference, or operator-credential access.

const SESSION = preload("res://scenes/EntitySession.tscn")
const BODY_NAMES := {
	"kilo-core-msi": "MSI",
	"desktop-i3anuvp": "I3",
	"desktop-l9v3emb": "L9",
	"imac-xanadu": "Xanadu"
}

var _entity: Node
var _headline: Label
var _body_labels: Dictionary = {}

func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	var heading := Label.new()
	heading.text = "ΞNuSyQ  /  ONE ENTITY · FOUR BODIES"
	heading.add_theme_font_size_override("font_size", 24)
	layout.add_child(heading)
	_headline = Label.new()
	_headline.text = "Awaiting source observations. No tool authority is granted here."
	layout.add_child(_headline)
	for node_id in BODY_NAMES:
		var row := Label.new()
		row.name = node_id
		row.text = BODY_NAMES[node_id] + " · UNKNOWN"
		row.add_theme_font_size_override("font_size", 17)
		layout.add_child(row)
		_body_labels[node_id] = row
	var caution := Label.new()
	caution.text = "READ ONLY · Reports are not authenticated agent seats or scheduling permission"
	layout.add_child(caution)
	_entity = SESSION.instantiate()
	add_child(_entity)
	_entity.self_model_changed.connect(_render_model)
	_render_model(_entity.self_model())

func _render_model(model: Dictionary) -> void:
	_headline.text = (
		"Entity sensor · %s · %d local ticks · 0 authorized actuators"
		% [model.get("phase", "unknown"), int(model.get("tick", 0))]
	)
	var bodies: Array = model.get("fleet_bodies", [])
	for body in bodies:
		if typeof(body) != TYPE_DICTIONARY:
			continue
		var node_id: String = String(body.get("body_id", ""))
		if not _body_labels.has(node_id):
			continue
		var label: Label = _body_labels[node_id]
		var state: String = String(body.get("state", "unknown"))
		var details := ""
		var observation: Dictionary = body.get("observation", {})
		if state == "reported_fresh" or state == "stale":
			details = " · RAM %s · system free %s" % [
				_format_bytes(observation.get("memory_available_bytes", null)),
				_format_bytes(observation.get("system_volume_free_bytes", null))
			]
		label.text = "%s  ·  %s%s" % [BODY_NAMES[node_id], state, details]
		# Neutral text only: no markup from external services is interpreted.

func _format_bytes(value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "unknown"
	return "%.1f GiB" % (float(value) / 1073741824.0)
