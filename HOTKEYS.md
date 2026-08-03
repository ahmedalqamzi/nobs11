# Native Windows desktop controls

The standard profile does not install a global keyboard hook or third-party window manager. Explorer owns the Windows key, Search, Snap, taskbar, and fullscreen behavior.

## Window controls

| Keys | Action |
|---|---|
| `Win+Left` / `Win+Right` | Snap the focused window to an exact monitor half |
| `Win+Up` | Maximize, or move a snapped window to the upper section |
| `Win+Down` | Restore, move to the lower section, or minimize |
| `Win+Z` | Open native Snap layouts |
| `Win+Shift+Left` / `Win+Shift+Right` | Move the focused window between monitors |
| `Alt+Tab` | Switch applications |
| `Alt+F4` | Close the focused window |
| `Win+D` | Show or restore the desktop |

## Windows shell

| Keys | Action |
|---|---|
| `Win` or `Ctrl+Esc` | Open Start |
| `Win+S` | Open Search |
| `Win+E` | Open File Explorer |
| `Win+R` | Open Run |
| `Win+L` | Lock the device |
| `Win+Shift+S` | Open Snipping Tool capture |
| `Ctrl+Shift+Esc` | Open Task Manager |
| `Win+Ctrl+D` | Create a virtual desktop |
| `Win+Ctrl+Left` / `Win+Ctrl+Right` | Switch virtual desktops |
| `Win+Ctrl+F4` | Close the current virtual desktop |

Windows Terminal is configured to reuse its existing window. Open it from Start, a pinned taskbar button, or `Win+R` followed by `wt`.

## Terminal multiplexer

Inside UCRT64 Bash, run `ta` to attach to the persistent `main` tmux session or create it.

| Keys | Action |
|---|---|
| `Ctrl+A`, then `|` | Split the current tmux pane horizontally |
| `Ctrl+A`, then `-` | Split the current tmux pane vertically |
| `Ctrl+A`, then `h/j/k/l` | Focus the pane left/down/up/right |
| `Ctrl+A`, then `H/J/K/L` | Resize the pane left/down/up/right |
| `Ctrl+A`, then `c` | Create a tmux window in the current directory |
| `Ctrl+A`, then `r` | Reload the tracked tmux configuration |
| Copy mode: `y` | Copy the selection and exit copy mode using vi keys |

## Shell shortcuts

| Keys or command | Action |
|---|---|
| `Ctrl+R` | Search shell history with fzf |
| `Ctrl+T` | Pick a file with fzf |
| `Alt+C` | Change directory with fzf |
| `z <pattern>` | Jump to a matching frequently used directory with zoxide |

## Optional app control

Open **Workstation App Control** from the Start menu for ongoing management. `make apps` remains a read-only terminal audit of optional desktop utilities. The control panel can search installed apps, run uninstallers, stop cataloged background activity and known automatic launch sources, reversibly manage startup items, and inspect current-session processes. Background control does not prevent an app from running when you or another application explicitly launches it later.
