# Canopy

A lightweight, modular Linux desktop environment for Wayland by **Xytro Labs**.
Labwc (compositor) + Quickshell (desktop shell) + a shared QML design system.


## Layout

| Component | Position | Responsibilities |
|---|---|---|
| **System Panel** | full width, top | app menu, workspace indicators, active application, clock/date |
| **System Tray** | floating pill, left edge | network, audio, Bluetooth, battery, quick settings |
| **Application Dock** | floating, bottom centre | pinned apps ǀ minimized windows ǀ active unpinned windows |
| **Desktop background** | `WlrLayer.Background` | gradient wash (no external wallpaper daemon needed) |

The **tray auto-hides** (slides out on the left band). The **dock is
intelligent**: on an empty desktop it stays visible so there is always something
to launch from; once a window exists it hides, and it comes back when the pointer
touches the bottom edge (or if anything is minimized).

Both surfaces use an **8px hot edge** (`mask: Region { item: <hotEdge> }`). The hot
edge is always on-screen and grows with the surface, so edge-hover reveals it
while the invisible area never steals clicks from application windows.

The dock is split into three clearly separated groups — **pinned ǀ minimized ǀ
active-but-unpinned** — and dividers only appear between groups that actually
have content.`` Their input region is
masked to the pill/bar itself (`mask: Region`), so the invisible band never
steals clicks from application windows.

The panel shows the application menu, GNOME-style workspace dots, a centred
clock + date, and a session button. **Running applications never appear in the
panel** — they belong to the dock. Network/audio/Bluetooth/battery/quick-settings
live **only** in the System Tray.

### Typography

Canopy ships its own typefaces in `shell/fonts/` and registers them with
`FontLoader` at the top of `shell.qml`, so the shell looks the same on every
machine instead of inheriting whatever Sans the box happens to have:

| Face | Role | Where |
| --- | --- | --- |
| **Space Grotesk** | panel, dock, headings, the clock | `Theme.fontDisplay` (also the default `Theme.fontFamily`) |
| **Inter** | body copy, menus, settings descriptions | `Theme.fontBody` |
| **JetBrains Mono** | numerals that must not jitter | `Theme.fontMono` |

All three are SIL OFL 1.1 and are distributed unmodified. `scripts/install.sh`
also copies them to `~/.local/share/fonts/canopy` so Qt apps, terminals and the
font picker see them, and `config/qt6ct/qt6ct.conf` sets Space Grotesk as the Qt
default so no widget falls back to a generic sans.

The panel carries the Canopy mark (`shell/assets/canopy-mark.svg`) as its
launcher button; `IconButton.imageSource` renders artwork instead of a themed
icon without tinting it.

## Interaction

One shared interaction layer (`shell/Components/`) drives tooltips, context
menus, icon buttons, hover/pressed/active states and active indicators across
every surface — see [docs/INTERACTION.md](docs/INTERACTION.md).

| What | How |
|---|---|
| **Launcher** | `Super` (toggles open/closed), or the panel / tray launcher button |
| **Launcher keyboard** | type to search, `↑ ↓ ← →` to move, `Enter` to launch, `Esc` to close |
| **Lock screen** | `Super+L` |
| **Tooltips** | hover any panel, tray, dock, quick-settings or settings control |
| **Context menu** | right-click the dock, tray icons, panel, panel power button, or empty desktop |
| **Quick settings** | left-click Wi-Fi / sound / battery in the panel or tray |

`Super` is bound in `config/labwc/rc.xml` as
`<keybind key="Super_L" onRelease="yes">` so `Super+<key>` shortcuts keep working.
The binding runs `quickshell -c canopy ipc call canopy toggleLauncher` — the
`-c canopy` flag is required for the IPC client to find the running shell.

## Install (single file)

```bash
sh dist/canopy-*.run          # user install: shell + Labwc config
sudo sh dist/canopy-*.run     # system install: also registers the DE session
```

The `.run` file is self-extracting and contains the whole desktop. The system
install additionally drops:

- `/usr/local/share/wayland-sessions/canopy.desktop` — so **Canopy appears in
  the display-manager session list** next to GNOME/KDE/Hyprland.
- `/usr/local/bin/canopy` — starts the shell inside an existing session, or
  `labwc` when run from a TTY.

Rebuild it after changes:

```bash
sh scripts/build-release.sh   # -> dist/canopy-<date>.run
```

## Updates

Canopy is not packaged by any distribution, so it updates itself from its own
releases: **github.com/xytrolabs/canopy** (canonical), mirrored on the project
site. The same self-extracting payload that installed Canopy is what upgrades
it, and every download is verified against `SHA256SUMS` before it runs.

```sh
canopy-update check          # installed / latest / up to date
canopy-update apply          # download, verify, install, restart
```

The shell does the same thing from **Settings → System → Software updates**:
it checks once a day (a timestamp means a restarted shell does not re-check),
raises a notification once per session when something is available, adds an
*Install Canopy x.y* entry to the power menu, and restarts itself after
installing. **Auto-check is on by default; auto-install is not** — installing
always needs a click, because it replaces the shell you are looking at.

Releasing, tagging and the asset names the updater depends on:
[`docs/RELEASING.md`](docs/RELEASING.md).

## Distributions

Canopy is distribution-agnostic: nothing in the shell or the installer assumes
a particular package manager. `scripts/lib-distro.sh` maps capabilities to
package names for Arch/CachyOS, Fedora and Debian/Ubuntu, and is the only file
that names a package.

```bash
sh scripts/deps.sh plan       # what this machine is missing + how to fix it
sh scripts/deps.sh install    # install it
```

| Distribution | labwc | quickshell |
| --- | --- | --- |
| Arch / CachyOS | 0.20.2 packaged | 0.3.2 packaged |
| Fedora 43–45 | 0.9.6–0.20.2 packaged | **unpackaged or too old** → `scripts/build-quickshell.sh` |
| Debian trixie | 0.8.3 packaged | 0.3.0 in `trixie-backports`; labwc via `scripts/build-labwc.sh` |
| Debian forky | 0.20.2 packaged | 0.3.2 packaged |

Full matrix, including what each distribution is missing and why:
[`docs/DISTRIBUTIONS.md`](docs/DISTRIBUTIONS.md). The icon theme is picked from
whatever is installed (`kora` → Papirus → Breeze → Adwaita), not hardcoded to an
Arch favourite, so a Fedora or Debian box looks right on first launch.

## Install (from source)

```bash
sudo pacman -S labwc quickshell qt6-declarative qt6-wayland qt6-5compat \
  xorg-xwayland wayland-protocols wlroots0.20 upower networkmanager bluez \
  pipewire grim

./scripts/install.sh
```

`install.sh` copies the Labwc config to `~/.config/labwc/`, the shell to
`~/.config/quickshell/canopy/`, and regenerates `shell/icon-map.js`.

## Run

```bash
quickshell kill canopy 2>/dev/null   # stop any stale instance
labwc -S 'quickshell -n -c canopy' -t Canopy
```

Autostart already launches `quickshell -n -c canopy`. **`-n` (single instance) is
required** — without it the autostart shell and a manually launched shell both run,
which is what produces a *second* panel and a *second* set of tray icons.

## Icons and icon packs

Icon packs such as **Kora**, Papirus, McMojave or Win11 are plain directories of
SVGs with an `index.theme` — there is nothing KDE-specific about them, and Labwc
has no say in icon theming (icons are chosen by the toolkit, not the compositor).
The only gate was Qt's icon-theme lookup, which on this machine fails for most
names (`firefox`, `thunar`, `code-oss`, `bluetooth-active`…) and paints Qt's
magenta checkerboard.

Canopy therefore resolves icons itself:

- `scripts/gen-icon-map.py` scans **every** theme under `~/.local/share/icons`,
  `/usr/share/icons` and `/usr/share/pixmaps` and writes `shell/icon-map.js`
  (~33 000 name → file mappings).
- Ties are broken by sharpness (SVG > large PNG) and then by a theme preference
  list at the top of the script. Kora is currently first, so Kora artwork wins.
- `shell/CanopyIcon.qml` looks a name up, falls back to `<name>-symbolic`, then
  draws a letter. It never shows a checkerboard.
- Monochrome symbolic glyphs are recoloured via `ColorOverlay` (`tint`), so the
  panel and tray glyphs read correctly in both light and dark mode.

To use a different icon pack, put it in `~/.local/share/icons/` and reorder
`PREFERRED` in `scripts/gen-icon-map.py`, then:

```bash
python3 scripts/gen-icon-map.py shell/icon-map.js
./scripts/install.sh
```

## Theme

All tokens live in `shell/Theme.qml` (singleton `Theme`): colours, radii,
spacing, typography, animation durations, and `darkMode`. Components bind to it,
so switching `Theme.darkMode` re-themes the whole shell.

## Known limitations

- **Workspaces**: indicators are shown, but switching uses Labwc keybinds
  (`Super+1..4`). Quickshell cannot drive Labwc desktops over IPC.
- **Notifications**: if another daemon already owns
  `org.freedesktop.Notifications`, Quickshell logs a registration warning and
  your existing daemon keeps the slot.
- **Battery**: hidden when UPower reports no battery (desktops, nested sessions).
- **Icon packs**: an app with no artwork in any installed pack (e.g. some KDE
  utilities) shows the pack's generic placeholder icon, not a bespoke one.
- **Auto-hide reveal strip**: the tray reveals on the left *window* band and the
  dock on the bottom band; there is no configurable hot-edge width yet.
- **Minimize/restore** depends on the compositor advertising wlr-foreign-toplevel;
  Labwc does, so it works.

## Development

```
shell/
  shell.qml         entry point, all surfaces
  Theme.qml         design tokens (singleton)
  CanopyIcon.qml    icon resolver component
  icon-map.js       generated icon index
config/labwc/       rc.xml, environment, autostart
scripts/            install.sh, gen-icon-map.py
```

To add a plugin surface, add a `PanelWindow` (layer-shell) with
`exclusionMode: Ignore`, bind it to a `Theme` token, and avoid polling — use the
Quickshell service models (`Networking`, `Bluetooth`, `UPower`, `ToplevelManager`,
`SystemClock`) which are signal-driven.
