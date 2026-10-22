# Changelog

What Proton-ish changes from [NotProton](https://github.com/NotProtonNot/NotProton), oldest first. Each release is
on [Releases](https://github.com/MagnusPladsen/Proton-ish/releases).

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
- 2026-10-22: README leads with what Proton-ish does and a five-step setup, with the details in docs/. The app recommends buying CrossOver to support future Wine development, under Help → Support Wine Development.
- 2026-10-22: Games run through Highball can be reported to highball-db from Prefixes (Report to highball-db…, in the toolbar or a game's menu), with the engine, the game's settings and your Mac filled in and marked as Proton-ish. The HighballKit version in launch logs is right again.
- 2026-10-22: New Highball Wine builds are checked against the pinned ones: one whose ntdll resolves like a supported build becomes a pull request to review, the others an issue with the differences. Engine revisions on a supported Wine build are pinned on every sync.
