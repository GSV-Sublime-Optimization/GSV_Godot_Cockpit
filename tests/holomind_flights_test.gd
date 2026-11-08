extends SceneTree
## Motion is earned: only real changes between feeds make anything fly.
## Run: godot --headless --path . --script res://tests/holomind_flights_test.gd

func _initialize() -> void:
	var holo: Node3D = (load("res://scenes/HoloMind.tscn") as PackedScene).instantiate()
	holo.set("shot_path", "")
	root.add_child(holo)
	await process_frame
	var fails := PackedStringArray()
	var base := {"bodies": {"i3": {"status": "red", "age_s": 200}, "msi": {"status": "green", "age_s": 100}, "xanadu": {"status": "green", "age_s": 0}},
		"orders": [{"id": "o1", "status": "done", "to": "claude (i3 seat)", "text": "old order"}]}
	holo.set("_flights_primed", false)
	holo.set("feed", base.duplicate(true))
	holo.call("_detect_flights")
	if (holo.get("_flights") as Array).size() != 0:
		fails.append("old news flew on the first feed")
	# Same feed again, with heartbeats only ageing: nothing happened, so nothing may fly.
	var aged := base.duplicate(true)
	aged["bodies"]["i3"]["age_s"] = 210
	aged["bodies"]["msi"]["age_s"] = 110
	holo.set("feed", aged)
	holo.call("_detect_flights")
	if (holo.get("_flights") as Array).size() != 0:
		fails.append("ageing heartbeats flew")
	# A new heartbeat from the MSI (its age dropped), a new order, and a status change on o1? No: o1 unchanged.
	var news := aged.duplicate(true)
	news["bodies"]["msi"]["age_s"] = 5
	news["orders"].append({"id": "o2", "status": "posted", "to": "claude (i3 seat)", "text": "new order"})
	holo.set("feed", news)
	holo.call("_detect_flights")
	if (holo.get("_flights") as Array).size() != 2:
		fails.append("expected exactly 2 flights (MSI heartbeat + new order), got %d" % (holo.get("_flights") as Array).size())
	# The seat takes o2: one receipt flies back.
	var taken := news.duplicate(true)
	taken["orders"][1]["status"] = "taken"
	holo.set("feed", taken)
	holo.call("_detect_flights")
	if (holo.get("_flights") as Array).size() != 3:
		fails.append("expected the receipt to fly (3 total), got %d" % (holo.get("_flights") as Array).size())
	# A silent rig's age reset is not a heartbeat we can vouch for.
	print("[flights-test] " + ("PASS" if fails.is_empty() else "FAIL: " + "; ".join(fails)))
	quit(0 if fails.is_empty() else 1)
