# Using Proton-ish

The details behind the [setup in the README](../README.md#set-up).

## Highball's engine

Proton-ish supports Highball's Wine 11 engines `x64-crossover26.3-r27` (the one it downloads), r26 (with D3DMetal 4
beta 3, macOS 27 only), r25 and r19. The engine lives in Highball's standard folder
(`~/Library/Application Support/Highball/engines`), whether Proton-ish downloaded it or the Highball app did, so the
two share it; games use its graphics files from there. Proton-ish never downloads, hosts or modifies D3DMetal on its
own: it is part of Highball's engine bundle and is only used after you accept Apple's licence, in the download sheet
or later through the engine row's **Enable D3DMetal…**.

If Steam had no default compatibility tool, Highball becomes the default for Windows games (the **Use Highball for
all Windows games** switch on the Status screen), so a Windows-only game just shows Play.

![Steam's Compatibility settings with "Highball Wine 11 (r19)" selected as the compatibility tool](screenshots/steam-compatibility-highball.png)

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

**Reporting a game.** How a game ran is worth a report: right-click it in **Prefixes** and choose **Report to
highball-db…**. highball-db's form opens in your browser with the game, engine, renderer and Mac filled in, marked as
Proton-ish; you add the rating and submit it with your GitHub account.

Design and roadmap: [design spec](superpowers/specs/2026-10-14-protonish-highball-design.md).

## CrossOver

In step 4 of the setup, click **Set Up** next to your CrossOver install instead of downloading Highball's engine.
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
- **Controllers** go through Steam Input the way NotProton routes them; Proton-ish has not characterised them beyond
  a game launching. If a controller is seen twice or not at all, try the game's **Disable hidraw** option in its
  Proton-ish settings, and report what you see.
- **Languages.** The app is in English, Italian and Simplified Chinese. Some of the strings Proton-ish adds
  (Highball, engines, licences, game fixes) still show in English in Italian until someone translates them.

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
