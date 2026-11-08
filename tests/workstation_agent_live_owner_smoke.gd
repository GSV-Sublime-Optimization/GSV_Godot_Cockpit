extends SceneTree

## OPTIONAL LIVE LOOPBACK SMOKE. NOT in offline .gsv/build.yaml.
## GET actual Studio mission index -> 3D selection -> Godot writes capsule.
## No POST, no raw logs, no secrets, no fake success or agent session.
const HYPERSPACE = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
const CATALOG = preload("res://scripts/workstation/WorkbenchCatalog.gd")
const CAPSULE = preload("res://scripts/workstation/WorkbenchAgentCapsule.gd")

func _initialize() -> void:
    _run.call_deferred()

func _fail(reason: String) -> void:
    printerr("WORKSTATION_LIVE_HANDOFF_UNAVAILABLE: " + reason)
    quit(2)

func _run() -> void:
    var supplied := OS.get_environment("GSV_STUDIO_ENTITY_PORT")
    var port := 7340
    if not supplied.is_empty():
        if not supplied.is_valid_int() or int(supplied) < 1 or int(supplied) > 65535:
            _fail("invalid_port")
            return
        port = int(supplied)
    var http := HTTPRequest.new()
    http.max_redirects = 0
    http.timeout = 7.0
    root.add_child(http)
    var err := http.request("http://127.0.0.1:%d/api/missions?limit=12" % port,
        PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
    if err != OK:
        _fail("studio_get_refused")
        return
    var reply: Array = await http.request_completed
    if int(reply[0]) != HTTPRequest.RESULT_SUCCESS or int(reply[1]) != 200:
        _fail("studio_get_unavailable")
        return
    var bytes: PackedByteArray = reply[3]
    if bytes.size() > 131072:
        _fail("source_oversized")
        return
    var parsed: Dictionary = CATALOG.parse_mission_list(bytes.get_string_from_utf8())
    if not parsed.get("ok", false):
        _fail("invalid_studio_mission_index")
        return
    var rows: Array = parsed["missions"]
    if rows.is_empty():
        _fail("no_owner_missions")
        return
    var observed: Dictionary = rows[0]
    var mid := String(observed["id"])
    var deck: PanelContainer = HYPERSPACE.new()
    root.add_child(deck)
    await process_frame
    deck.set_snapshot({
        "body_feed_state": "unknown", "project_feed_state": "unknown",
        "mission_feed_state": "observed", "service_feed_state": "unknown",
        "missions": rows, "projects": [], "services": [], "bodies": []
    })
    if not deck.select_key("mission:" + mid) or deck._export_button.disabled:
        _fail("mission_not_selectable_in_3d")
        return
    deck._export_handoff()
    var path := "user://hyperspace-agent-handoff.json"
    if not FileAccess.file_exists(path):
        _fail("no_exported_file")
        return
    var file := FileAccess.open(path, FileAccess.READ)
    var capsule := CAPSULE.validate(file.get_as_text())
    file.close()
    if not capsule.get("ok", false) or String(capsule["resource"].get("id", "")) != mid:
        _fail("export_identity_mismatch")
        return
    if capsule["resource"].get("execution_admitted", true):
        _fail("false_execution_permission")
        return
    print("WORKSTATION_LIVE_STUDIO_HANDOFF_PASS")
    print("LIVE_MISSION_ID=" + mid)
    print("HANDOFF_FILE=" + ProjectSettings.globalize_path(path))
    quit(0)
