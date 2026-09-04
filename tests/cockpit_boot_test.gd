extends SceneTree

## Headless boot budget + tab wiring check for the cockpit.
##
## Every panel that talks to the colony does so with a blocking
## OS.execute("pwsh", ...) call from its own _ready(), so any tab built during
## _build_ui() is paid for before the window can draw anything at all.
##
## Run:
##   godot-run.ps1 -ProjectPath <repo> -- --script res://tests/cockpit_boot_test.gd
##
## Exit 0 = pass, 1 = fail. Phase 2 deliberately pays the full probe cost, so
## the whole run takes about as long as the old boot did.

const MAIN_SCENE := "res://scenes/Main.tscn"

## Measured boot storm before lazy tabs: 	39 s of serial pwsh spawns. A
## generous ceiling still separates "paints, then probes" from the reverse.
const BUDGET_MSEC := 8000

const EXPECTED_TABS: PackedStringArray = [
	"Status",
	"Events",
	"Git Log",
	"Dispatch",
	"Models",
	"Agents",
	"CHUG",
	"Quests",
	"Receipts",
	"Terminal Depths",
	"Flight",
	"Steer",
	"Route",
]

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		_fail("could not load %s" % MAIN_SCENE)
		_finish()
		return

	# Phase 1 — time to first painted frame.
	var started := Time.get_ticks_msec()
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	var elapsed := Time.get_ticks_msec() - started

	print("[boot-test] time to first frame: %d ms (budget %d ms)" % [elapsed, BUDGET_MSEC])
	if elapsed > BUDGET_MSEC:
		_fail("first frame took %d ms, over the %d ms budget" % [elapsed, BUDGET_MSEC])

	var tabs := _find_tab_container(main)
	if tabs == null:
		_fail("no TabContainer found under the main scene")
	else:
		_check_tab_surface(tabs)
		await _check_lazy_tabs(tabs)

	main.queue_free()
	_finish()


func _check_tab_surface(tabs: TabContainer) -> void:
	var titles: PackedStringArray = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	print("[boot-test] tabs: %s" % ", ".join(titles))

	if titles != EXPECTED_TABS:
		_fail("tab surface changed\n  expected: %s\n  actual:   %s" % [
			", ".join(EXPECTED_TABS),
			", ".join(titles),
		])


## A fast boot is worthless if the deferred tabs never build. Visit every tab
## and require each to gain real content — this exercises every panel script
## that used to run during _build_ui().
func _check_lazy_tabs(tabs: TabContainer) -> void:
	for i in tabs.get_tab_count():
		var title := tabs.get_tab_title(i)
		tabs.current_tab = i
		await process_frame
		var page := tabs.get_tab_control(i)
		if page == null:
			_fail("tab '%s' has no control" % title)
			continue
		if page.get_child_count() == 0:
			_fail("tab '%s' stayed empty after being shown" % title)
			continue
		print("[boot-test] tab '%s' built %d node(s)" % [title, page.get_child_count()])


func _find_tab_container(node: Node) -> TabContainer:
	if node is TabContainer:
		return node
	for child in node.get_children():
		var found := _find_tab_container(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[boot-test] PASS")
		quit(0)
		return
	for message in _failures:
		printerr("[boot-test] FAIL: %s" % message)
	print("[boot-test] FAILED (%d)" % _failures.size())
	quit(1)
