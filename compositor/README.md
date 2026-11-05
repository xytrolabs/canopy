# canopywc — the Canopy compositor

`canopywc` is the compositor half of Canopy: it draws the windows, the shadows,
the blur and the title bars that the shell composes its desktop on top of. It is
a traditional desktop — windows stack, you place them, and an edge drop zone
snaps them into halves and quarters — with tiling layouts there for anyone who
wants them, per workspace, without leaving the session.

It is built on [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) and on
`canopyfx`, the in-tree scene graph and renderer.

## What it gives Canopy that labwc could not

- **Real blur.** Surfaces that ask for translucency get the wallpaper and the
  windows behind them blurred, not a flat tint standing in for depth.
- **Title bars drawn by the compositor**, in Canopy's palette and shape, so a
  GTK app, a Qt app and a terminal all carry the same window chrome.
- **Shadows and rounded corners** everywhere, including client-side decorated
  windows, with a hairline that matches the shell's own surfaces.
- **Animations** on open, close, move and workspace switches.

## Layout

`stacking` is the default and what Canopy ships: focus follows your clicks,
windows keep the size you give them, and dragging to an edge fills half or a
quarter of the output. `scrolling`, `dwindle` and `master` remain available per
workspace through `workspace-set-layout` or by setting `layout.mode`.

## Install and run

```sh
meson setup build --buildtype=release
meson compile -C build
```

In the Canopy tree, `sh scripts/build-compositor.sh` does the same and puts the
binary in `build-compositor/`, and `sh scripts/canopy-session --compositor
canopywc` starts a session with it.

## Configuration

The session seeds [`../config/compositor.toml`](../config/compositor.toml) to
`~/.config/canopywc/config.toml` on first start; edits apply as soon as the
file is saved. [`examples/config.toml`](examples/config.toml) is the fully
commented reference, and `canopywc config validate` checks a file without
starting a session. The reference documentation lives in [`docs/user`](docs/user).

```sh
canopywc msg panel-toggle launcher   # talk to the running compositor
canopywc windows                     # what is open
canopywc outputs                     # what it is drawing on
```

## Acknowledgements

`canopywc` is a fork of [Umbriel](https://github.com/noctalia-dev/umbriel),
which in turn is the compositor half of
[Noctalia](https://github.com/noctalia-dev/noctalia). Their design, keybinds and
protocol work carried over wholesale; the identity, the layout default and the
look are Canopy's. Thank you to the Umbriel and Noctalia authors and
contributors — the projects below are the ones they thanked, and we owe them
the same.

- [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) — the compositor library.
- [SceneFX](https://github.com/wlrfx/scenefx) — `canopyfx` is a hard fork of it (MIT).
- [niri](https://github.com/YaLTeR/niri) — the scrolling layout and animation ideas.
- [Hyprland](https://github.com/hyprwm/Hyprland) — the visual effects those ideas grew from.

## License

MIT. See [LICENSE](LICENSE) for details; the upstream copyright notice is
retained there, as the license requires.