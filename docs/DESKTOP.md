# Canopy as a desktop environment

Canopy is a desktop environment, not a shell you bolt onto someone else's
session. This file lists what that means in practice, so the difference between
"the shell runs" and "the desktop is installed" stays visible.

## What the desktop owns

| Layer | Component | Where |
|---|---|---|
| Compositor | Labwc | `config/labwc/` |
| Window management | stacking, snap, workspaces, rules | `config/labwc/rc.xml` |
| Root menu | desktop right-click menu | `config/labwc/menu.xml` |
| Session entry | what the display manager launches | `config/canopy-session.desktop` |
| Session helper | environment + compositor bootstrap | `scripts/canopy-session` |
| Shell | panel, tray, dock, launcher, settings, lock, OSD | `src/` (`bin/canopy`) |
| Notifications | daemon, history, DND | shell process |
| Clipboard | history + data-control | shell process |
| Wallpaper | rendering + picker | shell process |
| Session actions | lock, logout, reboot, shutdown | shell process (`canopy msg session …`) |
| Desktop portal | file chooser, screencast, screenshot | `config/xdg-desktop-portal/canopy-portals.conf` |
| Toolkit theming | GTK, Qt | `config/gtk-3.0`, `config/gtk-4.0`, `config/qt6ct` |
| Default applications | browser, files, images, media | `config/mimeapps.list` |
| Icons and cursor | theme selection, Canopy mark | installer + `assets/canopy.svg` |
| Updates | release check and install | `scripts/canopy-update` |
| Packaging | dependency resolution per distribution | `scripts/lib-distro.sh`, `scripts/deps.sh` |
| Install / uninstall | user and system | `scripts/install.sh`, `scripts/uninstall.sh` |
| Release payload | single-file installer | `scripts/build-release.sh` |

## Starting a session

```sh
canopy-session            # via display manager entry, or from a TTY
canopy-session --nested   # inside an existing Wayland session (development)
```

`canopy-session` exports the desktop identity (`XDG_CURRENT_DESKTOP=Canopy`,
toolkit backends, portal directory), clears a stale shell, and starts Labwc.
The shell itself is started from `config/labwc/autostart`, and the wrapper skips
its own startup command when that autostart file is present — starting both
would produce two panels and two sets of tray icons.

## Packaging

`meson install` (or `just install release`) installs:

```
bin/canopy
bin/canopy-session
bin/canopy-screenshot
bin/canopy-update
share/canopy/assets/...
share/wayland-sessions/canopy.desktop
share/xdg-desktop-portal/canopy-portals.conf
share/applications/dev.canopy.Canopy.desktop
share/icons/hicolor/scalable/apps/canopy.svg
```

A system install also seeds `/etc/xdg/labwc/*` and `/etc/xdg/gtk-*/settings.ini`
for accounts that have never run a Canopy session. User configuration is never
overwritten, and uninstalling keeps `~/.config/canopy` unless `--purge` is used.

## Dependency handling

```sh
sh scripts/deps.sh plan       # what this machine is missing
sh scripts/deps.sh install    # install it
sh scripts/deps.sh build      # build dependencies for a from-source build
```

The runtime list is the compositor, the portals and the system services the
shell talks to. Canopy's shell has no Qt or GTK dependency, so `quickshell`,
`qt6-declarative` and friends are not part of it.

## Release payload

```sh
sh scripts/build-release.sh    # -> dist/canopy-<version>.run
sh canopy-<version>.run        # user install
sudo sh canopy-<version>.run   # system install + Wayland session entry
```

CI (`.github/workflows/release.yml`) builds the same payload on a tag and
publishes `canopy-<version>.run` + `SHA256SUMS`, which is what `canopy-update`
downloads and verifies.

## Verified behaviour

Checked by running a real headless Labwc session from an installed payload:

- `canopy-session` starts Labwc, Labwc runs autostart, exactly one shell starts
- top panel, left vertical tray and bottom dock are created on the output
- the shell loads its assets from the user install
  (`~/.local/share/canopy/assets`), not from the build tree
- `config/labwc/rc.xml` parses without action errors
- `scripts/install.sh --dry-run` leaves existing user files untouched
- `scripts/uninstall.sh` removes the install and keeps the configuration
- `scripts/deps.sh plan` resolves package names on the host distribution

Not verified: live keyboard interaction, portal file dialogs, lock screen
authentication, and multi-monitor behaviour on real hardware.