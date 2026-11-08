extends VBoxContainer

## ModelStatusPanel — Live model bloodstream: Ollama · LiteLLM · FCC.
## Probes each inference endpoint and shows available models.

const BRIDGE := "C:/GSV/tools/godot-cockpit/Invoke-GSVGodotBridge.ps1"

var _output: RichTextLabel
var _status: Label

func _ready() -> void:
	var title := Label.new()
	title.text = "Ξ Model Bloodstream — Ollama · LiteLLM · FCC"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	_status = Label.new()
	_status.text = "status: waiting"
	_status.modulate = Color(0.6, 0.6, 0.6)
	add_child(_status)

	var btns := HBoxContainer.new()
	add_child(btns)

	var refresh_btn := Button.new()
	refresh_btn.text = "↺ Refresh"
	refresh_btn.pressed.connect(refresh_models)
	btns.add_child(refresh_btn)

	var fcc_note := Label.new()
	fcc_note.text = "  bridge mode: models"
	fcc_note.modulate = Color(0.5, 0.5, 0.5)
	btns.add_child(fcc_note)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = false
	add_child(_output)

	refresh_models()

func refresh_models() -> void:
	_status.text = "status: probing..."
	_output.clear()
	_output.append_text("[color=cyan]probing model bloodstream...[/color]\n")

	# Parallel: probe Ollama and LiteLLM directly (faster than bridge)
	var online := 0
	if _probe_ollama():
		online += 1
	if _probe_litellm():
		online += 1
	if _probe_fcc():
		online += 1
	_status.text = "status: live" if online == 3 else ("status: offline" if online == 0 else "status: partial (%d/3)" % online)

func _probe_ollama() -> bool:
	var raw := _fetch_url("http://localhost:11434/api/tags")
	_output.append_text("\n[b]OLLAMA :11434[/b]\n")
	var parsed = _safe_json(raw)
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("models")) == TYPE_ARRAY:
		var models: Array = parsed["models"]
		_output.append_text("[color=green]● UP[/color] — %d models\n" % models.size())
		for m in models:
			if typeof(m) == TYPE_DICTIONARY:
				var name_str: String = str(m.get("name", m.get("model", "?")))
				var size_gb: float = float(str(m.get("size", 0))) / 1_000_000_000.0
				_output.append_text("  [color=gray]·[/color] %s  [color=gray](%.1fGB)[/color]\n" % [name_str, size_gb])
		return true
	else:
		_output.append_text("[color=red]● DOWN[/color]\n")
	return false

func _probe_litellm() -> bool:
	var raw := _fetch_url("http://localhost:4000/v1/models")
	_output.append_text("\n[b]LITELLM :4000[/b]\n")
	var parsed = _safe_json(raw)
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("data")) == TYPE_ARRAY:
		var items: Array = parsed["data"]
		_output.append_text("[color=green]● UP[/color] — %d aliases\n" % items.size())
		for item in items:
			if typeof(item) == TYPE_DICTIONARY:
				_output.append_text("  [color=gray]·[/color] %s\n" % str(item.get("id", "?")))
		return true
	else:
		_output.append_text("[color=red]● DOWN[/color]\n")
	return false

func _probe_fcc() -> bool:
	var raw := _fetch_url("http://127.0.0.1:8082/v1/models")
	_output.append_text("\n[b]FCC :8082[/b]\n")
	var parsed = _safe_json(raw)
	if typeof(parsed) == TYPE_DICTIONARY and (typeof(parsed.get("data")) == TYPE_ARRAY or typeof(parsed.get("models")) == TYPE_ARRAY):
		var items: Array = parsed["data"] if typeof(parsed.get("data")) == TYPE_ARRAY else parsed["models"]
		_output.append_text("[color=green]● UP[/color] — %d models\n" % items.size())
		# Show first 8
		var shown := 0
		for item in items:
			if shown >= 8: break
			if typeof(item) == TYPE_DICTIONARY:
				_output.append_text("  [color=gray]·[/color] %s\n" % str(item.get("id", item.get("name", "?"))))
			shown += 1
		if items.size() > 8:
			_output.append_text("  [color=gray]... +%d more[/color]\n" % (items.size() - 8))
		return true
	else:
		_output.append_text("[color=yellow]● NOT FOUND[/color] (start fcc-codex)\n")
	return false

func _safe_json(raw: String) -> Variant:
	if raw.is_empty():
		return null
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return null
	return parser.data

func _fetch_url(url: String) -> String:
	var output: Array = []
	var code: int
	if OS.has_feature("windows"):
		var args := ["-NoProfile", "-Command",
			"try { (Invoke-WebRequest '%s' -UseBasicParsing -TimeoutSec 4).Content } catch { '' }" % url]
		code = OS.execute("pwsh", args, output, true, false)
		if code != 0:
			output.clear()
			code = OS.execute("powershell", args, output, true, false)
	else:
		code = OS.execute("curl", ["--fail", "--silent", "--max-time", "4", url], output, true, false)
	if code != 0:
		return ""
	var result := ""
	for item in output:
		result += str(item)
	return result.strip_edges()
