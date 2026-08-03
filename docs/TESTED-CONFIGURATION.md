# Tested configuration

## Primary test system

- ASUS ROG Zephyrus G16 family (exact model identifier intentionally omitted)
- Windows 11 Home 25H2, build 26200.8875
- x64, 2560×1600 internal display
- Windows Terminal 1.23
- PowerShell 7.6
- Native Windows Snap and Explorer taskbar

## Automated validation

The live verifier checks required commands, managed-file drift, the single-terminal model, native Snap and taskbar state, startup policy, protected Windows services and packages, browser policy, retired background-layer state, and rollback sentinels. Verification reports are redacted by default; `-IncludeIdentity` is intended only for private troubleshooting.

Repository CI separately checks PowerShell syntax, JSON parsing, dependency declarations, personal paths, runtime-data exclusions, startup safety, and removal of the retired custom dock.

## Interaction probes completed

- Native `Win`, `Ctrl+Esc`, and Search behavior
- Exact left/right window splits
- Normal window clearance above the taskbar
- Native fullscreen covering the taskbar without a third-party window manager
- Single Windows Terminal process/window behavior
- Explorer taskbar visibility and recovery after restart

## Manual sign-off still required for each release

- At least one DirectX fullscreen game and one borderless-windowed game
- Sleep, wake, shutdown, and cold boot
- Wi-Fi, Bluetooth, audio, microphone, camera, and notifications
- Brightness, keyboard lighting, fan/GPU modes, battery limit, and refresh switching
- External display and mixed-DPI behavior
- Steam, Riot/Vanguard, Overwolf-dependent software, Store, WinGet, Windows Update, and Defender
- Access to the Device Encryption or BitLocker recovery key

Passing on this laptop does not establish compatibility with other OEM service stacks. The machine-wide cleanup policy must be reviewed for every different device.
