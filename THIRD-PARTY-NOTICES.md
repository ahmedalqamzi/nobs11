# Third-party notices and provenance

This repository installs external applications through WinGet and MSYS2; their binaries are not redistributed here and remain under their respective licenses.

The locally written cleanup and performance policies were reviewed against these pinned upstream snapshots:

- [AtlasOS `1ed9630616b29f0c7974e8bd76a94fc06f60388c`](https://github.com/Atlas-OS/Atlas/tree/1ed9630616b29f0c7974e8bd76a94fc06f60388c) — GPL-3.0
- [Win11Debloat `6957ce4220960ea1473ff6b9f6d6a8a8359f4cb5`](https://github.com/Raphire/Win11Debloat/tree/6957ce4220960ea1473ff6b9f6d6a8a8359f4cb5) — MIT
- [Winhance `f23d554eb2d6400b1827bcc46b91294ffa53fbc9`](https://github.com/memstechtips/Winhance/tree/f23d554eb2d6400b1827bcc46b91294ffa53fbc9) — PolyForm Shield 1.0.0 except where its own third-party notices state otherwise

Catppuccin color values are used in terminal and prompt configuration; [Catppuccin](https://github.com/catppuccin/catppuccin) is MIT licensed.

The retired Zebar/Notch custom dock implementation, bundled Zebar client, bundled Nerd Font webfont, preview image, and unverified wallpaper were removed before public release preparation. Nerd Fonts, Windows Terminal, Brave, Git, and the other standard dependencies are installed from their upstream package sources rather than copied into this repository. GlazeWM, Zebar, AutoHotkey, PowerToys, Command Palette, Overwolf, and Mobalytics are optional migration/cleanup targets and are not installed by the standard manifest.

No upstream source file is intentionally vendored in the current tree. The review method and scope are recorded in [docs/UPSTREAM-PROVENANCE.md](docs/UPSTREAM-PROVENANCE.md). The project's original source is released under the MIT License; every notice required by applicable third-party licenses remains in force for third-party material.

Windows and other Microsoft product names are trademarks of Microsoft Corporation. This project is independent and is not endorsed by Microsoft or the other upstream projects.
