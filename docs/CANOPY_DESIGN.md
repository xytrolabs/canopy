# Canopy desktop

Canopy is Xytro Labs' desktop environment: a native Wayland shell on **Labwc**,
built on the Noctalia v5 foundation.

**Powerful when needed. Simple by default.** Mac functionality with Windows
simplicity.

## Surfaces

| Surface | Default position | Implementation |
|---|---|---|
| System Panel | top, floating, 34 px | `[bar.main]` |
| System Tray | left, vertical pill (56 px) | `[bar.tray]` |
| Dock | bottom centre, floating | `[dock]` |
| Quick Settings | right, floating | `[shell.panel]` placement + `[control_center]` |
| Launcher | centred, floating | `[shell.launcher]` |

All of it is one process. There is no separate bar daemon, notification daemon,
launcher process, dock process or settings process: they share one event loop,
one theme palette, one configuration store and one IPC socket.

## Design system

| Token | Value |
|---|---|
| Accent (dark / light) | `#8B6BFF` / `#6D4CF5` |
| Dark surfaces | `#14121A` / `#1E1B26` |
| Light surfaces | `#FAF9FD` / `#F0EDF7` |
| Corner scale | 1.0 (`theme.corner_radius_scale`) |
| Panel translucency | glass, 0.82 opacity, compositor blur |
| Animation | enabled, speed 1.0 |
| UI font | Inter |
| Icons | Tabler icon font bundled in the asset bundle |

The palette is a built-in theme named `Canopy`, so it is also available to the
template engine (GTK, Qt, kitty, alacritty, btop, KDE colour scheme).

Surfaces stay legible with `[backdrop] enabled = false` and
`[shell.animation] enabled = false`; neither effect is required for the design
to read correctly.

## Configuration

One store: `~/.config/canopy/config.toml` (state lives in
`~/.local/state/canopy/`). Settings, the shell and the CLI all read and write
that same file, so edits from the GUI, the panel and `canopy msg config-set`
cannot disagree.

`scripts/install.sh` seeds the file from `config/canopy/config.toml` only when
one does not already exist.

## Labwc integration

| Need | Mechanism |
|---|---|
| Session start | `config/labwc/autostart` starts `canopy` |
| Launcher key | `Super_L` → `canopy msg panel-toggle launcher` |
| Lock key | `Super+L` → `canopy msg session lock` |
| Window rules, decoration | `config/labwc/rc.xml` + `themes/canopy` |
| Workspaces | `ext-workspace-v1` (verified under Labwc) |
| Minimize / restore | `ext-foreign-toplevel-list-v1` minimize state, used by the dock |

No compositor-internal API is used; everything goes through protocols Labwc
implements.

## Known limitations

- Labwc does not expose a "minimize animation" hook, so restored windows appear
  immediately.
- ICC/gamma control is not available under Labwc, so Night Light uses the
  compositor's colour management where present and is otherwise a no-op.
- External public-IP, weather, community palette and community template
  features use the upstream Noctalia endpoints. Canopy runs without them; the
  shell logs one warning per unavailable endpoint.