extends PanelContainer
class_name AgentMap

## AgentMap — Colony agents as nodes on a visual graph.
## Agents are crew. The map is the ship layout.

const AGENTS := {
	"ship":        Vector2(80,  50),
	"gsv":         Vector2(200, 50),
	"intermediary":Vector2(320, 50),
	"fcc":         Vector2(80,  125),
	"litellm":     Vector2(200, 125),
	"openclaw":    Vector2(320, 125),
	"devmentor":   Vector2(80,  200),
	"nusyq":       Vector2(200, 200),
	"serena":      Vector2(320, 200),
}

const RADIUS := 18.0
const CANVAS_SIZE := Vector2(400, 250)

var _status: Dictionary = {}
var _canvas: Control
var _refresh_btn: Button

func _ready() -> void:
	# Init all gray
	for name in AGENTS.keys():
		_status[name] = false

	var root := VBoxContainer.new()
	add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "🗺 Agent Map — Colony Crew"
	title.add_theme_font_size_override("font_size", 15)
	hdr.add_child(title)

	_refresh_btn = Button.new()
	_refresh_btn.text = "↺"
	_refresh_btn.pressed.connect(refresh)
	hdr.add_child(_refresh_btn)

	_canvas = Control.new()
	_canvas.custom_minimum_size = CANVAS_SIZE
	_canvas.draw.connect(_draw_agents)
	root.add_child(_canvas)

	var legend := Label.new()
	legend.text = "green = agent command found on PATH   gray = missing"
	legend.modulate = Color(0.6, 0.6, 0.6)
	root.add_child(legend)

	refresh()

func set_agent_status(name: String, up: bool) -> void:
	_status[name] = up
	if _canvas:
		_canvas.queue_redraw()

func refresh() -> void:
	# Check each agent command via OS
	for name in AGENTS.keys():
		var found := _cmd_exists(name)
		_status[name] = found
	if _canvas:
		_canvas.queue_redraw()

func _cmd_exists(name: String) -> bool:
	var output: Array = []
	var mapped := name
	# Map display names to actual commands
	if name == "fcc":        mapped = "fcc-codex"
	elif name == "litellm":  mapped = "ollama"   # proxy: litellm lives via docker, check ollama instead
	elif name == "devmentor":mapped = "td"
	elif name == "nusyq":    mapped = "gsv"
	var code := OS.execute(PsShell.exe(), ["-NoProfile","-Command",
		"if (Get-Command '%s' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" % mapped],
		output, true, false)
	return code == 0

func _draw_agents() -> void:
	for name in AGENTS.keys():
		var pos: Vector2 = AGENTS[name]
		var up: bool = _status.get(name, false)
		var color := Color(0.2, 0.9, 0.3) if up else Color(0.4, 0.4, 0.4)
		var border := Color(0.1, 0.6, 0.1) if up else Color(0.25, 0.25, 0.25)

		_canvas.draw_circle(pos, RADIUS + 2, border)
		_canvas.draw_circle(pos, RADIUS, color)

		# Label below
		var lbl_pos := pos + Vector2(-RADIUS, RADIUS + 4)
		_canvas.draw_string(
			ThemeDB.fallback_font,
			lbl_pos,
			name,
			HORIZONTAL_ALIGNMENT_LEFT,
			RADIUS * 3,
			11,
			Color.WHITE
		)
