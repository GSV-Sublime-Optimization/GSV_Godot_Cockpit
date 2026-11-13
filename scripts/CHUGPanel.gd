extends PanelContainer
class_name CHUGPanel

## CHUGPanel — Continuous Harvest Update Generator telemetry.
## CHUG is the colony's autonomous improvement daemon (Terminal Depths :7337).
## Shows cycles, issues found, fixes applied, and active suggestions.

const DM_HEALTH := "http://localhost:7337/api/health"
const DM_CHUG   := "http://localhost:7337/api/chug/status"
const DM_TRIGGER := "http://localhost:7337/api/chug/trigger"

var _stats: RichTextLabel
var _suggestions: VBoxContainer

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# Header row
	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "⚙ CHUG — Harvest Update Generator"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	var refresh_btn := Button.new()
	refresh_btn.text = "↺ Refresh"
	refresh_btn.pressed.connect(refresh)
	hdr.add_child(refresh_btn)

	var trigger_btn := Button.new()
	trigger_btn.text = "▶ Trigger CHUG"
	trigger_btn.modulate = Color(0.4, 1.0, 0.4)
	trigger_btn.pressed.connect(_trigger_chug)
	hdr.add_child(trigger_btn)

	# Stats area
	_stats = RichTextLabel.new()
	_stats.fit_content = true
	_stats.custom_minimum_size = Vector2(0, 80)
	root.add_child(_stats)

	var sep := HSeparator.new()
	root.add_child(sep)

	# Suggestions label
	var slbl := Label.new()
	slbl.text = "Active Suggestions:"
	slbl.modulate = Color(1.0, 1.0, 0.4)
	root.add_child(slbl)

	_suggestions = VBoxContainer.new()
	_suggestions.add_theme_constant_override("separation", 3)
	root.add_child(_suggestions)

	refresh()

func refresh() -> void:
	_stats.clear()
	_stats.append_text("[color=cyan]Probing CHUG daemon...[/color]")

	var raw := _ps_get(DM_CHUG)
	if raw.begins_with("ERR"):
		_stats.clear()
		_stats.append_text("[color=red]" + raw + "[/color]")
		return

	var json := JSON.new()
	if json.parse(raw) != OK:
		_stats.clear()
		_stats.append_text("[color=yellow]Parse error — raw:\n" + raw.substr(0, 200) + "[/color]")
		return

	var d = json.get_data()
	_stats.clear()

	if typeof(d) != TYPE_DICTIONARY:
		_stats.append_text("[color=red]Unexpected response type[/color]")
		return

	var cycles  := str(d.get("cycles_completed", d.get("total_cycles", "?")))
	var issues  := str(d.get("total_issues_found", d.get("issues_found", "?")))
	var fixes   := str(d.get("total_fixes_applied", d.get("fixes_applied", "?")))
	var last_ts := str(d.get("last_cycle_at", d.get("last_run", "?")))
	if last_ts.length() > 16:
		last_ts = last_ts.substr(0, 16)

	_stats.append_text(
		"[b]cycles:[/b] %s    [b]issues found:[/b] %s    [b]fixes applied:[/b] %s\n" % [cycles, issues, fixes]
	)
	_stats.append_text("[color=gray]last cycle: %s[/color]\n" % last_ts)

	# Health check to verify daemon is live
	var health := _ps_get(DM_HEALTH)
	if health.contains("\"status\":\"ok\"") or health.contains("\"healthy\":true"):
		_stats.append_text("[color=green]● daemon UP[/color]")
	else:
		_stats.append_text("[color=yellow]● daemon status uncertain[/color]")

	# Suggestions
	for child in _suggestions.get_children():
		child.queue_free()

	var suggestions = d.get("suggestions", d.get("chug_suggestions", []))
	if typeof(suggestions) != TYPE_ARRAY or suggestions.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "  (no active suggestions)"
		none_lbl.modulate = Color(0.5, 0.5, 0.5)
		_suggestions.add_child(none_lbl)
		return

	var shown := 0
	for s in suggestions:
		if shown >= 4:
			break
		var lbl := Label.new()
		lbl.text = "  ◆ " + str(s).substr(0, 100)
		lbl.modulate = Color(1.0, 1.0, 0.4)
		lbl.clip_text = true
		_suggestions.add_child(lbl)
		shown += 1

func _trigger_chug() -> void:
	var output: Array = []
	OS.execute(PsShell.exe(), [
		"-NoProfile", "-Command",
		"Invoke-WebRequest '%s' -Method Post -UseBasicParsing -TimeoutSec 10 | Out-Null; Write-Host 'triggered'" % DM_TRIGGER
	], output, true, false)
	_stats.append_text("\n[color=green]⚡ CHUG cycle triggered[/color]")

func _ps_get(url: String) -> String:
	var output: Array = []
	var code := OS.execute(PsShell.exe(), [
		"-NoProfile", "-Command",
		"try { (Invoke-WebRequest '%s' -UseBasicParsing -TimeoutSec 5).Content } catch { 'ERR: ' + $_.Exception.Message }" % url
	], output, true, false)
	var text := ""
	for line in output:
		text += str(line)
	if text.strip_edges().is_empty():
		return "ERR: no output (exit %d)" % code
	return text.strip_edges()
