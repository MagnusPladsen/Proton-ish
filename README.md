# Proton-ish

Proton-ish lets the macOS Steam client run Windows games through Wine, the way Steam Play and Proton do
on Linux. Pick a Windows game in your normal macOS Steam library, choose a compatibility tool, press Play.
It runs games with [Highball](https://github.com/gauthierpiarrette/highball)'s free Wine engine or with
[CrossOver](https://www.codeweavers.com/crossover).

## Use CrossOver if you can

Proton-ish is free, and so is Highball's engine. The Wine underneath them is not free to make.
[CodeWeavers](https://www.codeweavers.com/) employs most of the people who work on
[Wine](https://www.winehq.org/) and funds nearly all of the Wine work for macOS. Highball's engine is built
from the CrossOver sources CodeWeavers publishes, so most of what runs your game in a free engine is CodeWeavers'
work with the price tag removed. Sales of CrossOver pay for that work. Without a healthy CodeWeavers there is no Wine on the
Mac, and Wine in general loses its largest contributor.

So: if you can, buy CrossOver and use it in Proton-ish. It gives the best support and performance, and it
keeps the work funded. If you cannot, play on with Highball's engine, and come back to this when you can.
The app says the same once on first launch, and again under **Help → Why Buy CrossOver** whenever you want it.

## Quick start

[CrossOver](https://www.codeweavers.com/crossover) gives the best support and performance, and buying it funds
Wine on the Mac; if you have it or can get it, follow [Using CrossOver](#using-crossover). Highball's Wine
engine is the free alternative, and the steps below set it up; no Highball app needed.

**You need:** an Apple Silicon Mac with macOS 15 or newer, [Steam for macOS](https://store.steampowered.com/about/)
and Rosetta 2 (macOS offers to install it the first time something needs it, or run
`softwareupdate --install-rosetta`).

1. **Install Proton-ish:** `brew install --cask magnuspladsen/tap/proton-ish`, or download `Proton-ish.zip` from the
   [Releases page](https://github.com/MagnusPladsen/Proton-ish/releases) and move `Proton-ish.app` to Applications.
2. **Open it once.** It is not notarized, so macOS blocks it; go to **System Settings → Privacy & Security** and click
   **Open Anyway**. The first launch opens with the note on who funds Wine; read it and click **Continue**.
3. **Install:** allow **App Management** when macOS asks (Proton-ish modifies the Steam app) and click **Install** on
   the Status screen.
4. **Get the engine:** click **Download…** next to **Highball engine**. Proton-ish shows Apple's licence for D3DMetal
   (DirectX 12): choose **Accept and Download**, or **Download without D3DMetal** if you would rather not. It then
   downloads Highball's Wine 11 engine (about 440 MB, from Highball's releases, checked against Highball's checksums)
   and sets it up. Already using the [Highball](https://github.com/gauthierpiarrette/highball) app? Proton-ish finds
   its engine instead when it is a supported one (`x64-crossover26.3-r27`, r26, r25 or r19); click **Set Up**.
5. **Play:** quit and reopen Steam. If Steam had no default compatibility tool, Highball is now the default for
   Windows games (the **Use Highball for all Windows games** switch on the Status screen), so a Windows-only game
   just shows Play. A game that also has a macOS version runs that version unless you tick **Force the use of a
   specific Steam Play compatibility tool** under its **Properties → Compatibility** and pick **Highball Wine 11 (r27)**.

Updates arrive through **Proton-ish → Check for Updates…** (or `brew upgrade`). Something broken? See
[Reporting problems](#reporting-problems).
## Why Proton-ish exists

[NotProton](https://github.com/NotProtonNot/NotProton) made Steam Play work on macOS on top of
[CrossOver](https://www.codeweavers.com/crossover). Proton-ish puts
[Highball](https://github.com/gauthierpiarrette/highball)'s free Wine engine into that same Steam integration,
so the games Highball runs can be played from the Steam library with Steam's own launch flow, Steam Cloud and
controller support, and so one app covers both engines. CrossOver stays fully supported and gives the best
results; see [Use CrossOver if you can](#use-crossover-if-you-can) for why that matters.

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
Highball's free Wine 11 engine (`x64-crossover26.3-r27`; r26 with D3DMetal 4 beta 3 on macOS 27, r25 and r19 still
supported) with Highball's own launch setup, so what works in
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
- Per-game fixes from highball-db apply automatically: variables, DLL overrides and DXVK options at every launch;
  registry values, config files and engine DLLs once per prefix per database version, before the first launch
  (Portal 2's `autoexec.cfg`, Warframe's launcher override). A fix is never undone when a later database drops it;
  rebuild the prefix for a clean slate. Installers and winetricks steps (`.NET` for Assetto Corsa) are not applied yet.
- **Fixes verified on another engine.** highball-db says which Wine engine a fix was checked on. By default a fix
  checked on another engine line still applies, and `protonish-run.log` says so. The switch **Apply game fixes verified
  on other engines** in the Status screen turns that off; one game can override the switch with the Steam launch option
  `PROTONISH_RECIPE_OTHER_ENGINES=0` or `=1`.
- `protonish-run.log` ends with a "renderer report": the Direct3D logs the game wrote, e.g. DXVK's version.

**Saves.** Highball's Wine names the Windows user after your Mac user, so Proton-ish links that name to
`steamuser`, the profile Steam reads and syncs with Steam Cloud, the way NotProton links CrossOver's `crossover`.
A prefix built before this (beta.4 and earlier saved under the Mac user's name) is brought over on its next launch:
files move into `steamuser`, of two differing copies the newer wins, and the loser stays in `<user> BACKUP` next to
it. Links Wine made to your Mac folders (Documents, Downloads, …) are dropped, never followed.

Design and roadmap: [design spec](docs/superpowers/specs/2026-10-14-protonish-highball-design.md).

## Using CrossOver

Follow the [Quick start](#quick-start), but in step 4 click **Set Up** next to your CrossOver install instead of
downloading Highball's engine.
CrossOver works exactly as in NotProton. Supported: CrossOver 26.3 and the CrossOver Preview builds 20260821,
20261006 and 20261015. Preview builds come in a Rosetta (x86) and an ARM64 variant; the ARM64 variant offers both a FEX and a
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
- **No NTFS.** Games on an NTFS volume (third-party NTFS drivers included) are not supported, as in NotProton.

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
- 2026-10-15: Upstream sync workflow: NotProton merges, Highball pin and highball-db bumps as PRs, new engine builds as issues.
- 2026-10-15: A final release counts as newer than an installed beta (it was refused before); Remove Everything clears Steam's default tool when it was Proton-ish's.
- 2026-10-16: Highball prefixes keep saves under `steamuser`, where Steam and Steam Cloud look (games saved under the Mac user's name before; existing prefixes are brought over on launch, see Using Highball).
- 2026-10-16: NotProton 1.1.8 merged: CrossOver Preview 20261015 (27.0.0.41073) supported, the Mac stays awake while a game runs (caffeinate), settings FEX cannot use are cleared for Steam's new Compatibility UI, and a steam.cfg that is not UTF-8 is left intact.
- 2026-10-16: The Status screen recommends CrossOver for the best support and performance and asks those who can to buy it and support CodeWeavers; a Thanks section links to NotProton and Highball on GitHub.
- 2026-10-16: A note on who funds Wine on the Mac opens on first launch (again under Help → Why Buy CrossOver) with a Buy CrossOver button; Help → Support CodeWeavers opens the CrossOver page. Repair Steam and Remove Everything sit under their own header above Thanks. README leads with "Use CrossOver if you can" and "Why Proton-ish exists" now describes Highball's engine in Steam rather than a way around paying.
- 2026-10-16: 0.1.0-beta.5: Highball saves kept under steamuser with migration of existing prefixes, NotProton 1.1.8 (CrossOver Preview 20261015, no display sleep during games), CrossOver recommended on the Status screen, first-launch note on who funds Wine.
- 2026-10-16: The CrossOver row's "Supported:" list names only CrossOver versions (Highball's r19 was listed too).
- 2026-10-16: Highball engine r25 (engine build 0024: spatial audio for surround mixes, retina display sizes, the VCLibs packages Forza Horizon 4 waits for) supported next to r19. The Download row offers it when a newer supported engine is missing, and a Highball default tool follows the newest engine set up; the engine list shows usable engines first, newest on top. HighballKit 0.10.16.
- 2026-10-16: The Status screen's Highball section is headed "Highball (free)".
- 2026-10-19: Each Highball engine row says where it stands with Steam: the engine Steam's config names is "Steam's default for Windows games", a requested one is the default "once Steam starts again", and the newest engine says so with a hint to pick it per game under Properties → Compatibility (recommended when not set up yet). The "Use Highball for all Windows games" row names the engine it uses. Repair Steam and Remove Everything moved into the Steam section.
- 2026-10-19: Steam keeps its Accessibility permission when Install follows Repair Steam (the restored Steam carries Valve's signature, so the grant was reset). Proton-ish records the signature it last applied in `signed-requirement`.
- 2026-10-19: highball-db fixes that change the Windows prefix (registry values, config files, engine DLLs) apply once per prefix per database version, written by `highball-env` and imported by the run script before the launch. Fixes verified on another engine line apply by default; the Status screen switch and the launch option `PROTONISH_RECIPE_OTHER_ENGINES` decide.
- 2026-10-20: Highball engines r26 and r27 supported. Both carry r25's Wine build (0024), so the same patches apply; r27 is the engine Proton-ish downloads now, r26 adds Apple's D3DMetal 4.0 beta 3 and needs macOS 27. An engine Highball installed is recognised by its manifest id, since these revisions share launcher bytes.
- 2026-10-20: Upstream changes ship themselves: a sync PR from the daily workflow bumps the version, merges once CI passes and publishes a release, so NotProton and Highball updates reach the app through Sparkle without a manual merge. Conflicts still go to a person.
- 2026-10-19: NotProton 1.2.0 merged: Italian localization, a Windows library filter and button in Steam's library, non-Steam Windows shortcuts run with the default tool and get named prefixes, a per-game Disable hidraw option, High Resolution DPI fix, Steam verification for installs off the boot drive, CrossOver Preview 20261015, Wine's VC++ runtime left native when the game installed Microsoft's, release notes shown as HTML in the updater, and a note that NTFS volumes are unsupported. Proton-ish keeps its own version number, release pipeline and README.

- 2026-10-20: HighballKit 0.10.21, highball-db b7e4a1d: Highball's fixes and per-game data as of this release.
- 2026-10-20: highball-db ed5e18a: Highball's fixes and per-game data as of this release.
## What Install changes

- **Steam app:** Proton-ish adds its Steam Play code to Steam and re-signs it, which is why it needs App Management.
- **Signing certificate:** the first install creates a "Proton-ish Local Signing" certificate in Proton-ish's own
  keychain (`~/Library/Application Support/protonish/signing.keychain-db`) and signs Steam with it, so Steam keeps
  its Accessibility permission across Proton-ish installs and updates, and when Install follows Repair Steam. No
  password prompt: Proton-ish holds that keychain's password.
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

## Maintenance

A daily workflow (`.github/workflows/upstream-sync.yml`, also on demand under Actions) keeps the fork current:

- **NotProton:** a new upstream commit becomes a PR that merges it into main, or an issue listing the conflicting
  files when the merge is not clean.
- **Highball:** a new Highball release bumps the HighballKit pin, and a new highball-db commit refreshes the bundled
  snapshot, in one PR.
- **Highball engines:** a new engine build becomes an issue with the steps to support it.

A sync PR bumps `dylib/version.h` to the next beta (or the next patch after 1.0), adds its dated line below, and
merges itself once the required checks pass; the merge publishes the release, so the app updates through Sparkle
without anyone pressing a button. A merge with conflicts stays with a person: merge by hand on a branch, run
`scripts/sync/bump-release.sh "NotProton <sha> merged"`, open the PR. The workflow needs a repository secret
`SYNC_TOKEN`: a fine-grained GitHub token for this repository only, with Contents, Pull requests, Issues and
Workflows set to read and write, so that CI runs on the PRs it opens. When the token expires the workflow skips with
a notice until it is renewed. Run the scripts' tests with `make synccheck`.

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
