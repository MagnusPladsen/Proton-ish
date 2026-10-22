# Game Reports to highball-db Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A **Report to highball-db…** action on a Highball game in the Prefixes screen opens highball-db's report form pre-filled, marked as Proton-ish.

**Architecture:** A pure `GameReport` type builds the form URL from facts the app gathers (the prefix, its build record, the tail of its `protonish-run.log`, the Mac). `PrefixesModel` exposes it, `PrefixesView` shows it in the row's context menu, and the URL opens in the browser. The stale `highballKitVersion` constant and the sync script that should keep it current are fixed first, since the report quotes the version the launch log prints.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing, POSIX sh (`scripts/sync`), `Localizable.xcstrings`.

**Spec:** `docs/superpowers/specs/2026-10-22-game-report-design.md`

## Global Constraints

- Form: `https://github.com/gauthierpiarrette/highball-db/issues/new` with `template=report.yml`; query items by field id: `title`, `steam_appid`, `renderer`, `chip`, `macos`, `engine`, `version`, `session`. Never `rating`, `issues`, `settings` or `notes`.
- Session text, exactly: `Played through Proton-ish (macOS Steam), Highball engine <engine id>.`
- Version text: `Proton-ish <app version>, HighballKit <version>`, or `Proton-ish <app version>` when the log names no HighballKit.
- Renderer: one of `dxmt`, `d3dmetal`, `dxvk`, `wined3d`, from the last `highball-env: note: renderer <value>` line; anything else leaves it out.
- The action exists only for a prefix whose build record names a Highball engine. Proton-ish never posts to GitHub; the browser opens the form and the player submits it.
- The `NotProtonApp` target keeps its dependencies (Sparkle only); no HighballKit link.
- New user-visible strings go into `Localizable.xcstrings` with `translated` Italian and Simplified Chinese entries; `make l10ncheck` stays clean. The form's own text (session, version) is English and not localised.
- Execution starts from `main` after PR #53 has merged (it brings `docs/using-proton-ish.md`).

## Review Focus

1. A `protonish-run.log` grown over months of launches: only its tail is read, and the menu opens without a stall.
2. A prefix last run through CrossOver whose log still holds old `highball-env` lines: no report action (the build record decides, not the log).
3. A title with `&`, `#`, `+`, quotes or non-ASCII (`Café ☕ & Co #2`): the form shows it exactly.
4. A missing or unreadable `protonish-run.log`: the form still opens, renderer left out, version `Proton-ish <app version>`.
5. A build record naming a Highball engine this Proton-ish no longer lists (`x64-crossover26.3-r12`): still reportable, since the engine id is Highball's.

---

### Task 1: Keep `highballKitVersion` in step with the pin

**Files:**
- Modify: `scripts/sync/highball.sh` (the `highballKitVersion` sed), `app/Sources/HighballEnvCore/HighballEnvCore.swift:6`
- Test: `scripts/sync/test-sync.sh` ("Highball: pin and database" section)

- [ ] **Step 1: Write the failing test.** In `test-sync.sh`, after the existing "a newer Highball release opens a PR" case, add a case: `hb 0.10.15 aaaaaaa1111`; then in `$work/hb` overwrite `app/Sources/HighballEnvCore/HighballEnvCore.swift` with `public static let highballKitVersion = "0.10.1"` (drifted), commit it and `git push -q origin main` (the script branches from `origin/main`); `printf 'v0.10.16\n' > "$STUB_DIR/releases"`; `runhb`. Assert:
  `is "a drifted HighballKit constant follows the pin" 'public static let highballKitVersion = "0.10.16"' "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:app/Sources/HighballEnvCore/HighballEnvCore.swift)"`.
- [ ] **Step 2:** `make -s synccheck`. Expected: FAIL on that check (the constant stays `0.10.1`).
- [ ] **Step 3:** Change the sed to replace any value: `s/highballKitVersion = "[^"]*"/highballKitVersion = "$newer_kit"/`. Set the constant in `HighballEnvCore.swift` to `"0.10.22"` (the pin in `app/Package.swift`).
- [ ] **Step 4:** `make -s synccheck && make -s scriptcheck`. Expected: PASS.
- [ ] **Step 5:** Commit `Keep highballKitVersion in step with the HighballKit pin`.

### Task 2: `GameReport`, the form URL from a prefix's facts

**Files:**
- Create: `app/Sources/NotProtonApp/Model/GameReport.swift`
- Test: `app/Tests/NotProtonAppTests/GameReportTests.swift`

**Interfaces:**
- Produces, in `GameReport.swift`:
  - `struct GameReport: Sendable, Equatable { let title: String; let appID: String; let engine: String; let renderer: String?; let kitVersion: String?; let appVersion: String; let chip: String; let macOS: String }`
  - `var url: URL` — the form URL (Global Constraints).
  - `static func isHighballEngine(_ build: String) -> Bool` — true for the engine-id shape `<arch>-<line>-r<N>` (`x64-crossover26.3-r27`, `arm64-wine11.18-r6`), false for CrossOver builds (`26.3.0.41073`) and empty strings.
  - `struct LaunchFacts: Equatable { var renderer: String?; var kitVersion: String? }` and `static func lastLaunch(inLog text: String) -> LaunchFacts` — the last `highball-env: note: renderer <x>` line (kept only when `x` is one of the four) and the last `highball-env: highball-env HighballKit <v>` line.
  - `static func make(for prefix: WinePrefix, record: PrefixBuildRecord?, appVersion: String, chip: String = Machine.chip, macOS: String = Machine.macOS, log: URL? = nil) -> GameReport?` — nil unless `record` names a Highball engine; `title` is `prefix.title`; `log` defaults to `PrefixLog.launch`'s path for the prefix; reads at most the last 1 MiB of it; a missing or unreadable log gives an empty `LaunchFacts`.
  - `enum Machine { static var chip: String; static var macOS: String }` in the same file: `sysctlbyname("machdep.cpu.brand_string")` (fallback `unknown chip`), and `ProcessInfo.processInfo.operatingSystemVersion` as `major.minor`, plus `.patch` when non-zero.

- [ ] **Step 1: Write the failing tests** (`@Suite("Game report")`), reading `url`'s query items into a `[String: String]`:
  - `"The form gets every fact by its field id"`: a report for `Emberward`/`2459550`/`x64-crossover26.3-r27`/`dxmt`/`0.10.22`/`1.0.5`/`Apple M1 Pro`/`26.6.2` gives `template=report.yml`, `title=Emberward`, `steam_appid=2459550`, `engine=x64-crossover26.3-r27`, `renderer=dxmt`, `chip=Apple M1 Pro`, `macos=26.6.2`, `version=Proton-ish 1.0.5, HighballKit 0.10.22`, `session=Played through Proton-ish (macOS Steam), Highball engine x64-crossover26.3-r27.`, and the host/path of the form.
  - `"Rating, issues, settings and notes stay the player's"`: none of those four keys is present.
  - `"Without a renderer or HighballKit version those are left out or shortened"`: no `renderer` key; `version=Proton-ish 1.0.5`.
  - `"A title keeps its punctuation"`: `Café ☕ & Co #2` round-trips exactly through the query items (Review Focus 3).
  - `"The last launch's renderer and HighballKit win"`: a log excerpt with two launches (`highball-env: highball-env HighballKit 0.10.15` / `highball-env: note: renderer dxvk`, then `... 0.10.22` / `... renderer dxmt`) gives `dxmt` and `0.10.22`.
  - `"A renderer the form does not offer is left out"`: `highball-env: note: renderer metalfx` gives `renderer == nil`.
  - `"Only Highball engine ids count"`: `isHighballEngine` true for `x64-crossover26.3-r27`, `x64-crossover26.3-r12`, `arm64-wine11.18-r6`; false for `26.3.0.41073`, `99.0.0.12345`, `""`.
  - `"A CrossOver prefix has no report, whatever its log says"`: `make` with record build `26.3.0.41073` and a log full of `highball-env` lines returns nil (Review Focus 2).
  - `"A Highball engine no longer listed is still reported"`: record `x64-crossover26.3-r12` returns a report with that engine (Review Focus 5).
  - `"A missing log still gives a report"`: `log` pointing at a nonexistent file gives `renderer == nil`, `kitVersion == nil` (Review Focus 4).
  - `"Only the end of a long log is read"`: a temp log of 3 MiB of filler followed by `highball-env: note: renderer d3dmetal` gives `d3dmetal`, and one where the only renderer line sits in the first MiB followed by 2 MiB of filler gives nil (Review Focus 1).
  - `"The Mac's facts are filled in"`: `Machine.chip` is non-empty; `Machine.macOS` matches `^\d+\.\d+(\.\d+)?$`.
- [ ] **Step 2:** `cd app && swift test --filter GameReport`. Expected: FAIL to compile (`GameReport` undefined).
- [ ] **Step 3:** Implement the interfaces above with `URLComponents`/`URLQueryItem` (as HighballKit's `PlayReport` does) and a `FileHandle` seek to `max(0, size - 1 MiB)` for the log.
- [ ] **Step 4:** `cd app && swift test --filter GameReport`. Expected: PASS.
- [ ] **Step 5:** Commit `Build highball-db report links from a prefix's facts`.

### Task 3: The Prefixes action

**Files:**
- Modify: `app/Sources/NotProtonApp/PrefixesModel.swift`, `app/Sources/NotProtonApp/Views/PrefixesView.swift` (`actions(for:)`, after **Open Log**), `app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings`
- Test: `app/Tests/NotProtonAppTests/PrefixesModelTests.swift`

**Interfaces:**
- Consumes: Task 2's `GameReport.make(for:record:appVersion:)`, `GameReport.url`.
- Produces, on `PrefixesModel`: `func report(for prefix: WinePrefix) -> GameReport?` (from `records[prefix.id]` and `AppVersion.bundled`) and `func sendReport(for prefix: WinePrefix)` (opens `url` with `NSWorkspace.shared.open`).

- [ ] **Step 1: Write the failing tests** in `PrefixesModelTests.swift`, using the suite's existing fixtures for a loaded model:
  - `"A Highball prefix offers a report"`: a prefix whose build record is `x64-crossover26.3-r27` gives a non-nil `report(for:)` with that engine.
  - `"A CrossOver prefix offers none"`: build record `26.3.0.41073` gives nil.
  - `"A prefix with no build record offers none"`: nil.
- [ ] **Step 2:** `cd app && swift test --filter PrefixesModel`. Expected: FAIL to compile.
- [ ] **Step 3:** Implement both model methods. In `actions(for:)`, inside `if let prefix = single(ids)`, after the **Open Log** menu: `if model.report(for: prefix) != nil { Button("Report to highball-db…") { model.sendReport(for: prefix) } }`. Add the catalog entry `Report to highball-db…`: it `Segnala a highball-db…`, zh-Hans `报告到 highball-db…`, both `translated`, in the format `make l10ncheck` expects.
- [ ] **Step 4:** `cd app && swift test --filter PrefixesModel && swift build --package-path . -c release` then (repo root) `make -s l10ncheck`. Expected: PASS, l10ncheck lists no new problem.
- [ ] **Step 5:** Commit `Offer a highball-db report on Highball games in Prefixes`.

### Task 4: Docs, release line and the full check

**Files:**
- Modify: `README.md` ("Reporting problems"), `docs/using-proton-ish.md` ("Highball's engine"), `dylib/version.h` and README changelog via `scripts/sync/bump-release.sh`

- [ ] **Step 1:** README "Reporting problems": add one sentence before the issue link: `Played a Highball game? Right-click it in **Prefixes** and choose **Report to highball-db…**: the form opens in your browser with the game, engine and Mac filled in, marked as Proton-ish.` `docs/using-proton-ish.md`, end of "Highball's engine": the same sentence, adapted ("How a game ran is worth a report: …").
- [ ] **Step 2:** Run `make -s brandcheck synccheck scriptcheck` and `cd app && swift test --filter 'GameReport|PrefixesModel'`. Expected: all clean. A full `make app-tests` on a machine without Dobby and the Wine bridge built fails the same 46 checks as `main` ("appinfo tool", "Install payload", "Steam installer"); compare against `main` rather than reading those as regressions.
- [ ] **Step 3:** Real check: build the app (`make app`, or run the debug build), open Prefixes, right-click a Highball game, choose the action, and read the browser's form: title, AppID, engine, renderer, chip, macOS, version and Session filled; Rating and Notes empty. Right-click a CrossOver game, if one exists: no action.
- [ ] **Step 4:** `sh scripts/sync/bump-release.sh "Games run through Highball can be reported to highball-db from Prefixes (Report to highball-db…), pre-filled and marked as Proton-ish. The HighballKit version in launch logs is right again."`
- [ ] **Step 5:** Commit the docs (`Mention the highball-db report in the README and docs`), push, open the PR.
