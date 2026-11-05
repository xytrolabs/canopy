# Compositors

Canopy's shell is compositor-agnostic; **labwc is the session that ships and is
supported**. Other compositors are experiments, and each one gets its own
session entry so testing it can never change the default session.

| Session | Compositor | Status |
| --- | --- | --- |
| Canopy | labwc | default, supported |
| Canopy (MangoWC, beta) | mangowc | beta, side-by-side test |

## Why labwc is the default

The desktop's whole visual identity lives in labwc's side of the stack:

- server-side decorations (`config/labwc/themes/canopy/openbox-3`) — the
  traffic-light buttons, titlebar colours and corner radius,
- the `rc.xml` keybind scheme and window rules,
- `autostart` starting the shell.

A dwl-derived compositor such as MangoWC draws no decorations at all and owns
its window management (tiling, tags, layouts), so windows look and behave
differently there. That is why MangoWC is a *second* session and not a
replacement.

## Testing MangoWC

```sh
sudo sh scripts/install.sh --with-mangowc    # installs mangowm + session entry
canopy-session --compositor mangowc          # or pick "Canopy (MangoWC, beta)" at login
canopy-session --compositor labwc            # back to the default, unchanged
```

What the installer does, and does not do:

- installs the `mangowm` package when the distribution has one (Arch does;
  Debian/Fedora/openSUSE builds are not packaged — the script says so and points
  at the upstream repository),
- writes `~/.config/mango/config.conf` from `config/mangowc/config.conf` **only
  if you do not have one** and keeps a copy under
  `/usr/local/share/canopy/mangowc/` (or `$XDG_DATA_HOME/canopy/mangowc/`),
- adds `/usr/local/share/wayland-sessions/canopy-mangowc.desktop`,
- never touches `~/.config/labwc`, the labwc session entry, or the labwc theme.

## What the shell does on MangoWC

The shell already had a MangoWC backend before this session existed: it detects
the compositor (`MANGO_INSTANCE_SIGNATURE`, or the session's desktop name) and
uses MangoWC's socket for workspaces and window state, so the bar's workspace
indicator and the dock's running indicators are driven by the compositor rather
than guessed from `wlr-foreign-toplevel-management`.

Consequences worth knowing before you file a bug:

- **no server-side decorations** — that is MangoWC's design, not a Canopy bug,
- **tiling by default** — `Super+Space` cycles layouts, `Super+F` toggles
  floating for a window,
- **tags are workspaces** — the bar shows four of them, same as labwc,
- **blur is unavailable** — the shell already simulates it; MangoWC offers no
  background-effect protocol either.

## Adding another compositor

1. Check `src/compositors/compositor_detect.cpp` — if the compositor is already
   detected, only a session path is needed; otherwise add a backend next to the
   existing `labwc/`, `mango/`, `sway/` ones.
2. Add `canopy_pkgs <name>` in `scripts/lib-distro.sh` for the distributions
   that package it.
3. Add a `.desktop` session file in `config/` and install it from
   `install.sh` behind a `--with-<name>` flag, so the default session is never
   affected.
4. Document it in this file with the same "what differs" list.