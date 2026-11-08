extends RefCounted

## Sync doors (design §4): every named sync target rendered as a door —
## a panel naming what it is, its real source, and its honest state — never
## a re-implementation of the surface behind it, never a faked live feed.
##
## Pure logic: build_doors() takes the facts the room has already observed
## (file presence, mtimes, the PU queue state) and returns door dicts.
## The four NOT-A-THING verdicts (design §4.1) are doors too — a derived
## view labelled DERIVED is visible in the room, not silently dropped.
##
## Door states use the honest vocabulary: live / stale / unavailable /
## unknown / planned / not_connected / derived.

static func build_doors(facts: Dictionary) -> Array:
	var doors: Array = []
	doors.append({
		"id": "omnisynapse",
		"title": "OMNISYNAPSE",
		"state": "not_connected",
		"detail": "Sibling cockpit, NOT a data source. Views: mission, capability, agent/topology, Council, communications, memory, catalogue, integration, history. Its own honesty label, adopted verbatim: NOT CONNECTED — zero independently verified live colony connectors. Checkout present: " + ("yes" if bool(facts.get("omnisynapse_checkout", false)) else "no") + ".",
		"link": "C:/dev/active/OMNISYNAPSE",
	})
	doors.append({
		"id": "gitnexus",
		"title": "GitNexus",
		"state": "unavailable",
		"detail": "Code-graph / impact-analysis MCP (stdio, no HTTP). No org repo (404). Process presence is not yet in the fleet feed's processes block — until it is, the door cannot claim live. " + String(facts.get("gitnexus_note", "process check owed via fleet feed processes block")),
		"link": "",
	})
	var vault_age := String(facts.get("vault_newest_age", "unknown"))
	doors.append({
		"id": "vault",
		"title": "Obsidian vault",
		"state": "unavailable",
		"detail": "Vault present (C:/dev/vault, 5,271 notes). Bridge writes <vault>/Bridge/live/ via vault_bridge.py — but the scheduled task is NOT installed, so the vault is never shown as live-synced. Newest Bridge file: " + vault_age + ".",
		"link": "C:/dev/vault/Bridge/live",
	})
	var pu: Dictionary = facts.get("pu", {})
	var pu_state := "stale" if bool(pu.get("stale", true)) else "live"
	doors.append({
		"id": "pu-queue",
		"title": "PU queue",
		"state": pu_state,
		"detail": "Real file, stale: " + str(pu.get("total", 0)) + " PUs, " + String(pu.get("file_age", "unknown")) + ", API :5002 DOWN. Statuses: " + _counts_text(pu.get("counts", {})) + ". A standing invitation to revive the queue — the stale label is the point.",
		"link": "C:/dev/active/NuSyQ-Hub/data/unified_pu_queue.json",
	})
	doors.append({
		"id": "techniques",
		"title": "Techniques",
		"state": "derived",
		"detail": "DERIVED — no techniques registry exists. Technique content lives inside skills, Kilo_Core/dev docs, and the mission-preflight lane mappings. This view filters skills + docs and cites each card's source.",
		"link": "",
	})
	doors.append({
		"id": "relationships",
		"title": "Relationships",
		"state": "derived",
		"detail": "DERIVED — no relationships service. Edges come from Atlas seats, vault links, and GitHub authorship/review edges (colony-public only). Muse's private people/groups memory is never rendered.",
		"link": "",
	})
	doors.append({
		"id": "cross-references",
		"title": "Cross references",
		"state": "derived",
		"detail": "DERIVED — no cross-references service. Selecting any node shows its cross-refs panel: linked PRs, vault notes, Atlas entries, repos — each a real link, verified at generation time. A claimed link with a missing target renders BROKEN LINK.",
		"link": "",
	})
	return doors


static func _counts_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for status in ["queued", "voting", "approved", "executing", "completed", "failed"]:
		if counts.has(status):
			parts.append(status + " " + str(counts[status]))
	if parts.is_empty():
		return "no counts"
	return ", ".join(parts)


## One-line door summary for the ledger: id + state per door.
static func ledger_line(doors: Array) -> String:
	var parts: PackedStringArray = []
	for door in doors:
		if typeof(door) == TYPE_DICTIONARY:
			parts.append(String(door.get("id", "?")) + " " + String(door.get("state", "unknown")))
	return "DOORS " + " · ".join(parts)
