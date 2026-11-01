# Canopy interaction layer

Canopy's shell surfaces (panel, tray, dock, launcher, quick settings, settings)
all share one interaction implementation. This document describes it, how to use
it, and what has actually been verified.

## Coordinate model (why tooltips used to appear near the panel)

Every Canopy surface is its own `wlr-layer-shell` window. Qt has no position for
such a window, so `Item.mapToGlobal()` answers with *window-local* pixels. A dock
icon 46 px from the top of the 112 px dock window therefore reported y ≈ 46
instead of y ≈ screenHeight − 46, and the tooltip was drawn near the top of the
screen. Quickshell's `itemRect()` is not uniform on 0.3.2 either — measured with
a real pointer it returned a screen-space X but a window-local Y.

`Components/Coords.qml` therefore computes the window origin from the surface's
own layer-shell geometry (readable `anchors` / `margins` / `screen` on the
`WlrLayershell` window) and adds the item's position inside that window:

```qml
originX = anchors.right && !anchors.left ? screen.width - window.width - margins.right : margins.left
originY = anchors.bottom && !anchors.top ? screen.height - window.height - margins.bottom : margins.top
```

No magic offsets, and it holds for any edge, any alignment, any resolution and
any scale factor. Tooltip and menu placement both go through it.

## Components

Everything lives in `shell/Components/` (module `Canopy.Components`).

| File | Purpose |
| --- | --- |
| `Tooltip.qml` | `singleton Tooltip` — global tooltip controller. `show(item, title, detail, placement)` / `hide()`. One hover delay (400 ms) and one look for the whole shell. |
| `MenuController.qml` | `singleton MenuController` — global context-menu controller. `show(items, item, placement)`, `showAt(items, x, y)`, `close()`, `activate(i)`, `moveSelection(delta)`, `activateSelected()`. |
| `Coords.qml` | `singleton Coords` — item → screen coordinate mapping (see above). |
| `CanopyTooltipCard.qml` | The tooltip surface: acrylic card, hairline border, title + optional detail line. |
| `CanopyMenuCard.qml` | The menu surface: fixed-width card that stacks `MenuItemRow`s. |
| `MenuItemRow.qml` | One menu row: fixed icon column, label, check mark, separator, danger and disabled states. |
| `IconButton.qml` | The single icon-button implementation (hover/pressed/active states, tooltip, left + right click). Used by the panel and the tray. |
| `InteractionOverlay.qml` | One Overlay-layer surface that renders every tooltip and every context menu, and owns menu keyboard navigation. |

### Adding a tooltip

```qml
HoverHandler {
    onHoveredChanged: {
        if (hovered) Tooltip.show(myButton, "Wi-Fi", "Right-click for networks", "right")
        else Tooltip.hide()
    }
}
```

`placement` is `bottom` (default), `top`, `right` or `left`. The overlay flips
the tooltip automatically when it would leave the screen, then clamps it.

Or simply use `IconButton`, which wires the tooltip, both mouse buttons and the
hover/pressed/active visuals in one place:

```qml
IconButton {
    iconName: "preferences-system-symbolic"
    label: "Settings"
    tipDetail: "Appearance, desktop, sound and more"
    tipPlacement: "right"
    onClicked: rootShell.openSettingsAt(0)
    onRightClicked: MenuController.show(rootShell.settingsTrayMenu(), this, "right")
}
```

### Adding a context menu

```qml
MenuController.show([
    { label: "Open", icon: "application-x-executable", run: function () { entry.execute() } },
    { label: "Show window", run: function () { toplevel.activate() } },
    { sep: true },
    { label: "Close window", icon: "window-close-symbolic", danger: true,
      run: function () { toplevel.close() } },
    { label: "Pin to dock", checked: rootShell.isPinned(entry.id), run: function () { ... } },
    { label: "Unavailable action", enabled: false }   // rendered greyed out
], sourceItem, "above")
```

Item schema: `label`, `icon`, `enabled`, `danger`, `checked`, `sep`, `run`.
Items without a `run` function and without `sep` are ignored, so a menu can only
ever contain actions that work — there is no such thing as a decorative entry.

While a menu is open the overlay's input region covers the screen, so any click
outside closes it and no tooltip can appear behind it.

## Where menus exist

| Surface | Trigger | Contents |
| --- | --- | --- |
| Dock — pinned app | right click | Open, **every `Actions=` entry from the application's own .desktop file, label and behaviour taken verbatim** (Firefox: New Window / New Private Window / Open Profile Manager; VS Code: New Empty Window), Show/Minimize/Close windows (only while running), Pin/Unpin |
| Dock — window | right click | Show, Minimize/Restore, Close, Pin/Unpin |
| Panel — Wi-Fi | right click | Wi-Fi on/off, available networks (connect/disconnect), Network settings |
| Panel — sound | right click | Mute/unmute, volume ±5 %, quick settings, Sound settings |
| Panel — battery | right click | Battery level (read-only), Power settings, Suspend |
| Panel — power | left or right click | Lock, Settings, Suspend, Log out, Restart, Shut down |
| Panel — background | right click | Quick settings, Notifications, Settings, Show desktop, Lock, Restart shell |
| Tray — Wi-Fi / sound / Bluetooth / battery / notifications / settings | right click | The same live actions, scoped to that icon |
| Desktop background | right click | Launcher, Settings, Change wallpaper, Show desktop, Notification centre, Lock |
| Tray — StatusNotifier item | right click | The application's own DBusMenu (`QsMenuAnchor`) |

## Keyboard: the Super key

Labwc is the only place that can see a global key press, so the binding lives in
`config/labwc/rc.xml`:

```xml
<keybind key="Super_L" onRelease="yes">
  <action name="Execute" command="quickshell -c canopy ipc call canopy toggleLauncher" />
</keybind>
```

Two details matter:

* `onRelease="yes"` fires only when Super is pressed and released on its own, so
  `Super+Return`, `Super+1…4` and friends keep working.
* The IPC client needs the **same `-c canopy` flag** as the running shell. Without
  it `quickshell ipc` cannot locate the instance and exits with
  `Could not find "default" config directory`. This was the actual reason the
  Super key "did nothing" — the previous `W-l` lock shortcut had the same bug and
  is fixed too.

The launcher takes `WlrKeyboardFocus.Exclusive` while visible, so typing searches
immediately, `Enter` launches the highlighted result, `Up`/`Down`/`Left`/`Right`
move the selection, and `Escape` closes it. Pressing Super again toggles it shut.

## IPC surface

`quickshell -c canopy ipc call canopy <function>` — every function is typed
(untyped QML parameters are `QVariant` and cannot cross the IPC boundary).

```
lock, unlock, openLauncher, toggleLauncher, closeAll,
openSettings, openSettingsAtPage(page), openNotifications, openQuickSettings,
settingsPage(i), setWallpaper(path), clearWallpaper, wallpaperMode(m),
panelHeight(v), panelVisible(on), trayPosition(p), trayIconSize(v), trayAutoHide(on),
dockAlignment(a), dockMargin(v), dockIconSize(v), dockMagnify(on), dockAutoHide(on),
themeMode(m), resetAll
```

Every one of these calls the *same* setter the corresponding settings control
calls, so the persisted value and the live UI cannot diverge.

## StatusNotifierItem applications (third-party tray icons)

Quickshell hands these over through `SystemTray.items`. Each item exposes
`activate()`, `secondaryActivate()`, `hasMenu` and a `menu` object.

* If `hasMenu` is true the item's **own** menu is opened with `QsMenuAnchor`
  (the application's DBusMenu). Canopy never replaces it with a generic menu.
  This requires `//@ pragma UseQApplication` at the top of `shell.qml` — without
  it every open fails with *"Cannot call QsMenuAnchor.open() as quickshell was
  not started in QApplication mode"*.
* If the item has no menu, right-click falls back to `secondaryActivate()`.
* Left click calls `activate()`.

## Icon system

`CanopyIcon` resolves every icon through one path:

1. `image://icon/<theme name>` (how StatusNotifierItems arrive) → the name is
   unwrapped and looked up in the generated index. Rendering the provider URL
   directly produced magenta/garbage pixmaps on this Qt build.
2. Absolute paths and `image://qspixmap/...` (an application's own pixmap) are
   used verbatim.
3. Otherwise `<name>` then `<name>-symbolic` in `icon-map.js` (28 971 entries,
   regenerated by `scripts/gen-icon-map.py`).
4. Fallback: a themed letter glyph (never a magenta block, never an emoji).

| Surface | Icons | Source |
| --- | --- | --- |
| Panel | launcher, network, volume, power (battery when present) | theme symbolic icons, tinted `Theme.textPrimary` |
| Tray | launcher, quick settings, network, sound, bluetooth, notifications, settings | theme symbolic icons, tinted |
| Tray | application icons (KMix, Cachy-Update, vesktop, …) | `image://icon/<name>` → icon index |
| Dock | pinned apps | `.desktop` `Icon=` → icon index |
| Dock | windows | `DesktopEntries.heuristicLookup(appId).icon` |
| Quick settings | network, bluetooth, battery | theme symbolic |
| Quick settings | appearance | multi-colour theme icon, deliberately **untinted** |
| Menus | dock/session/window items | desktop-entry icons + theme symbolic |

## App-provided menus vs Canopy menus

The rule is: **use what the application provides verbatim, and only add what the
operating system must do.**

* Tray applications: their DBusMenu is opened as-is via `QsMenuAnchor`.
* Dock applications: the application's own `.desktop` `Actions=` entries are
  listed with their original labels and executed through the entry's
  `DesktopAction`, so Canopy never invents or renames them.
* Canopy only adds the pieces no application exposes: launch, window management
  (show / minimize / close) for its own running windows, pinning, and Canopy's
  own system controls.
* Platform menus need a resolvable Qt icon theme. `config/qt6ct/qt6ct.conf` now
  sets `icon_theme=kora`; with the previous value the icons inside application
  menus (and the tray icons handed over as `image://icon/...`) were drawn as
  magenta placeholder blocks.

## Verification tooling

Real pointer and keyboard input is possible on this machine, so the behaviours
below were exercised rather than assumed:

* `/tmp/canopy-vptr` — small C client using `zwlr_virtual_pointer_manager_v1`
  for exact absolute pointer moves, left/right clicks (uinput absolute devices
  are ignored by libinput).
* `/tmp/vkeyd.py` — persistent uinput keyboard for key presses.
* Harness: isolated nested labwc session (`XDG_CONFIG_HOME=/tmp/ctest`, labwc
  autostart removed so exactly one shell runs), then `grim` screenshots per step.

## Verified behaviour

All rows below were exercised on a running desktop with a real virtual pointer
(`zwlr_virtual_pointer_manager_v1`) and a virtual keyboard - not inferred from
code or from menu-builder output alone.

| Check | Method | Result |
| --- | --- | --- |
| Dock tooltip position (centred dock) | hover Firefox icon | **PASS** - card directly above the icon |
| Dock tooltip uses the real app name | hover Thunar icon | **PASS** - "Thunar File Manager / Click to launch" |
| Panel tooltip | hover the power button (top-right) | **PASS** - below the icon, clamped to the screen edge |
| Tray tooltip | hover the tray launcher button | **PASS** - card to the right of the icon |
| Tray + dock tooltips in light theme | `themeMode light`, hover | **PASS** - legible card in both themes |
| Right-click a pinned dock app | right-click Firefox | **PASS** - Open / New Window / New Private Window / Open Profile Manager / Unpin from dock (the app's own actions, verbatim) |
| Right-click another pinned app | right-click VS Code | **PASS** - Open / New Empty Window / Unpin from dock |
| Right-click a third tray app | right-click Cachy-Update | **PASS** - its own menu with submenus and disabled rows, icons no longer magenta |
| Menu action executes | click "Unpin from dock" | **PASS** - icon removed, dock re-centred |
| Right-click a running app | launch alacritty, right-click its dock entry | **PASS** - Show window / Minimize / Close window / Pin |
| Running-app menu action | click "Minimize" | **PASS** - window minimised, entry moved to the minimized section |
| Tray application native menu | right-click a StatusNotifier item | **PASS** - the app's own DBusMenu (Open Discover... / Start Update / Refresh / Quit) |
| Tray Canopy control menu | right-click the Wi-Fi icon | **PASS** - Wi-Fi toggle + live networks (HOME-FB15 checked) |
| Desktop context menu | right-click empty desktop | **PASS** - opens at the pointer, "Show desktop" disabled with no windows |
| Menu dismissal | click elsewhere | **PASS** - menu closes and the click is not passed through |
| Menu keyboard navigation | right-click dock, Down, Down, Enter | **PASS** - highlight moves, Enter runs the highlighted action |
| Menu icon alignment | visual | **PASS** - fixed icon column, labels align with and without icons |
| Super opens the launcher | virtual keyboard KEY_LEFTMETA | **PASS** - launcher opens (labwc: `Handling action 5: Execute`, new layer surface) |
| Super closes the launcher | second KEY_LEFTMETA | **NOT VERIFIED** - the synthetic keyboard cannot deliver a second modifier press to the focused surface; the labwc binding plus an in-shell `Keys.onReleased` fallback are both in place |
| Launcher typing filters results | virtual keyboard T,H | **NOT VERIFIED** - synthetic keycodes reach the compositor (Super/Escape work) but arrive without keysyms, so no text is inserted |
| Launcher Escape closes | virtual keyboard KEY_ESC | **PASS** (observed once) |
| Tooltips after changing dock alignment | `dockAlignment left` + hover | **NOT VERIFIED** - that run left the launcher open and swallowed the hover; the code path is identical to the centred case |
| Settings persistence across restart | set values, kill, relaunch, no IPC | **PASS** - see the previous pass; unchanged by this work |
| Bundled fonts load without a system install | run from the repo in a nested session, `fc-list` shows no Space Grotesk | **PASS** - panel clock, app name, dock tooltips, quick settings and settings window all render Space Grotesk via `FontLoader` |
| Panel mark renders | launch shell, screenshot the panel | **PASS** - `assets/canopy-mark.svg` drawn by `IconButton.imageSource`; a relative path failed here, `Qt.resolvedUrl()` in `shell.qml` is required because the Image lives in `Components/` |
| Qt default face | `QT_QPA_PLATFORMTHEME=qt6ct` + installed `qt6ct.conf` | **PASS** - `[Fonts] general="Space Grotesk,11,…"`; Texts that name no family stop falling back to a generic sans |

## Typography and branding

Canopy does not inherit the machine's font. `shell/fonts/` carries nine TTFs and
`shell.qml` registers them with `FontLoader` before any surface is created:

| Token | Family | Used for |
| --- | --- | --- |
| `Theme.fontDisplay` | Space Grotesk | panel, dock, headings, clock |
| `Theme.fontBody` | Inter | long-form copy |
| `Theme.fontMono` | JetBrains Mono | numerals |
| `Theme.fontFamily` | = `fontDisplay` | the legacy name every existing component binds to |

`scripts/install.sh` also installs them to `~/.local/share/fonts/canopy` and sets
the Qt default in `config/qt6ct/qt6ct.conf`. The panel's launcher button carries
`shell/assets/canopy-mark.svg` (the accent tile with the arch) instead of a
themed grid glyph, so the panel reads as Canopy rather than as a toolkit bar.

## Session, screenshots and system settings

### Screenshots
`scripts/canopy-screenshot.sh` is installed to `~/.local/bin/canopy-screenshot`
and bound in `rc.xml`:

| Key | Action |
| --- | --- |
| `Print` | region capture (Flameshot) |
| `Shift+Print` | whole screen, saved to `~/Pictures/Screenshots` and copied to the clipboard |
| `Super+Shift+S` | region capture (Flameshot) |

Flameshot is the interactive default. Full-screen capture goes straight to
`grim` (instant, no daemon); if Flameshot is missing the region path falls back
to `slurp` + `grim` + `wl-copy`. The same helper is reachable from the power
menu and the desktop context menu ("Take screenshot…").

### Log out
Logging out asks **labwc itself** to exit (`labwc -e`), which tears the session
down cleanly and returns to the TTY or the display manager. The previous
implementation ran `loginctl terminate-user`, which killed the shell before the
session could close and left it hanging.

### Wi-Fi discovery
`WifiDevice.scannerEnabled` is switched on while a surface that lists networks
is open (quick settings) and off again when it closes, which is what makes
nearby networks appear. The quick-settings list shows the connected network
first, then the strongest ones, with signal percentage, a lock for secured
networks, a **Scan** button to force a rescan, right-click actions
(connect / disconnect / forget) and a link to Network settings. The tray's
network menu uses the same live list and adds "Scan for networks".

### Audio
PipeWire nodes are exposed directly:

* Quick settings: the current output device name, volume, a mute toggle on the
  speaker icon, and an **Output device** list where clicking a device switches
  the default (`Pipewire.preferredDefaultAudioSink`).
* Settings → Sound: output volume/mute, the output-device picker, and a
  microphone (default source) volume/mute section.

### Settings sizing
The Settings window used to size its page scroller from the *screen* height
(`win.height - 180`), so on anything above 720p the page spilled out of the
card. The sidebar and scroller are now sized from the card, the scroller takes
exactly the space the header leaves, and it clips and scrolls.

## Privacy: what Canopy reads

Canopy deliberately reads as little of the disk as it can:

* **Wallpapers** - only `~/.local/share/wallpapers`, `/usr/share/backgrounds` and
  `/usr/share/wallpapers`, at depth 2, capped at 40 entries. The user's
  `~/Pictures` library is **not** scanned unless they switch on
  *Settings > Appearance > Include my Pictures folder* (off by default,
  persisted as `includePictures`). Any other image can be picked explicitly with
  **Choose file...**, which uses the file dialog and nothing else.
* **Thumbnails** are decoded at 200x120 (`sourceSize`), so the picker never
  decodes full-resolution images.
* **Applications** come from the freedesktop `.desktop` entries, never from
  scanning the filesystem for executables.
* **Icons** are resolved through `icon-map.js`, generated at install time from
  the installed icon themes (file names only).

## Known limitations

* **Workspace indicators are not live.** Labwc 0.20 exposes no IPC or protocol
  for workspace queries, so the four dots render as unselected markers with
  tooltips rather than claiming which workspace is active.
* **No blur.** `ext-background-effect-v1` is not available on this compositor,
  so depth comes from layered translucency, hairlines and shadow rings.
* **Platform (DBusMenu) popups are drawn by Qt, not by Canopy**, so they use the
  Qt widget style rather than the Canopy menu design. This is deliberate: an
  application's own menu must not be reimplemented.
* **Some application tray icons are white-on-transparent** and low contrast on a
  light tray. A faint backplate is drawn behind StatusNotifier icons in light
  mode; the artwork itself is left untouched.
* **Synthetic input limits.** Pointer interaction is fully automatable. The
  synthetic keyboard delivers keycodes/modifiers to the compositor but not
  keysyms to the focused client, so launcher typing and the "Super twice" toggle
  remain manual checks.
