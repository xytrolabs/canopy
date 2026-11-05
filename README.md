# Canopy

The **Xytro Labs** desktop environment for Linux: a native Wayland shell on
**Labwc**, built on the Noctalia v5 foundation.

> **Powerful when needed. Simple by default.**
> _Mac functionality with Windows simplicity._

<p align="center"><img src="assets/canopy.svg" alt="Canopy" width="120"></p>

## What Canopy is

Canopy is a desktop environment, not a bar you bolt onto someone else's session.
One process owns the desktop surfaces; the compositor owns the windows; the
installer owns the session.

| Layer | Component |
|---|---|
| Compositor | Labwc (stacking, movable, resizable windows) |
| Shell | `canopy` — panel, tray, dock, launcher, quick settings, notifications, OSD, lock screen, wallpaper |
| Session | `canopy-session` + `wayland-sessions/canopy.desktop` |
| Portals | `xdg-desktop-portal-{gtk,wlr}` with Canopy's preferred-backend config |
| Toolkit theming | GTK 3/4, Qt 6 (palette, fonts, icons, cursor) |
| Default apps | `mimeapps.list` baseline |
| Lifecycle | `deps.sh`, `install.sh`, `uninstall.sh`, `canopy-update`, single-file release payload |

The shell is native: no Qt, no GTK, no Quickshell. It speaks Wayland and OpenGL
ES directly, so the panel, dock, launcher and settings share one event loop, one
theme palette, one configuration store and one IPC socket.

## Layout

```
┌──────────────────────────────────────────────────────────────┐
│  launcher  workspaces  window      clock      tray · session  │  System Panel
└──────────────────────────────────────────────────────────────┘
 ┌──┐
 │  │  launcher                                              ▓▓▓ │
 │  │  settings                                        ▓ quick ▓  │  System Tray (left)
 │  │  network                                           ▓ sett.▓ │
 │  │  sound                                             ▓▓▓▓▓▓▓ │
 └──┘
                    ┌──────────────────────────┐
                    │  pinned │ running │ min  │                    Dock (bottom)
                    └──────────────────────────┘
```

- **System Panel** — top, slim, floating: launcher, workspaces, active window,
  centred clock, media, notifications, network, Bluetooth, volume, battery,
  quick settings, session.
- **System Tray** — vertical pill on the left edge: launcher, settings, network,
  audio, Bluetooth, notifications, quick settings.
- **Dock** — bottom centre: pinned ǀ running ǀ minimized, with context menus,
  tooltips and multi-window handling.
- **Quick Settings** — attached to the right edge: Wi-Fi, Bluetooth, audio,
  microphone, brightness, power profiles, night light, Do Not Disturb.

Defaults live in [`config/canopy/config.toml`](config/canopy/config.toml) and are
seeded on first run or by the installer, never over an existing setup.

## Design

- Acrylic-inspired translucency with controlled blur — and surfaces that stay
  readable with blur and animations disabled.
- Rounded geometry, one corner scale, subtle shadows.
- Restrained purple accent: `#7C5CFC` on a near-black violet base `#0B0A10`,
  with tinted-glass surfaces (`#16151F`, `#201E2C`).
- Inter for UI text, Tabler for icons. No emoji stand-ins, no missing-icon
  placeholders, no magenta artefacts.
- Short, purposeful transitions.

Full notes: [docs/CANOPY_DESIGN.md](docs/CANOPY_DESIGN.md).

## Install

### From a release

```sh
curl -fsSLO https://github.com/xytrolabs/canopy/releases/latest/download/canopy-2026.11.04.run
curl -fsSLO https://github.com/xytrolabs/canopy/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS
sh canopy-*.run          # user install
sudo sh canopy-*.run     # system install + Wayland session entry
```

Log out and pick **Canopy** in the display manager, or start it from a TTY:

```sh
canopy-session
```

Canopy runs on labwc. MangoWC is available as a separate beta session for
testing, side by side — it never replaces the default one:

```sh
sudo sh scripts/install.sh --with-mangowc
canopy-session --compositor mangowc    # back with: canopy-session --compositor labwc
```

See [docs/COMPOSITORS.md](docs/COMPOSITORS.md) for what differs (decorations,
tiling, tags) before trying it.

### From source

```sh
sh scripts/deps.sh plan      # what this machine is missing
sh scripts/deps.sh build     # build dependencies (distro-specific names)
just configure release
just build release
sudo sh scripts/install.sh
```

## Working on it

```sh
canopy-session --nested        # run the whole desktop inside your current session
canopy msg panel-toggle launcher
canopy msg settings-open
canopy config validate         # check ~/.config/canopy/config.toml
just test                      # unit tests
```

Useful scripts:

```sh
sh scripts/deps.sh plan        # runtime/build gaps on this distribution
sh scripts/uninstall.sh        # remove the install, keep the configuration
canopy-update check            # is there a newer release?
sh scripts/build-release.sh    # dist/canopy-<version>.run
```

## Project layout

| Path | Contents |
|---|---|
| `src/` | shell sources (C++23, Wayland + OpenGL ES) |
| `assets/` | icon font, translations, wallpapers, default config, desktop entries |
| `config/` | Canopy defaults, Labwc session, portals, GTK/Qt, mimeapps |
| `scripts/` | session, install, uninstall, deps, update, release |
| `docs/` | design system, desktop scope, packaging, upstream fork notes |
| `protocols/` | Wayland protocol XML used by the shell |

## Upstream and licensing

Canopy is an independent Xytro Labs project built on
[Noctalia](https://github.com/noctalia-dev/noctalia) v5.4.1 (MIT). Upstream
copyright, attribution and third-party acknowledgements are preserved — see
[LICENSE](LICENSE), [CREDITS.md](CREDITS.md) and
[docs/UPSTREAM_FORK.md](docs/UPSTREAM_FORK.md) for the pinned commit and the
upstream-sync procedure.

Canopy itself is MIT licensed.