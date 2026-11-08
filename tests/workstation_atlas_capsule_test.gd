extends SceneTree

const ATLAS = preload("res://scripts/workstation/WorkbenchAtlasBridge.gd")
const PROJECTION = preload("res://scripts/workstation/WorkbenchSpatialProjection.gd")
const HYPERSPACE = preload("res://scripts/workstation/WorkbenchHyperspace.gd")
const CAPSULE = preload("res://scripts/workstation/WorkbenchAgentCapsule.gd")
var errors: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var entries := []
    for i in 30:
        entries.append({"id": "cap%03d" % i, "name": "Tool %03d" % i,
            "kind": "capability", "machine": "msi",
            "grade": "Q" if i == 0 else "D", "cost_class": "tokenless",
            "state": "degraded" if i == 0 else "live",
            "evidence": "Test-only recorded source evidence", "can_do": "Analyze code"})
    var raw := {"schema": ATLAS.SCHEMA, "generated_at": "2026-11-08T08:00:00Z", "entries": entries}
    var parsed: Dictionary = ATLAS.parse(JSON.stringify(raw))
    _check(parsed.get("ok", false), "strict Atlas schema accepted")
    _check(parsed["entries"].size() == 30, "provider entries preserved")
    _check(not parsed["entries"][0]["admitted"], "static grade is not permission")
    var projection: Dictionary = PROJECTION.project({}, parsed["entries"], "synthetic_fixture")
    _check(projection["nodes"].size() == 28, "4 rig identities + bounded 24 Atlas")
    _check(projection["atlas_omitted"] == 6, "hidden Atlas items reported")
    _check(projection["edges"].is_empty(), "static provider cannot mint verified runtime links")
    _check(PROJECTION.color_for("snapshot:live") != PROJECTION.color_for("reported_fresh"),
        "static Atlas never receives live-green")
    var item: Dictionary = {}
    for n in projection["nodes"]:
        if n.get("kind", "") == "capability":
            item = n
            break
    _check(not item.is_empty() and not item["observed"], "snapshot is visible but not live")
    var capsule: Dictionary = CAPSULE.build(item, projection, {})
    _check(capsule.get("ok", false), "agent receives portable capability context")
    _check(CAPSULE.validate(capsule["json"]).get("ok", false), "capability capsule validates")
    _check(capsule["data"]["authority"]["permission_granted"] == false,
        "handoff never grants tool privilege")
    var forbidden: Dictionary = capsule["data"].duplicate(true)
    forbidden["authority"]["permission_granted"] = true
    _check(not CAPSULE.validate(JSON.stringify(forbidden)).get("ok", true),
        "forged approval rejected on import")
    var fake := raw.duplicate(true)
    fake["entries"][1]["grade"] = "ROOT"
    _check(not ATLAS.parse(JSON.stringify(fake)).get("ok", true), "invented capability grade rejected")
    fake = raw.duplicate(true)
    fake["entries"][1]["id"] = "cap000"
    _check(not ATLAS.parse(JSON.stringify(fake)).get("ok", true), "duplicate capability rejected")
    var hyperspace: PanelContainer = HYPERSPACE.new()
    root.add_child(hyperspace)
    await process_frame
    hyperspace._capabilities.clear()
    hyperspace._capabilities.assign(parsed["entries"])
    hyperspace._atlas_source = "synthetic_fixture"
    hyperspace.set_snapshot({})
    _check(hyperspace._meshes.has("capability:cap000"), "real 3D Atlas mesh generated")
    _check(hyperspace.select_key("capability:cap000"), "3D Atlas selectable")
    _check(hyperspace._open_button.disabled and hyperspace._compose_button.disabled,
        "no execution or Studio mission from static tool card")
    _check(not hyperspace._export_button.disabled, "agent handoff available on Atlas selection")
    hyperspace._lens.select(5)
    hyperspace._apply_visibility()
    _check(not hyperspace._meshes["rig:kilo-core-msi"]["root"].visible,
        "Atlas lens filters live 3D scene")
    hyperspace.queue_free()
    await process_frame
    if errors.is_empty():
        print("WORKSTATION_ATLAS_CAPSULE_PASS")
        quit(0)
    else:
        for e in errors:
            printerr("WORKSTATION_ATLAS_CAPSULE_FAIL: " + e)
        quit(1)

func _check(ok: bool, label: String) -> void:
    if not ok:
        errors.append(label)
