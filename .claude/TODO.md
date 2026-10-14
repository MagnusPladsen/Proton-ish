# Project TODOs

## High Priority
## Medium Priority
- [ ] Highball parity for Steam games: every game that works in Highball should work here (added: 2026-10-14)
  - M2b: map the in-Steam graphics panel to Highball's renderers (DXMT, D3DMetal when the Apple licence is accepted, DXVK, vkd3d) per game
  - Import per-game fixes from highball-db (CC0): renderer, DLL overrides, env vars, Windows version, keyed by Steam app id
  - Track a compatibility list (game, engine revision, result) in the README or a docs page

## Low Priority / Future
- [ ] Reach out to Highball after the beta has testers: stable engine manifest, steamclient patch in highball-engine, shared compat data (added: 2026-10-14)

## Completed
- [x] Safeguard for /tmp/.wine-<uid> with too-open permissions (completed: 2026-10-14)
- [x] Keep Steam's Accessibility permission across installs with a local signing identity (completed: 2026-10-14)
- [x] Decided to keep the name Proton-ish; no rename for now (completed: 2026-10-14)
