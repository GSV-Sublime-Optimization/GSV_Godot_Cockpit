extends PanelContainer
class_name TDStatePanel

## TDStatePanel — Terminal Depths live state viewer.
## TD is the game-heart. This panel shows its pulse.

const BRIDGE := "C:/GSV/tools/godot-cockpit/Invoke-GSVGodotBridge.ps1"
const TD_HEALTH_URL := "http://localhost:7337/api/health"
const TD_CHUG_URL   := "http://localhost:7337/api/chug/status"
const TD_DEPTH_URL  := "http://localhost:7337/api/player/depth"

var _label: RichTextLabel
var _refresh_btn: Button

func _ready() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "⚡ Terminal Depths — Game Heart"
	title.add_theme_font_size_override("font_size", 15)
	hdr.add_child(title)

	_refresh_btn = Button.new()
	_refresh_btn.text = "↺"
	_refresh_btn.pressed.connect(refresh)
	hdr.add_child(_refresh_btn)

	_label = RichTextLabel.new()
	_label.scroll_following = true
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size = Vector2(0, 160)
	root.add_child(_label)

	refresh()

func refresh() -> void:
	_label.clear()
	_append("[color=cyan]── Terminal Depths ──[/color]")

	# Health
	_probe_and_show("DevMentor health", TD_HEALTH_URL)

	# CHUG
	_probe_and_show("CHUG status", TD_CHUG_URL, func(d):
		if typeof(d) == TYPE_DICTIONARY:
			var chug = d.get("chug", d)
			if typeof(chug) == TYPE_DICTIONARY:
				_append("  cycles: [color=green]%s[/color]" % str(chug.get("cycles_completed", "?")))
				_append("  issues: %s  fixes: %s" % [
					str(chug.get("total_issues_found", "?")),
					str(chug.get("total_fixes_applied", "?"))
				])
				var sugs = chug.get("chug_suggestions", [])
				if typeof(sugs) == TYPE_ARRAY:
					for s in sugs.slice(0, 3):
						_append("  [color=yellow]→[/color] " + str(s))
	)

	# Player depth
	_probe_and_show("Player depth", TD_DEPTH_URL, func(d):
		if typeof(d) == TYPE_DICTIONARY:
			_append("  depth: [color=green]%s[/color]  xp: %s" % [
				str(d.get("depth", d.get("current_depth", "?"))),
				str(d.get("xp", d.get("total_xp", "?")))
			])
	)

	_append("")
	_append("[color=gray]Launch TD: docker compose -f C:/dev/active/Kilo_Core/docker-compose.yml up -d dev-mentor[/color]")

func _probe_and_show(label: String, url: String, parser: Callable = Callable()) -> void:
	var args: Array[String] = [
		"-NoProfile", "-ExecutionPolicy", "Bypass",
		"-Command",
		"try { $r=Invoke-WebRequest '%s' -UseBasicParsing -TimeoutSec 4; Write-Output $r.Content } catch { Write-Output 'ERROR: '+$_.Exception.Message }" % url
	]
	var output: Array = []
	OS.execute(PsShell.exe(), args, output, true, false)
	var raw := ""
	for item in output:
		raw += str(item)
	raw = raw.strip_edges()

	if raw.begins_with("ERROR"):
		_append("[color=red]✗[/color] %s — %s" % [label, raw.substr(7, 60)])
		return

	_append("[color=green]✓[/color] %s" % label)

	if not parser.is_null():
		var json := JSON.new()
		if json.parse(raw) == OK:
			parser.call(json.get_data())

func _append(text: String) -> void:
	if _label:
		_label.append_text(text + "\n")
