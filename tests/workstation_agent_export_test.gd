extends SceneTree

## True cross-surface smoke: native Godot scene exports a versioned agent capsule.
## The Python CLI validates this SAME file separately; it never runs a command.
const HYPERSPACE = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
const CAPSULE = preload("res://scripts/workstation/WorkbenchAgentCapsule.gd")
var errors: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var deck: PanelContainer = HYPERSPACE.new()
    root.add_child(deck)
    await process_frame
    var fixture := {
        "body_feed_state": "observed", "bodies": [{"body_id": "kilo-core-msi", "state": "reported_fresh"}],
        "project_feed_state": "observed",
        "projects": [{"name": "Local fixture only", "path": "C:/dev/active/Furyline", "branch": "main"}],
        "mission_feed_state": "unknown", "missions": [],
        "service_feed_state": "unknown", "services": []
    }
    deck.set_snapshot(fixture)
    _check(deck.select_key("project:C:/dev/active/Furyline"), "fixture source exists as 3D mesh")
    _check(not deck._export_button.disabled, "operator export enabled on selected source")
    deck._export_handoff()
    var path := "user://hyperspace-agent-handoff.json"
    _check(FileAccess.file_exists(path), "Godot wrote a real local file")
    if FileAccess.file_exists(path):
        var file := FileAccess.open(path, FileAccess.READ)
        var data := file.get_as_text()
        file.close()
        _check(CAPSULE.validate(data).get("ok", false), "Godot export validates via contract")
        _check(data.contains("KiloCore-Studio"), "owner referenced without pretend auth")
        _check(data.contains("C:/dev/active/Furyline"), "canonical repo preserved")
        _check(data.contains("\"permission_granted\": false"), "no authority granted")
        _check(data.to_utf8_buffer().size() < CAPSULE.MAX_BYTES, "bounded")
    var destination := ProjectSettings.globalize_path(path)
    if errors.is_empty():
        print("WORKSTATION_AGENT_EXPORT_PASS")
        print("HANDOFF_FILE=" + destination)
        quit(0)
    else:
        for e in errors:
            printerr("WORKSTATION_AGENT_EXPORT_FAIL: " + e)
        quit(1)

func _check(test: bool, message: String) -> void:
    if not test:
        errors.append(message)
