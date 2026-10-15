# Proton-ish

Proton-ish lets the macOS Steam client run Windows games through Wine, the way Steam Play and Proton do
on Linux. Pick a Windows game in your normal macOS Steam library, choose a compatibility tool, press Play.

## Quick start

Free setup with Highball's Wine engine. Using CrossOver instead? See [Using CrossOver](#using-crossover).

**You need:** an Apple Silicon Mac with macOS 15 or newer, [Steam for macOS](https://store.steampowered.com/about/)
and Rosetta 2 (macOS offers to install it the first time something needs it, or run
`softwareupdate --install-rosetta`).

1. **Install Proton-ish:** `brew install --cask magnuspladsen/tap/proton-ish`, or download `Proton-ish.zip` from the
   [Releases page](https://github.com/MagnusPladsen/Proton-ish/releases) and move `Proton-ish.app` to Applications.
2. **Open it once.** It is not notarized, so macOS blocks it; go to **System Settings → Privacy & Security** and click
   **Open Anyway**.
3. **Get the Wine engine:** install [Highball](https://github.com/gauthierpiarrette/highball), open any environment's
   settings and set **Advanced → Engine** to `x64-crossover26.3-r19` (Wine 11). Highball downloads it. Wine 10
   engines do not work yet.
4. **Set up Proton-ish:** allow **App Management** when macOS asks (Proton-ish modifies the Steam app), click
   **Install** on the Status screen, then **Set Up** next to the engine in the Highball section.
5. **Play:** quit and reopen Steam. In a Windows game's **Properties → Compatibility**, tick **Force the use of a
   specific Steam Play compatibility tool**, pick **Highball Wine 11 (r19)** and press Play.

Updates arrive through **Proton-ish → Check for Updates…** (or `brew upgrade`). Something broken? Open an
[issue](https://github.com/MagnusPladsen/Proton-ish/issues) and attach the game's `protonish-run.log`.

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
> CodeWeavers or Highball. Please report Proton-ish problems at
> https://github.com/MagnusPladsen/Proton-ish/issues, never to those projects.

## Status

Proton-ish is in early development; pre-releases are out (see [Quick start](#quick-start)). Highball
support works: a Windows game (Emberward) launched from the macOS Steam client through Highball's free Wine 11
engine (`x64-crossover26.3-r19`) on an Apple Silicon Mac, with Steam sign-in and the overlay working. That is one
game on one Mac so far; expect rough edges.

![Emberward running from macOS Steam through Proton-ish and Highball's Wine 11 engine](docs/screenshots/emberward-running-highball.png)

![Steam's Compatibility settings with "Highball Wine 11 (r19)" selected as the compatibility tool](docs/screenshots/steam-compatibility-highball.png)

## Using Highball

The [Quick start](#quick-start) covers it. Keep Highball installed: Proton-ish sets up its engine from
Highball's copy and uses Highball's graphics files.

**Graphics.** Games get the launch environment Highball itself would give them, computed by Highball's own code
(HighballKit), so Highball's fixes arrive with each Proton-ish update:

- **Automatic** (default): Highball's choice for the game from its database
  ([highball-db](https://github.com/gauthierpiarrette/highball-db), bundled), otherwise DXMT.
- **D3DMetal, DXMT, DXVK, WineD3D** in the game's Proton-ish options override it. D3DMetal needs Apple's licence
  accepted in Highball (an environment's **Graphics → Review licence…**); without it the game runs on DXMT and
  `protonish-run.log` says why. WineD3D is a last resort and renders many games wrongly.
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
- 2026-10-15: Upstream sync workflow: NotProton merges, Highball pin and highball-db bumps as PRs, new engine builds as issues.

## What Install changes

- **Steam app:** Proton-ish adds its Steam Play code to Steam and re-signs it, which is why it needs App Management.
- **Signing certificate:** the first install creates a "Proton-ish Local Signing" certificate in Proton-ish's own
  keychain (`~/Library/Application Support/protonish/signing.keychain-db`) and signs Steam with it, so Steam keeps
  its Accessibility permission across Proton-ish updates. No password prompt: Proton-ish holds that keychain's
  password.
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

## Maintenance

A daily workflow (`.github/workflows/upstream-sync.yml`, also on demand under Actions) keeps the fork current:

- **NotProton:** a new upstream commit becomes a PR that merges it into main, or an issue listing the conflicting
  files when the merge is not clean.
- **Highball:** a new Highball release bumps the HighballKit pin, and a new highball-db commit refreshes the bundled
  snapshot, in one PR.
- **Highball engines:** a new engine build becomes an issue with the steps to support it.

Nothing merges or releases by itself; the PRs run the normal checks and never touch `dylib/version.h`. The workflow
needs a repository secret `SYNC_TOKEN`: a fine-grained GitHub token for this repository only, with Contents,
Pull requests, Issues and Workflows set to read and write, so that CI runs on the PRs it opens. When the token
expires the workflow skips with a notice until it is renewed. Run the scripts' tests with `make synccheck`.

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
