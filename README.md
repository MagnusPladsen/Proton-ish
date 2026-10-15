# Proton-ish

Proton-ish lets the macOS Steam client run Windows games through Wine, the way Steam Play and Proton do
on Linux. Pick a Windows game in your normal macOS Steam library, choose a compatibility tool, press Play.

## Quick start

Free setup with Highball's Wine engine; no Highball app needed. Using CrossOver instead? See
[Using CrossOver](#using-crossover).

**You need:** an Apple Silicon Mac with macOS 15 or newer, [Steam for macOS](https://store.steampowered.com/about/)
and Rosetta 2 (macOS offers to install it the first time something needs it, or run
`softwareupdate --install-rosetta`).

1. **Install Proton-ish:** `brew install --cask magnuspladsen/tap/proton-ish`, or download `Proton-ish.zip` from the
   [Releases page](https://github.com/MagnusPladsen/Proton-ish/releases) and move `Proton-ish.app` to Applications.
2. **Open it once.** It is not notarized, so macOS blocks it; go to **System Settings → Privacy & Security** and click
   **Open Anyway**.
3. **Install:** allow **App Management** when macOS asks (Proton-ish modifies the Steam app) and click **Install** on
   the Status screen.
4. **Get the engine:** click **Download…** next to **Highball engine**. Proton-ish shows Apple's licence for D3DMetal
   (DirectX 12): choose **Accept and Download**, or **Download without D3DMetal** if you would rather not. It then
   downloads Highball's Wine 11 engine (about 440 MB, from Highball's releases, checked against Highball's checksums)
   and sets it up. Already using the [Highball](https://github.com/gauthierpiarrette/highball) app? Proton-ish finds
   its `x64-crossover26.3-r19` engine instead; click **Set Up**.
5. **Play:** quit and reopen Steam. If Steam had no default compatibility tool, Highball is now the default for
   Windows games (the **Use Highball for all Windows games** switch on the Status screen), so a Windows-only game
   just shows Play. A game that also has a macOS version runs that version unless you tick **Force the use of a
   specific Steam Play compatibility tool** under its **Properties → Compatibility** and pick **Highball Wine 11 (r19)**.

Updates arrive through **Proton-ish → Check for Updates…** (or `brew upgrade`). Something broken? See
[Reporting problems](#reporting-problems).
## Why Proton-ish exists

[NotProton](https://github.com/NotProtonNot/NotProton) made Steam Play work on macOS, but it only
supports [CrossOver](https://www.codeweavers.com/crossover), which is a paid product. Today there are
good free and open-source Wine runtimes for the Mac, such as [Highball](https://github.com/gauthierpiarrette/highball).
Proton-ish adds support for those, starting with Highball's Wine 11 engine, so nobody has to pay just to
play the Windows games they already own. CrossOver stays fully supported.

If you can afford it, please consider buying CrossOver anyway: CodeWeavers funds most of the Wine
development that every free runtime, Highball included, is built on.

## Thanks

- **[CodeWeavers](https://www.codeweavers.com/)**, for maintaining and funding [Wine](https://www.winehq.org/)
  for decades and publishing CrossOver's sources. Without them there would be no Wine on macOS.
- **[NotProton](https://github.com/NotProtonNot/NotProton)** by NotProtonNot, for the Steam integration,
  the macOS lsteamclient port and steam-shim. Proton-ish is a fork of NotProton; all of that work is theirs.
- **[Highball](https://github.com/gauthierpiarrette/highball)** by Gauthier Piarrette, for a free, open-source
  Wine runtime for Apple Silicon that makes a CrossOver-free setup possible. Proton-ish runs Highball games with
  Highball's own launch code (HighballKit, GPLv3) and its per-game database
  ([highball-db](https://github.com/gauthierpiarrette/highball-db), CC0).
- **[Valve](https://github.com/ValveSoftware/Proton)**, for Proton, lsteamclient and steam_helper.

> Proton-ish is a fork of NotProton and is **not affiliated with or endorsed by** NotProton, Valve,
> CodeWeavers or Highball. See [Reporting problems](#reporting-problems) before filing an issue anywhere.

## Status

Proton-ish is in early development; pre-releases are out (see [Quick start](#quick-start)). Games run through
Highball's free Wine 11 engine (`x64-crossover26.3-r19`) with Highball's own launch setup, so what works in
Highball should work here. Verified so far on an Apple Silicon Mac: Emberward, Among Us (Steam sign-in and the
overlay included). For what Highball's community has tested, see
[highball-db](https://github.com/gauthierpiarrette/highball-db), the compatibility database Proton-ish bundles.

![Emberward running from macOS Steam through Proton-ish and Highball's Wine 11 engine](docs/screenshots/emberward-running-highball.png)

![Steam's Compatibility settings with "Highball Wine 11 (r19)" selected as the compatibility tool](docs/screenshots/steam-compatibility-highball.png)

## Using Highball

The [Quick start](#quick-start) covers it. The engine lives in Highball's standard folder
(`~/Library/Application Support/Highball/engines`), whether Proton-ish downloaded it or the Highball app did, so the
two share it; games use its graphics files from there. Proton-ish never downloads, hosts or modifies D3DMetal on its
own: it is part of Highball's engine bundle and is only used after you accept Apple's licence, in the download sheet
or later through the engine row's **Enable D3DMetal…**.

**Graphics.** Games get the launch environment Highball itself would give them, computed by Highball's own code
(HighballKit), so Highball's fixes arrive with each Proton-ish update:

- **Automatic** (default): Highball's choice for the game from its database
  ([highball-db](https://github.com/gauthierpiarrette/highball-db), bundled), otherwise DXMT.
- **D3DMetal, DXMT, DXVK, WineD3D** in the game's Proton-ish options override it. The list only shows what the engine
  can run: D3DMetal appears once Apple's licence is accepted. WineD3D is a last resort and renders many games wrongly.
- **DirectX 12-only games** (no DirectX 11 fallback) go to D3DMetal on Automatic, as in Highball. Without the licence
  the game stays on DXMT and `protonish-run.log` points to **Enable D3DMetal…**.
- Per-game fixes from highball-db that only set variables, DLL overrides or DXVK options apply automatically.
  Fixes that change the Windows prefix (registry, winetricks) are not applied yet.
- `protonish-run.log` ends with a "renderer report": the Direct3D logs the game wrote, e.g. DXVK's version.

Design and roadmap: [design spec](docs/superpowers/specs/2026-10-14-protonish-highball-design.md).

## Using CrossOver

Follow the [Quick start](#quick-start) but skip step 3 and set up your CrossOver install in step 4 instead.
CrossOver works exactly as in NotProton. Supported: CrossOver 26.3 and the CrossOver Preview builds 20260821 and
20261006. Preview builds come in a Rosetta (x86) and an ARM64 variant; the ARM64 variant offers both a FEX and a
Rosetta compatibility tool. The Status screen shows which of your CrossOver installs can be set up.

A Steam client update can break Proton-ish until Proton-ish catches up; the Status screen has a
**Block Steam client updates** switch if you would rather wait.

Set a default tool under **Steam → Settings → Compatibility**, and override it per game under the game's
**Properties → Compatibility**. A Rosetta tool is the safer default; FEX is worth trying per game.

## Good to know

- **Native macOS versions win.** If a game has a macOS version, Steam installs and runs that. To get the Windows
  version, tick **Force the use of a specific Steam Play compatibility tool** in the game's Compatibility settings
  and pick a tool. Unticking it switches back to the macOS version.
- **No Valve Anti-Cheat.** VAC is not supported (Proton does not support it either). VAC games start in insecure
  mode and cannot join secure matchmaking.

## Reporting problems

Start at [Proton-ish's issues](https://github.com/MagnusPladsen/Proton-ish/issues) with the game's
`protonish-run.log`: the Steam integration, the setup and the launch belong to Proton-ish, even when Highball's
engine does the running. If a problem turns out to be in the engine or a renderer, the issue will say so and
point to the right place:

- A game that also misbehaves in the Highball app: [highball-db](https://github.com/gauthierpiarrette/highball-db)
  collects per-game reports and fixes, which Proton-ish picks up with every update.
- A bug in Highball's engine itself: [Highball's issues](https://github.com/gauthierpiarrette/highball/issues),
  reproduced in the Highball app, since the Highball project does not support Proton-ish setups.

Never report Proton-ish problems to NotProton, CodeWeavers or Valve.

## Changes from upstream

- 2026-10-14: Rebranded to Proton-ish (bundle ID `com.magnuspladsen.protonish`, support
  directory `~/Library/Application Support/protonish/`, tool names `protonish-*`, own update feed).
- 2026-10-14: New app icon (two crossed orbits around a wine drop), replacing upstream's artwork.
- 2026-10-14: Internal groundwork for more Wine runtimes: runners now live in
  `runners/<runtime>-<build>/root/`, and compatibility tools record their runtime. No change for CrossOver users.
- 2026-10-14: Highball support: set up Highball's Wine 11 engine (`x64-crossover26.3-r19`) as a Steam Play compatibility tool.
- 2026-10-14: Steam is signed with a local certificate so it keeps its macOS permissions across updates; Wine's server directory is fixed when another tool left it open.
- 2026-10-14: First pre-release, 0.1.0-beta.1.
- 2026-10-14: 0.1.0-beta.2: the signing certificate moves to Proton-ish's own keychain, so installing no longer asks for your password.
- 2026-10-14: "Check for Updates" works for pre-releases (fixed feed address). Releases are published automatically when a version is merged into main.
- 2026-10-15: README rewritten in Proton-ish's own words; the copied NotProton README text is gone, and NotProton's thanks to earlier projects are kept, clearly attributed.
- 2026-10-15: README starts with a single Quick start, from installing Proton-ish to pressing Play.
- 2026-10-15: Highball games run with Highball's own launch environment (HighballKit 0.10.15): the Graphics choice
  works (D3DMetal, DXMT, DXVK, WineD3D), Automatic follows highball-db, and highball-db's environment fixes apply.
  New `highball-env` helper; the run log reports which renderer served the game. Synced with NotProton `dae593c`.
- 2026-10-15: 0.1.0-beta.3: Highball graphics choice and per-game fixes, renderer report, NotProton console-output fix.
- 2026-10-15: Proton-ish downloads Highball's engine itself (Highball's own installer, Apple's licence shown first); the Highball app is optional.
- 2026-10-15: "Use Highball for all Windows games" sets Steam's default tool; on by itself only when Steam had none.
- 2026-10-15: DirectX 12-only games go to D3DMetal on Automatic; the Graphics list shows only what the engine can run.
- 2026-10-15: Steam keeps its Accessibility permission across installs (the grant was reset on every install before).
- 2026-10-15: README: Status reflects Highball's game support, "Reporting problems" says where to report what.
- 2026-10-15: 0.1.0-beta.4: engine download from Proton-ish, default tool for all Windows games, DirectX 12 games on D3DMetal, Accessibility kept across installs.

## What Install changes

- **Steam app:** Proton-ish adds its Steam Play code to Steam and re-signs it, which is why it needs App Management.
- **Signing certificate:** the first install creates a "Proton-ish Local Signing" certificate in Proton-ish's own
  keychain (`~/Library/Application Support/protonish/signing.keychain-db`) and signs Steam with it, so Steam keeps
  its Accessibility permission across Proton-ish installs and updates. No password prompt: Proton-ish holds that
  keychain's password.
- **Steam's default tool:** the **Use Highball for all Windows games** switch sets Steam's default compatibility tool
  (what Steam's own Compatibility settings call the default). It turns itself on only when Steam had no default; a
  CrossOver or other default is never replaced. Applies at the next Steam start.
- **Not notarized:** notarizing needs a paid Apple developer account, hence the Open Anyway step.
- **Undo:** **Remove Everything** in Proton-ish restores Steam and deletes the support folder and the keychain
  (`brew uninstall --zap --cask proton-ish` does the same).

## Building from source

- Xcode 27 (the same toolchain upstream CI uses); older Xcode versions fail to type-check the app.
- `brew install shellcheck node` for the lint and panel checks.
- `make dobby && make all && make app-tests` builds the dylib and runs the Swift tests;
  `make bridge fonts app` builds the full `out/Proton-ish.app` (the bridge step compiles a Wine tree and takes a while).
- `make brandcheck` must stay clean: it fails if an upstream NotProton identifier slips back in.

### Source layout

- `app/`: the macOS app (SwiftUI) that sets everything up.
- `dylib/`: the code injected into Steam that enables Steam Play and adds the compatibility tools.
- `lsteamclient/`: Valve's lsteamclient, ported to macOS, so Windows games can talk to the macOS Steam client.
- `steam-shim/`: Valve's steam_helper from Proton 9.0, ported.
- `ntdll-patch/`: patches each runner's copy of Wine (in `~/Library/Application Support/protonish/runners/`) so it
  loads lsteamclient.

## Contributing and license

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Licensing is described in
[NOTICE](NOTICE).

## Earlier projects, as credited by NotProton

NotProton's README thanks earlier projects with similar goals, noting that NotProton was not built on their work.
Proton-ish passes those thanks on:

- [Kaon](https://github.com/natbro/kaon) by [Nat Brown](https://github.com/natbro).
- [Neutron](https://github.com/mont127/Neutron) by mont127, a similar idea implemented differently.
- [Gio](https://github.com/giodotblue), who worked on enabling Steam Play in macOS Steam before NotProton was released.

The original NotProton README is at https://github.com/NotProtonNot/NotProton#readme.
