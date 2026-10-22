# Proton-ish

Play Windows games from your normal macOS Steam library. Proton-ish adds Steam Play to the Mac version of Steam, the
way Proton does on Linux: pick a Windows game, press Play, and it runs through Wine, with
[Highball](https://github.com/gauthierpiarrette/highball)'s free engine or with [CrossOver](https://www.codeweavers.com/crossover).

![Emberward running from macOS Steam through Proton-ish and Highball's Wine 11 engine](docs/screenshots/emberward-running-highball.png)

## What you get

- **Your Steam library as it is.** Windows games sit next to your Mac games and start with Steam's own Play button.
  No second launcher, no second library.
- **Steam keeps doing its job.** Steam Cloud saves, sign-in, the overlay and Steam Input go through Steam as usual.
- **Free to play.** Proton-ish downloads Highball's free Wine 11 engine for you and runs each game with Highball's own
  launch settings and per-game fixes from [highball-db](https://github.com/gauthierpiarrette/highball-db), which
  arrive with every update.
- **CrossOver as well.** Own CrossOver? Proton-ish sets it up as a Steam compatibility tool too, and you choose per game.
- **Updates itself** through **Proton-ish → Check for Updates…** or `brew upgrade`.

## Set up

You need an Apple Silicon Mac with macOS 15 or newer and [Steam for macOS](https://store.steampowered.com/about/).

1. **Install** with `brew install --cask magnuspladsen/tap/proton-ish`, or download `Proton-ish.zip` from
   [Releases](https://github.com/MagnusPladsen/Proton-ish/releases) and move `Proton-ish.app` to Applications.
2. **Open it.** It is not notarized, so macOS blocks the first launch: go to **System Settings → Privacy & Security**
   and click **Open Anyway**.
3. **Click Install** on the Status screen, and allow **App Management** when macOS asks: Proton-ish adds Steam Play to
   the Steam app.
4. **Click Download…** next to **Highball engine** (about 440 MB). First you see Apple's licence for D3DMetal, which
   DirectX 12 games use: accept it, or download without it. Already have the Highball app, or CrossOver? Click
   **Set Up** next to it instead.
5. **Restart Steam and press Play.** macOS offers to install Rosetta 2 the first time it is needed.

A game that also has a Mac version runs the Mac version. To play the Windows one, open the game's
**Properties → Compatibility**, tick **Force the use of a specific Steam Play compatibility tool** and pick
**Highball Wine 11 (r27)**.

## Support Wine development

Highball's engine and CrossOver both run on [Wine](https://www.winehq.org/), and most Wine development is done by
[CodeWeavers](https://www.codeweavers.com/), the company behind CrossOver. If you can, buying
[CrossOver](https://www.codeweavers.com/crossover) is the most direct way to support future Wine development, and
Proton-ish supports it fully alongside Highball's engine. The app shows this note once and keeps it under
**Help → Support Wine Development**.

## Games

Highball's community tracks how games run in [highball-db](https://github.com/gauthierpiarrette/highball-db), which
Proton-ish bundles, so what works in Highball should work here. Tested through Proton-ish itself:

| Game | Engine | Result |
|---|---|---|
| Nubby's Number Factory | Highball Wine 11 r25 | Runs, 2026-10-19; the prefix recipe path (M2c) not yet exercised on it |
| Emberward | Highball Wine 11 r19 | Runs, 2026-10-14 |
| Among Us | Highball Wine 11 r19 | Runs, Steam sign-in and the overlay included, 2026-10-15 |

Untested so far: a DirectX 12-only game on D3DMetal, a game with a highball-db prefix recipe (Portal 2, Warframe),
anything through CrossOver. Played something? [Open an issue](https://github.com/MagnusPladsen/Proton-ish/issues)
either way, working or not, and it goes on this list.

## Reporting problems

Open an [issue](https://github.com/MagnusPladsen/Proton-ish/issues) with the game's `protonish-run.log` (in the game's
prefix). The Steam integration, the setup and the launch are Proton-ish's, even when Highball's engine runs the game,
so start here. If it turns out to be the engine, the issue will point you to the right place: highball-db for a game
that also misbehaves in the Highball app, or [Highball's issues](https://github.com/gauthierpiarrette/highball/issues)
for an engine bug reproduced there. Please don't report Proton-ish setups to Highball, NotProton, CodeWeavers or Valve.

## More

- [Using Proton-ish](docs/using-proton-ish.md): supported engines, graphics modes, game fixes, saves, CrossOver
  builds, limits (VAC, NTFS) and what Install changes on your Mac.
- [Developing Proton-ish](docs/development.md): building from source, the source layout, and how the fork keeps up
  with NotProton and Highball.

## Thanks

- **[Highball](https://github.com/gauthierpiarrette/highball)** by Gauthier Piarrette, for a free, open-source
  Wine runtime for Apple Silicon. Proton-ish runs games with Highball's engine, its launch code (HighballKit, GPLv3)
  and its per-game database ([highball-db](https://github.com/gauthierpiarrette/highball-db), CC0).
- **[NotProton](https://github.com/NotProtonNot/NotProton)** by NotProtonNot, for the Steam integration,
  the macOS lsteamclient port and steam-shim. Proton-ish is a fork of NotProton; all of that work is theirs.
- **[CodeWeavers](https://www.codeweavers.com/)**, for maintaining and funding [Wine](https://www.winehq.org/)
  for decades and publishing CrossOver's sources.
- **[Valve](https://github.com/ValveSoftware/Proton)**, for Proton, lsteamclient and steam_helper.
- NotProton's README thanks earlier projects with similar goals, noting that NotProton was not built on their work,
  and Proton-ish passes those thanks on: [Kaon](https://github.com/natbro/kaon) by [Nat Brown](https://github.com/natbro),
  [Neutron](https://github.com/mont127/Neutron) by mont127, and [Gio](https://github.com/giodotblue), who worked on
  enabling Steam Play in macOS Steam before NotProton was released. The original NotProton README is at
  https://github.com/NotProtonNot/NotProton#readme.

> Proton-ish is a fork of NotProton and is **not affiliated with or endorsed by** NotProton, Valve,
> CodeWeavers or Highball.

## Contributing and license

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Licensing is described in
[NOTICE](NOTICE).

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
- 2026-10-20: NotProton 3bbc6a7 merged: FEX gets a Reduced x87 precision toggle (on by default) and AVX2 on by default.
- 2026-10-20: 1.0.0. Proton-ish leaves beta: Highball's free Wine 11 engines r19 to r27 with Highball's launch setup and per-game fixes, CrossOver as NotProton has it, self-releasing upstream syncs, Sparkle updates and a Homebrew cask. Nobody can test every game, so the README keeps a compatibility list and every game that misbehaves is an issue.
- 2026-10-20: highball-db f2c34a9: Highball's fixes and per-game data as of this release.
- 2026-10-21: HighballKit 0.10.22, highball-db 18f3c87: Highball's fixes and per-game data as of this release.
- 2026-10-21: The upstream sync runs every three hours instead of daily, and an upstream README edit no longer blocks a NotProton merge: the fork's README wins (`merge=ours`), so those merges ship on their own like the rest.
- 2026-10-21: NotProton f478d89 merged: CrossOver versions sort in order, appmanifest names keep escaped quotes, more Italian.
- 2026-10-21: New Highball engine revisions that reuse a supported Wine build are supported by the Highball sync itself, with no manual pin, and the newest one that runs on macOS 15 becomes the engine Proton-ish downloads.
- 2026-10-21: highball-db 81da423: Highball's fixes and per-game data as of this release.
