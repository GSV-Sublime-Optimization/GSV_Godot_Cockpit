# REVIEW OPERATIONS / Exact-Head PR Admission Gate

[Msg⛛{GSV-HOLODIVE-REVIEW-OPERATIONS-20261108}]
Owning lane: GPT-6 Colony Workstation draft #20. Source-only, not a scheduler.

## Purpose and use

The previous workstation could inspect Studio missions, but not answer "Which PR can safely move next, and what is the single best unblock?" Reviewing dozens of unprioritized GitHub tabs consumes tokens and engineering time. Review Operations adds a small, repeatable, queryable source instrument.

On MSI with GitHub CLI authenticated to the permitted organization:
1. Double-click EXPORT_REVIEW_QUEUE.cmd. Its explicit read-only Python exporter writes a TTL-bound, sanitized report to LOCALAPPDATA/GSV_Cockpit/review_queue.json.
2. In Godot Play Project, open REVIEW OPS (F8), then RELOAD LOCAL SOURCE.
3. From HOLO DIVE, select PR REVIEW GATE (key 8 when the viewport has focus). Pick a numbered gate; its inspector shows exact SHA, CI, blockers and advisory review lane. OPEN SOURCE / EVIDENCE navigates to the review surface, not a shell.
4. The Review Operations desk offers PR search, sequential NEXT, verified GitHub URL, and COPY EXACT-HEAD REVIEW BRIEF. Each brief contains a bounded source identity, blockers, actor candidate if actually observed, and the need for a fresh official GSV merge dry-run.

The exporter uses subprocess arguments without a shell, bounded output/time, no token/GitHub write calls, and atomic local output. It reads up to 48 open PRs, detailed metadata for up to 20, and emits schema gsv.review-operations.v1 (128 KiB cap, 300-second TTL). Missing source details are UNOBSERVED, never falsely called missing provenance. The original GSV engineering-actor review and merge admission gate are the final authority, not this renderer.

The source-backed 3D gate renders up to 16 detailed PRs on a distinct altitude ring, and only the top six in ALL DOMAINS to avoid overload. Each is a recognizable admission gate, not an agent or generic light. Failed checks are red; draft/needs-review states amber; candidates needing a new exact-head gate recheck blue. Full reasons appear in the inspector. No geometric relation is invented between a GitHub repo slug and an observed Studio local folder.

## Sequential actor routing

Agent routing is advisory. Without a separately fresh observed actor capacity source, every result says UNOBSERVED / NOT ASSIGNED. An optional availability file has schema gsv.actor-availability.v1, generated_utc within ten minutes, and one record per agent/<actor> with available state, can_review true, observed UTC within five minutes, explicit max_concurrent, active and skills. Supply it via the Python collector's --availability option. The algorithm assigns candidate slots sequentially in priority order but never POSTs, grants authority or automatically sends a task.

GitHub's authenticated account is NOT the GSV engineering-actor identity; actor independence must be checked by the GSV gate. Existence of a provenance block does not automatically make its contents truthful. Exact HEAD and current owner permissions must be reverified for any execution.

## Observed MSI proof

A read-only collection on November 8, 2026 sampled 32 open PRs and fetched detailed metadata for 16. Native Godot 4.7.2 loaded the source, displayed 16 3D review gate identities and opened exact-head data with WORKSTATION_REVIEW_LIVE_PASS. RTX 5070 visual capture was saved locally under receipts/review-gate-live-msi.png. This is not a fixture proving other fleet health. The installed Studio /api/entity/bodies endpoint was unavailable, despite its source PR being merged; the cockpit must keep unknown body facts unknown.

## Resource model

- One opt-in GitHub collection; Godot reads local data, not continuous cloud polling.
- 300-second TTL and fail-closed invalid schema/URL, duplicate PR, authorisation, head or future timestamp.
- The 3D renderer shows a bounded subset; full short queue stays in the review instrument.
- Work packets traverse actual verified project-to-RUNNING-mission edges only. Unobserved or awaiting-approval nodes do not pretend to work.
- Static SubViewport invalidates once; source-running packets and explicit cinematic motion update at a bounded cadence (~12 Hz), camera dive up to ~30 Hz. Measured CPU/VRAM/fps is still a separate release gate.
- A short typed context capsule replaces re-reading huge threads.

## Cross-project opportunities and boundaries

- GPT-6 Living Colony #28 offers an opt-in source-present tool atlas and object finder. It is stacked on #20 and should rebase on this PR review gate.
- Muse Alive Room #30 has event-driven observations plus PR/PU suggestions. Compare actual output and read semantics before merging its representations with this review queue.
- OmniSynapse, GitNexus, Obsidian/Second Brain, PU queue, skills, plugins, connectors and agent toolchains need provider-owned read adapters reporting installed, callable, authenticated, qualified and admitted independently. A checked-out source tree is not a connected tool. The review collector does not open private vaults, import plugin tokens or start services.

## Not yet proven

No agent is scheduled by the hologram, no PR approved or merged by export, no protected default branch changed, no PTY or OAuth bridge created. Real cross-app sync, 720p human accessibility, physical idle CPU/GPU sampling and the Studio worktree-to-running-game artifact loop remain separate acceptance gates.
