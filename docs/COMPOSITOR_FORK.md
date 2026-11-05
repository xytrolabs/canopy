# Canopy's own compositor

Status: **rebranded, building, and running the shell headless.** The fork lives
at `compositor/`, is called `canopywc`, and defaults to a stacking desktop.

## Why this is the right move

Canopy currently runs on labwc, and three of the complaints this project keeps
running into are labwc's limits, not the shell's:

| Complaint | Root cause in labwc |
| --- | --- |
| "the decorations look outdated" | labwc draws openbox-3 titlebars; every visual is baked into 14 px bitmaps |
| "it doesn't look like one system" | CSD apps draw their own headerbar; we fight it with a GTK stylesheet |
| no real depth | labwc has no `ext-background-effect-v1`, so "blur" is translucency + a border |

[Umbriel](https://github.com/noctalia-dev/umbriel) is the compositor half of the
Noctalia project — the same codebase Canopy forked. It has, in its own words,
*blur, shadows, rounded corners, double borders, animations, GLSL effect
presets*, optional **title bars**, layer shell, session lock, Xwayland and a
live-reloaded TOML config.

Forking it means Canopy stops decorating around a compositor and starts owning
the whole stack.

## Evidence it is viable here

Checked on this machine (2026-11-04, Umbriel `b6c4b7d`):

- `git clone --depth=1` → **14 MB**, MIT licence, meson + C++23.
- Every dependency is already installed: `wlroots-0.20 0.20.2` (Umbriel pins
  `>=0.20.1 <0.21`, and labwc already needs 0.20), `libei-1.0 1.6`,
  `lcms2 2.20`, `libdisplay-info 0.3`, `nlohmann_json 3.12`,
  `tomlplusplus 3.4`, `pixman 0.46`, `libdrm 2.4.134`, `wayland-server 1.26`.
- `meson setup` → 219 targets, no missing dependency, **no root required**.
- `ninja` → builds clean (`umbriel` binary produced).

So the fork is not a research project; it compiles today.

### In the tree

It is vendored at `compositor/` (a squashed subtree of upstream `b6c4b7d`,
12 MB) and builds from there:

```sh
sh scripts/build-compositor.sh                     # -> build-compositor/canopywc
sh scripts/canopy-session --compositor canopywc     # a session with it
```

`canopy-session --list-compositors` shows it next to labwc and MangoWC.

### What the rebrand changed

The whole tree now speaks Canopy — 970 files, no `umbriel` left outside the
upstream copyright in `LICENSE`:

| Was | Is |
| --- | --- |
| binary `umbriel`, `start-umbriel` | `canopywc`, `start-canopywc` |
| `~/.config/canopy/config.toml` | `~/.config/canopywc/config.toml` |
| `UMBRIEL_SOCKET` | `CANOPY_SOCKET` |
| `$XDG_RUNTIME_DIR/umbriel-<display>.sock` | `canopywc-<display>.sock` |
| `umbriel.service`, `umbriel-session.target` | `canopywc.service`, `canopywc-session.target` |
| `umbrielfx` (the scene graph) | `canopyfx` |
| C++ namespace `umbriel::` | `canopy::` |
| desktop entry *Umbriel* | *Canopy*, `DesktopNames=Canopy` |

The compositor config deliberately does **not** live in `~/.config/canopy/`:
the shell merges every `*.toml` in that directory as shell configuration, so a
`compositor.toml` there was parsed as a shell config and warned about every
key. It gets its own directory, named after the binary.

The ported documentation, effect presets and keybind reference all point at
Canopy paths and the in-tree `compositor/docs/user/` reference.

### Stacking, not tiling

Canopy is a traditional desktop, so `layout.mode` defaults to `stacking` in the
source (`Config::Layout::mode`), not only in the shipped config: a fresh
session with no config file behaves the same way. Windows keep their size,
edge and corner drop zones fill halves and quarters, and the tiling layouts
stay available per workspace.

### Keeping up with upstream

```sh
git fetch umbriel main
git subtree pull --prefix=compositor umbriel <commit> --squash
```

The first pull after this rebrand will conflict: upstream edits `umbriel`
identifiers, this tree renamed them. Resolve by taking upstream's behaviour
and re-applying the rename (`sed -e 's/UMBRIEL/CANOPY/g' -e 's/Umbriel/Canopy/g'
-e 's/umbriel/canopy/g'`), or cherry-pick the upstream commit instead of
merging. `LICENSE` keeps the upstream copyright notice, which the MIT terms
require.

### Smoke test

Run headless with the real shell as its autostart, the fork brings Canopy up
unchanged: the bar reserves its 32 px strip, the wallpaper loads, the shell
registers its NetworkManager and BlueZ agents, and a screenshot shows the
full-width accent hairline `#7C5CFC` on row 0 with the bar body below it. The
only failures in the log are the ones a nested test cannot avoid (no PipeWire,
polkit already owned by the host session).

### The integration already exists

`src/compositors/umbriel/` in the Canopy shell is a complete backend:
`umbriel_runtime`, `umbriel_event_handler`, `umbriel_workspace_backend`,
`umbriel_output_backend`, `umbriel_keyboard_backend`, `umbriel_audio_provider`.
The backend now accepts both `CANOPY_SOCKET` and `UMBRIEL_SOCKET`, and both the
`canopywc-<display>.sock` and `umbriel-<display>.sock` runtime paths, so a
stock Umbriel session and the fork are the same thing to the shell.

Nothing in the shell has to be written for a first session — it is the
compositor that needs rebranding.

## What a fork actually costs

1. **A moving target.** Umbriel has no releases, 147 open issues and commits
   every few hours. We would pin a commit and re-sync deliberately, not daily.
2. **Rebrand surface** (mechanical, and the shell taught us the rule: rename
   what users see, leave internal namespaces alone):

   | Umbriel | Canopy |
   | --- | --- |
   | `umbriel` binary, `start-umbriel` | `canopywc`, `start-canopywc` |
   | `~/.config/umbriel/config.toml` | `~/.config/canopy/compositor.toml` |
   | `UMBRIEL_SOCKET` | `CANOPY_SOCKET` (also read by the shell backend) |
   | `umbriel.service`, `data/*.desktop` | `canopywc.service`, session entry |
   | `xdg-desktop-portal-umbriel` | stays upstream for now (portal fork is separate work) |
   | logo, cheat-sheet strings, docs links | Canopy mark and voice |

3. **Two build systems in one repo** (meson for both, so this is cheap).
4. **A second release artefact** in `build-release.sh` and CI.

## Plan

**Phase 0 — vendor and build (no user-visible change).**
Add the fork, build it in CI next to the shell, add `docs/` for the pin. labwc
stays the default session.

**Phase 1 — session.**
`canopy-session --compositor canopywc` (same pattern as `--compositor mangowc`),
its own session entry and config, installed behind `--with-compositor`. The
shell talks to it through the existing Umbriel backend.

**Phase 2 — identity.**
Canopy palette into the compositor's appearance config, title bars styled to
match the shell's pills, keybinds mirroring `config/labwc/rc.xml`, and the
menu-bar accent hairline becomes a real border rather than a fallback.

**Phase 3 — default.**
Flip the default session only when a checklist passes: bar/dock/tray render,
portals, screenshots, screen share, Xwayland, lock screen, HDR off by default,
and a week of daily use.

## What stays

- The shell is unaffected — it already speaks Umbriel's IPC.
- labwc remains a supported session (and the fallback) for as long as we ship.
- Nothing in `config/labwc` or the openbox theme is deleted by this work.

## Open decision

Where the fork lives:

1. **Monorepo subtree** at `compositor/` — one clone, one CI, atomic changes
   across shell and compositor. Larger repo (14 MB + history).
2. **Separate repository**, vendored by release tarball — keeps this repo the
   size it is, but shell/compositor changes can no longer land together.