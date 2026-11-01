# Canopy — Component Reuse Report

**Date:** 2026-10-31 · **Target stack:** Labwc 0.20.2 (wlroots) + Quickshell 0.3.2 + Qt 6.12 / QML
**Scope:** identify existing implementations worth reusing instead of rebuilding, and
establish a reuse strategy that preserves Canopy's identity (top panel / left tray /
bottom dock, "Mac functionality, Windows simplicity, Canopy identity").

---

## 0. Executive summary

| Candidate | Language / stack | License | Verdict for Canopy |
|---|---|---|---|
| **Quickshell** | C++ core, QML API | **LGPL-3.0** (+GPL-3.0 parts) | **Adopt as the platform.** Its service modules already cover ~60% of what Canopy needs. No code copying — we consume it as a library. |
| **Noctalia** | **C++ 97.9%**, native Wayland/OpenGL ES, *no Qt* | **MIT** | **Reference only.** Zero code reuse possible (wrong stack), but it **officially supports Labwc** → the single most valuable integration reference. |
| **Caelestia Shell** | QML 60% + C++ 31% | **GPL-3.0** | **Reference only.** Hyprland-coupled *and* copyleft — copying QML would relicense Canopy. |
| **Dux Shell** | Quickshell / QML (Material 3) | MIT (per Arch) | **Low value.** Material 3 aesthetic conflicts with Canopy's Windows/macOS blend. |
| **KDE plasma-workspace / plasma-desktop** | C++ + QML, KDE Frameworks | GPL-2.0+ / LGPL | **Reference only.** Tied to KWin + PlasmaCore; unusable outside Plasma. Useful for IA of Settings and notification spec details. |

**Strategic conclusion:** Canopy should stay a **Quickshell application**, drawing
features from Quickshell's service layer rather than reimplementing protocols, and use
Noctalia (Labwc-specific behaviour) and Caelestia (QML patterns) as *reading material*,
not as source.

---

## 1. Quickshell (platform) — what we already get for free

Source: `quickshell-mirror/quickshell` · License **LGPL-3.0** · installed 0.3.2
Relevant trees: `src/services/*`, `src/wayland/*`

| Feature | Quickshell module | Canopy status |
|---|---|---|
| Layer-shell surfaces | `Quickshell.Wayland._WlrLayerShell` (`PanelWindow`, `WlrLayershell.layer/keyboardFocus/mask`) | **In use** — panel, tray, dock, launcher, calendar, lock |
| Foreign toplevels (window list, activate, minimize) | `Quickshell.Wayland._ToplevelManagement` | **In use** — dock sections |
| Notifications (freedesktop server) | `Quickshell.Services.Notifications` | **In use** — centre + history |
| StatusNotifier tray items + DBusMenu | `Quickshell.Services.SystemTray`, `Quickshell.DBusMenu` (`QsMenuAnchor`) | **In use** — background apps, right-click menus |
| Audio | `Quickshell.Services.Pipewire` | **In use** — volume slider |
| Battery / power | `Quickshell.Services.UPower` | **In use** |
| Network | `Quickshell.Networking` | **In use** — Wi-Fi toggle + list |
| Bluetooth | `Quickshell.Bluetooth` | **In use** |
| Application discovery | `DesktopEntries` / `DesktopEntry` (`Quickshell`) | **In use** — launcher, dock |
| PAM authentication | `Quickshell.Services.Pam` (`PamContext`) | **In use** — lock screen |
| Greetd (display-manager client) | `Quickshell.Services.Greetd` | **Available, unused** — see §7 |
| Idle inhibit / notify | `Quickshell.Wayland._IdleInhibitor`, `_IdleNotify` | **Used** (lock), idle-notify pending |
| Screencopy | `Quickshell.Wayland._Screencopy` | **Available, unused** — needed for Mission Control thumbnails |
| MPRIS | `Quickshell.Services.Mpris` | Available, unused — media widget |
| Polkit agent | `Quickshell.Services.Polkit` | Available, unused |
| IPC | `Quickshell.Io.IpcHandler` | **In use** — `quickshell ipc call canopy lock` |
| File I/O | `Quickshell.Io.FileView` | Available — settings read-back pending |
| **Session lock (`ext-session-lock-v1`)** | **absent in 0.3.2** | Blocked — see §6 |

**Adaptation complexity:** none (already integrated). **Recommendation: reuse.**

---

## 2. Noctalia — most relevant *behavioural* reference (MIT, supports Labwc)

Source: `noctalia-dev/noctalia` · **MIT** · C++ 97.9%, no Qt/GTK.

- Explicitly lists **Labwc** among supported compositors, with workspace integration via
  compositor-native backends or `ext-workspace-v1`.
- Owns: multi-monitor bars, dock, launcher, control centre, notification toasts/history,
  wallpaper picker, OSDs, **lock screen**, session panel, tray, clipboard history.
- Ships `ARCHITECTURE.md`, `SCOPE.md` — strong design references.

**Reuse verdict:** *reference*. Cannot be linked (different toolkit, no Qt), and no QML
to copy. Actionable takeaways for Canopy:

1. Treat *workspace data* as a pluggable backend: Labwc exposes none over IPC → keep our
   dots as indicators until `ext-workspace-v1` lands in Labwc (see §5).
2. Their feature split (shell owns surfaces + services; session actions separate) matches
   Canopy's structure — keep it.
3. Multi-monitor is per-output surfaces, not one stretched surface — Canopy still needs
   this (see §8).

---

## 3. Caelestia Shell — QML patterns only (GPL-3.0)

Source: `caelestia-dots/shell` · **GPL-3.0** · QML 59.9%, C++ 31.1%, releases v2.5.0.

- Hard dependency on **Hyprland**: keybinds via Hyprland global shortcuts, monitor list via
  `hyprctl monitors`. Uses `quickshell-git`, not the tagged release.
- Heavy deps (caelestia-cli, libcava, aubio, ddcutil, m3shapes, Material fonts).

**Reuse verdict:** *reference only — do not copy.* GPL-3.0 code would relicense Canopy.
Patterns worth mirroring (independently implemented): JSON config with per-monitor
overrides, colour scheme derivation from wallpaper, `Visual`-style shared image component.

---

## 4. Dux Shell & KDE — deprioritised

- **Dux**: Material 3 Quickshell shell. Aesthetic mismatch; nothing we lack.
- **KDE plasma-workspace / plasma-desktop**: GPL/LGPL, C++ + KDE Frameworks, bound to KWin
  and PlasmaCore. Cannot be embedded. Only value: Settings IA (sidebar + panes — already
  mirrored in our Settings window) and the notifications spec details.

---

## 5. Feature matrix — what to reuse, adapt, reference, or build

| Feature | Best existing implementation | Where | Deps | License | Labwc compatibility | Complexity | Verdict |
|---|---|---|---|---|---|---|---|
| App launcher | Canopy launcher (Quickshell `DesktopEntries`) | `shell/shell.qml` | Qt only | ours | Full | — | **keep / extend** |
| Dock + task mgmt | Quickshell `ToplevelManager` | `_ToplevelManagement` | Qt | LGPL-3 | Full (wlr-foreign-toplevel) | Low | **reuse** |
| System tray + context menus | Quickshell `SystemTray` + `QsMenuAnchor` | `services/sni`, `DBusMenu` | Qt, DBus | LGPL-3 | Full | Low | **reuse** |
| Quick settings / control centre | Canopy QS panel (Quickshell services) | `shell/shell.qml` | Qt | ours | Full | — | **keep / extend** |
| Notifications | Quickshell `Notifications` | `services/notifications` | Qt, DBus | LGPL-3 | Full | Low | **reuse** |
| Virtual desktops | **none usable** — Labwc has no IPC/`ext-workspace-v1` | — | — | — | **No** | High | **implement later** (keybind-only today) |
| Window overview (Mission Control) | Quickshell `Screencopy` + `Toplevel.setRectangle`; Caelestia/Noctalia switchers as reference | `_Screencopy` | Qt | LGPL-3 | Partial — works, but no thumbnails without screencopy per-output | High | **adapt (build in Canopy)** |
| Lock screen | Canopy lock (Quickshell `Pam`) — **implemented this pass** | `shell/shell.qml` | Qt, PAM | ours | Works as overlay; **not** a true session lock | Done | **keep; upgrade when `ext-session-lock` binding exists** |
| Display manager / greeter | Quickshell `Services/Greetd` | `services/greetd` | Qt, greetd | LGPL-3 | N/A (runs pre-compositor) | Medium | **adapt** |
| Settings app | Canopy Settings (implemented) | `shell/shell.qml` | Qt | ours | Full | — | **keep / extend** |
| Audio / net / BT / battery | Quickshell `Pipewire`, `Networking`, `Bluetooth`, `UPower` | `services/*` | Qt, DBus | LGPL-3 | Full | Low | **reuse** |
| Multi-monitor | Quickshell `ShellScreen` / `Variants` | core | Qt | LGPL-3 | Full | Medium | **adapt** (per-output surfaces pending) |
| Theming / config | Canopy `Theme.qml` singleton + `settings.json` | `shell/` | Qt | ours | Full | — | **keep; add read-back** |
| Wallpaper | `swaybg`/`hyprpaper` external; Noctalia has built-in picker | — | external | varies | `swaybg` works | Low | **reference** |
| Clipboard history | `wl-clipboard` + `cliphist` | — | external | GPL/MIT | Full | Low | **reference** |

---

## 6. Compositor-specific gaps (the important section)

These are the places where a Hyprland feature **does not** transfer to Labwc:

1. **Workspace switching.** Hyprland exposes `hyprctl dispatch workspace`; Labwc has no IPC.
   → Canopy keeps `Super+1..4` keybinds and **indicator-only** dots until Labwc implements
   `ext-workspace-v1`. Do not fake it.
2. **Global shortcuts.** Caelestia binds actions via Hyprland's global-shortcuts portal.
   Labwc has no such portal → Canopy uses `rc.xml` `<keybind>` → `quickshell ipc call canopy …`
   (already wired for `W-l` lock).
3. **Session lock.** `ext-session-lock-v1` is not exposed by Quickshell 0.3.2, so our lock is
   an **Overlay layer-shell surface** with exclusive keyboard focus. Consequences to state
   honestly: other clients are not suspended, so this is a *screen guard*, not a secure lock.
   Upgrade path: adopt `ext-session-lock-v1` (swaylock-style) once Quickshell binds it, or
   shell out to `swaylock` as an interim.
4. **Blur / acrylic.** No `ext-background-effect-v1` in Labwc 0.20 → translucency is alpha
   only. Any "acrylic" look from Noctalia/Caelestia is not reproducible here.
5. **Window animations / overview effects.** Labwc has no window-animation protocol.
   Mission Control therefore must be a *screenshot grid*, not a live-scaled window grid.

---

## 7. Implemented in this pass

- **Lock screen** (`shell/shell.qml`): Quickshell `PamContext` with `config: "login"`,
  password field, failure message, Cancel, live clock, avatar, Overlay layer with
  `WlrKeyboardFocus.Exclusive`. Trigger: `quickshell ipc call canopy lock`, bound to
  **Super+L** in `config/labwc/rc.xml`.
- **IPC surface**: `IpcHandler { target: "canopy" }` exposing `lock`, `unlock`,
  `openLauncher`, `openSettings`, `openNotifications`, `openQuickSettings` — the extension
  point every future keybind uses.
- Verified rendering in a nested Labwc session.

---

## 8. Recommended roadmap (derived from this research)

1. **Settings persistence read-back** via `Quickshell.Io.FileView` (small, unblocks all
   customisation). 
2. **Multi-monitor**: one `Variants`/per-`ShellScreen` instance of panel/tray/dock instead of
   global surfaces.
3. **Greeter**: `Quickshell.Services.Greetd` client + `greetd` config → real "display manager"
   story (the piece we do *not* have).
4. **Mission Control**: `Screencopy` per output + `Toplevel.setRectangle()` grid; reference
   Noctalia's switcher, implement independently.
5. **True session lock**: `ext-session-lock-v1` when available; `swaylock` binding meanwhile.
6. **MPRIS media widget** and **Polkit agent**: both free from Quickshell services.

---

## 9. Licensing guidance for contributors

- **Quickshell**: LGPL-3.0 — link/interpret freely; our QML stays ours. If we ever ship a
  modified Quickshell, that modification must be LGPL.
- **Noctalia (MIT)**, **Dux (MIT)**: patterns are freely reusable, but neither has QML to port.
- **Caelestia (GPL-3.0)** and **KDE (GPL/LGPL)**: **do not copy code or QML**. Reading for
  design is fine; shipping derived code would force Canopy to GPL-3.0.
- Canopy's own tree remains original work (currently MIT `LICENSE`).
