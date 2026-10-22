# Game reports to highball-db from Proton-ish

Date: 2026-10-22. Status: approved 2026-10-22.

## 1. Intent

Highball's community tracks how games run in [highball-db](https://github.com/gauthierpiarrette/highball-db).
Reports arrive as GitHub issues through its `report.yml` form; the Highball app pre-fills that form after a
session (`PlayReport.url` in HighballKit) so a report costs one click and a rating. Proton-ish bundles the
database and runs games with the same engine, but has no way to report back: the README sends players to the
form by hand, and nothing marks a report as a Proton-ish setup.

Highball's maintainer asked for exactly that mark: "If someone sends a report to highball db from a Proton-ish
setup, could it say Proton-ish in the notes, so we can tell the two apart?" The owner's call: the only
workable path is a button in the app. A player who runs a game through Proton-ish should be able to report it
to highball-db with the facts filled in, as Highball players can.

## 2. Goals

- G1. A **Report to highball-db…** action on a game in the Prefixes screen opens highball-db's report form in
  the browser with every fact Proton-ish knows filled in: title, Steam AppID, engine id, renderer, chip, macOS
  version, Proton-ish and HighballKit versions, and the Proton-ish mark. The player adds the rating and words.
- G2. Every report says it came from Proton-ish, in the field the Highball maintainer agrees to (section 6, D2).
- G3. The form's own field ids are used, so GitHub fills the right inputs, exactly as Highball's link does.

## 3. Non-goals

- A report form on Proton-ish's own repository, or any forwarding of Proton-ish issues to highball-db. The owner
  dropped both: one path, the button.
- Asking the player to report when a session ends. Proton-ish has no hook on a game's exit (Steam owns the
  launch); the button is on demand.
- Reports for CrossOver games. highball-db is Highball's database; a prefix last run by CrossOver shows no
  report action.
- Recording play time. The form's Session field takes a sentence, not a number; Proton-ish puts the mark there.

## 4. Anti-goals

- Sending anything without the player seeing it: the button opens a browser page, the player submits it, under
  their own GitHub account. Proton-ish never posts to GitHub itself.
- Pre-filling Notes. Highball leaves Notes empty on purpose (highball#347: a pre-filled Notes snapped back to
  the pre-filled text when edited); the player's words stay theirs.
- Inventing a rating or a renderer. A fact Proton-ish does not know is left blank for the player.

## 5. Constraints

- The form is `https://github.com/gauthierpiarrette/highball-db/issues/new?template=report.yml` with query
  items named by field id: `title`, `steam_appid`, `rating`, `issues`, `renderer` (dxmt, d3dmetal, dxvk,
  wined3d), `chip`, `macos`, `engine`, `version`, `settings`, `session`, `notes`. Submitting needs a GitHub
  account; the owner accepts that.
- What a prefix knows (`app/Sources/NotProtonApp/Model/PrefixStore.swift`, `PrefixTools.swift`): `appID`,
  `name`, `lastUsed`, and the build record `notproton-build` in the prefix root, whose first line is the build
  the game last ran on (a Highball engine id such as `x64-crossover26.3-r27`, or a CrossOver build).
- The renderer of each launch is in the prefix's `protonish-run.log`: `highball-env` writes
  `highball-env: note: renderer <dxmt|d3dmetal|dxvk|wined3d>` at every launch (`LaunchEnvironment.swift`), already
  in the form's spelling. The `renderer report:` lines from `highball_renderer_report` are not usable: on real
  prefixes they mostly read `empty` or `no version line`.
- Chip and macOS version come from `sysctl -n machdep.cpu.brand_string` and `sw_vers -productVersion`, as
  HighballKit's `Machine` does. The app target does not link HighballKit today (only `highball-env` does);
  it stays that way, the two commands are enough.
- Proton-ish's version is `CFBundleShortVersionString` (`SystemStatus.swift`). The HighballKit version that
  launched a game is in its `protonish-run.log` as `highball-env: highball-env HighballKit <version>`, printed
  from `HighballEnvCore.highballKitVersion`. That constant is stale today (`0.10.15` while `app/Package.swift`
  pins `0.10.22`): `scripts/sync/highball.sh` only rewrites it when it equals the old pin, so one hand bump left
  it behind for good. The app target cannot read the constant (it does not link `HighballEnvCore`).
- highball-db's ingest (`Scripts/ingest-report.py`) keeps `session` as its own field and copies it into the
  record's notes when Notes is empty; it does not store `version` or `settings`.
- Strings are localised: new ones go into `Localizable.xcstrings` with Italian and Simplified Chinese
  translations, in the format `dylib/tests/l10ncheck.py` checks.

## 6. Decided

- D1. The action lives on the game's row in the Prefixes screen, next to Reveal in Finder and the logs, as
  **Report to highball-db…**. It shows only when the prefix's build record names a Highball engine.
- D2. The Proton-ish mark goes in the form's Session field: `Played through Proton-ish (macOS Steam), Highball
  engine <id>.` Highball's ingest stores Session and copies it into the notes when the player leaves Notes
  empty, so the mark reaches the record the maintainer reads, and Notes stays the player's (highball#347). The
  owner tells the maintainer so; there is no Notes fallback. (Spec writer's call after the builder check.)
- D3. `version` is `Proton-ish <app version>, HighballKit <version>`, the HighballKit version taken from the
  last `highball-env HighballKit` line in the game's `protonish-run.log`, so it names the code that actually
  launched the game; without such a line it reads `Proton-ish <app version>`. (The form labels the field
  "Highball version" and the ingest does not store it; it is for the human reader. Spec writer's call.)
- D4. `renderer` is the value of the last `highball-env: note: renderer` line in `protonish-run.log`, when it is
  one of the form's four options; otherwise it is left blank for the player to pick.
- D5. `settings` is left blank. Proton-ish has no per-game settings store of Highball's shape; the launch
  options a player set in Steam are theirs to describe.
- D6. `title` is the prefix's name when Steam's appinfo gave one, otherwise `App <appID>`; `steam_appid` is
  the appID.
- D7. The README's "Reporting problems" and `docs/using-proton-ish.md` mention the button in one line each.
  `docs/using-proton-ish.md` arrives with PR #53; this work starts from `main` once #53 has merged.
- D8. The stale constant is fixed in the same work: `highball.sh` rewrites `highballKitVersion` to the new pin
  whatever its current value, with a `test-sync.sh` case for a constant that has drifted, and the constant is set
  to the pinned `0.10.22`. Otherwise every report would say `HighballKit 0.10.15`. (Spec writer's call.)

## 7. Left to the builder

- Where the URL is assembled (a small `GameReport` type in `app/Sources/NotProtonApp/Model/` is the obvious
  place) and how `PrefixesModel` exposes it to the row; a unit test on the URL's query items as
  `PlayReportTests` does in HighballKit.
- How the last renderer line is read from `protonish-run.log` (it can be large: read from the end) and
  tested with a recorded log excerpt.
- Italian and Simplified Chinese wording for the new strings.

## 8. Success

- A player opens Prefixes, picks a game last run on a Highball engine, clicks **Report to highball-db…**, and
  the browser shows highball-db's form with title, AppID, engine, chip, macOS, version and the Proton-ish mark
  filled in, renderer filled from the last launch. Rating and Notes are empty.
- A game last run on CrossOver has no such action.
- The Highball maintainer can tell a Proton-ish report from a Highball one at a glance.
