extends PanelContainer
class_name GitLogPanel

## GitLogPanel — Recent git commits across colony repos.
## Runs `git log` locally — zero HTTP, zero bridge, purely local.

const REPOS := [
	"C:/dev/active/Kilo_Core",
	"C:/dev/active/Dev-Mentor",
	"C:/dev/active/NuSyQ-Hub",
	"C:/dev/active/GSV_Godot_Cockpit",
	"C:/dev",
]
const COMMITS_PER_REPO := 5

var _box:     RichTextLabel
var _repo_sel: OptionButton

static func create() -> GitLogPanel:
	return GitLogPanel.new()

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# Header
	var hdr := HBoxContainer.new()
	root.add_child(hdr)

	var title := Label.new()
	title.text = "🔀 Git Log — Colony Commits"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	_repo_sel = OptionButton.new()
	_repo_sel.add_item("all repos")
	for r in REPOS:
		_repo_sel.add_item(r.split("/")[-1])
	_repo_sel.item_selected.connect(func(_i): refresh())
	hdr.add_child(_repo_sel)

	var refresh_btn := Button.new()
	refresh_btn.text = "↺"
	refresh_btn.pressed.connect(refresh)
	hdr.add_child(refresh_btn)

	_box = RichTextLabel.new()
	_box.bbcode_enabled = true
	_box.scroll_following = false
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_box)

	refresh()

func refresh() -> void:
	_box.clear()
	var sel := _repo_sel.selected  # 0 = all

	if sel == 0:
		for repo in REPOS:
			_show_repo(repo)
	else:
		_show_repo(REPOS[sel - 1])

func _show_repo(repo: String) -> void:
	var name := repo.split("/")[-1]
	_box.append_text("\n[b][color=cyan]%s[/color][/b]\n" % name)

	var output: Array = []
	var fmt := "%h  %ar  %an  %s"
	var code := OS.execute(PsShell.exe(), [
		"-NoProfile", "-Command",
		"cd '%s'; git log --oneline --format='%s' -n %d 2>&1" % [repo, fmt, COMMITS_PER_REPO]
	], output, true, false)

	if code != 0 or output.is_empty():
		_box.append_text("  [color=red](git error or no repo)[/color]\n")
		return

	var text := ""
	for line in output: text += str(line)
	var lines := text.split("\n")
	for line in lines:
		line = line.strip_edges()
		if line == "": continue
		# First 7 chars = short hash
		if line.length() > 7:
			var hash_part := line.substr(0, 7)
			var rest := line.substr(8)
			_box.append_text("  [color=yellow]%s[/color] %s\n" % [hash_part, rest])
		else:
			_box.append_text("  %s\n" % line)
