# Proton-ish

Proton-ish brings the Steam Play experience from Linux Steam to the macOS Steam client.
Pick a Windows game in your normal macOS Steam library, choose a compatibility tool, press Play.

## Why Proton-ish exists

[NotProton](https://github.com/NotProtonNot/NotProton) made Steam Play work on macOS, but it only
supports [CrossOver](https://www.codeweavers.com/crossover), which is a paid product. Today there are
good free and open-source Wine runtimes for the Mac, such as [Highball](https://github.com/gauthierpiarrette/highball).
Proton-ish is adding support for those, starting with Highball (in progress, not usable yet), so nobody has to
pay just to play the Windows games they already own. CrossOver stays fully supported.

If you can afford it, please consider buying CrossOver anyway: CodeWeavers funds most of the Wine
development that every free runtime, Highball included, is built on.

## Thanks

- **[CodeWeavers](https://www.codeweavers.com/)**, for maintaining and funding [Wine](https://www.winehq.org/)
  for decades and publishing CrossOver's sources. Without them there would be no Wine on macOS.
- **[NotProton](https://github.com/NotProtonNot/NotProton)** by NotProtonNot, for the Steam integration,
  the macOS lsteamclient port and steam-shim. Proton-ish is a fork of NotProton; all of that work is theirs.
- **[Highball](https://github.com/gauthierpiarrette/highball)** by Gauthier Piarrette, for a free, open-source
  Wine runtime for Apple Silicon that makes a CrossOver-free setup possible.
- **[Valve](https://github.com/ValveSoftware/Proton)**, for Proton, lsteamclient and steam_helper.

> Proton-ish is a fork of NotProton and is **not affiliated with or endorsed by** NotProton, Valve,
> CodeWeavers or Highball. Please report Proton-ish problems at
> https://github.com/MagnusPladsen/Proton-ish/issues, never to those projects.

## Status

- Proton-ish is in early development.
- The code on `main` is currently unmodified upstream NotProton.
- The rebrand (own bundle ID, update feed, support directory `~/Library/Application Support/protonish/`,
  tool names `protonish-*`) is in progress on branch
  [`design/protonish-highball`](https://github.com/MagnusPladsen/Proton-ish/tree/design/protonish-highball).
  See the [design spec](https://github.com/MagnusPladsen/Proton-ish/blob/design/protonish-highball/docs/superpowers/specs/2026-10-14-protonish-highball-design.md).
- Highball support comes after the rebrand.
- There are no Proton-ish releases yet. Until then, use upstream
  [NotProton](https://github.com/NotProtonNot/NotProton) with CrossOver.

The upstream NotProton documentation follows.

---

## Upstream NotProton README

NotProton enables the Steam Play experience from Linux Steam in the macOS Steam client.

This is done by forcibly enabling the Steam Play functionality in macOS Steam (which is
present and inert) as well as by porting some components of Valve's Proton to macOS.

This tool is intended to be used with the stable Steam Client (version 1791918634) as well as the beta Steam Client (version 1791686101) paired with **CrossOver 26.3 or CrossOver [Preview](https://www.codeweavers.com/preview)
20261006 or 20260821**, with more supported versions to come.

Supporting specifically CrossOver is a design goal of this project. Better support for modifying CrossOver (using custom builds of DXMT/patched D3DMetal/MacGameVideoFix) will come in a future update, but support for alternatives to CrossOver itself is not planned.

Both the FEX and the Rosetta versions are supported. I recommend using the FEX version of the 
Preview 20261006, as it includes both the FEX version as well as the Rosetta one. 

I further recommend going into Steam Settings - Compatibility and selecting the Rosetta version as your default compatibility tool. You can select FEX on a per game basis by right clicking a game in Steam, going into Properties - Compatibility and selecting FEX there.

If a game has a native macOS version as well as a Windows one, Steam will download the macOS version. To override this behavior, right click on the game, select Properties, select Compatibility. Enable 'Force the use of a specific Steam Play compatibility tool'. Select whichever version of CrossOver you want to do use. That will make Steam download the Windows version. Unchecking the 'Force the use...' box or selecting 'No Compatibility Tool' in the drop down list will revert to the macOS version of the game, with the specifics there varying based on your Steam version.

**Valve Anti-Cheat is not supported.** Proton itself does not support VAC in Valve titles; Valve ships native Linux ports instead. VAC titles will launch in Insecure Mode and will not allow matchmaking. 

**This project now has a brew cask.** For brew users, you can install via ``brew install --cask notprotonnot/notproton/notproton``

Please read NOTICE for license information.

Please open issue reports with any issues. PRs are welcome and encouraged.

There are many people who worked on similar ideas, similar projects. I did not base NotProton on their work, but I still want to 
give thanks to the people who came before me:

[Nat Brown](https://github.com/natbro) made [Kaon](https://github.com/natbro/kaon), which is similar in goals to NotProton.

mont127's [Neutron](https://github.com/mont127/Neutron) is also a similar idea, but implemented differently. 

[Gio](https://github.com/giodotblue) was working enabling Steam Play inside of Steam on macOS prior to the release of NotProton itself. 
I would have done things differently had I been aware of that. 

Thanks to everyone who has positively contributed to macOS gaming. 

Developer Notes:

As far as the source structure goes, the macOS app itself is located in the ```app``` folder. The core logic is in ```dylib```.
```lsteamclient``` is a macOS port of Valve's lsteamclient. ```steam-shim```is a port of Valve's
steam-helper from Proton 9.0. ntdll-patch patches the copy of CrossOver that the app
makes/places in the ```~/Library/Application Support/notproton/runners/``` folder so that
lsteamclient is loaded.
