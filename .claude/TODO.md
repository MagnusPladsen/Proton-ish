# Project TODOs

## High Priority
## Medium Priority
- [x] Version ordering: pre-release-aware VersionOrder replaces String.compare(.numeric) (completed: 2026-10-15)
- [x] CrossOver row lists Highball's "r19" in "Supported:" (SupportedRunners.versionList includes Highball builds) (completed: 2026-10-16)
- [ ] Highball parity for Steam games: every game that works in Highball should work here (added: 2026-10-14)
  - [x] M2b: Highball's own launch environment via HighballKit (highball-env): Graphics choice, Automatic from highball-db, environment-only recipe steps, renderer report (completed: 2026-10-15)
  - M2c: apply highball-db recipe steps that change the prefix (registry, winetricks, winver, copy, file, installer)
  - [x] M2d also: hide renderers in the Graphics dropdown that the engine can't run (completed: 2026-10-15)
  - [x] Import per-game fixes from highball-db (CC0): bundled snapshot, renderer and environment-only steps (M2b); prefix steps in M2c
  - Track a compatibility list (game, engine revision, result) in the README or a docs page
- [x] M2d: Proton-ish installs the Highball engine itself with HighballKit's EngineStore.install (Highball's release URLs, sha256-checked; D3DMetal only after the user accepts Apple's licence in Proton-ish), so users no longer need the Highball app. After M2b's run-script task, before the Reddit post (added: 2026-10-15)
  - [x] Also: a "Use Highball for all Windows games" switch that sets Steam's default compatibility tool (CompatToolMapping app 0 in config.vdf, Steam stopped), so no per-game tool choice (user decision 2026-10-15)
  - [x] Automatic should send DirectX 12-only games to D3DMetal like Highball (ProgramNeeds from the game's exe; pass the exe to highball-env)
- [x] Remove Everything clears Steam's default tool when it is ours (SteamCompatConfig, config.vdf edited while Steam is stopped) (completed: 2026-10-15)
- [x] Upstream sync automation (plan: docs/superpowers/plans/2026-10-15-upstream-sync-automation.md), after M2b; needs a SYNC_TOKEN PAT (completed: 2026-10-15)

## Low Priority / Future
- [ ] Reach out to Highball after the beta has testers: stable engine manifest, steamclient patch in highball-engine, shared compat data (added: 2026-10-14)

## Completed
- [x] Safeguard for /tmp/.wine-<uid> with too-open permissions (completed: 2026-10-14)
- [x] Keep Steam's Accessibility permission across installs with a local signing identity (completed: 2026-10-14)
- [x] Decided to keep the name Proton-ish; no rename for now (completed: 2026-10-14)
