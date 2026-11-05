# Canopy identity

Canopy is a fork of Noctalia. Forking the code is the easy half; what makes a
desktop feel like *itself* is a small number of decisions applied consistently.
This file is that list, so a change can be judged against it instead of taste.

## What Canopy is

A desktop that stays out of the way: one thin bar, one island, one dock, and
windows that look like they belong to the same system as the panels.

- **Calm over clever.** No animation that exists only to show off. Panels appear
  where you look, not where they are easiest to draw.
- **One surface per job.** The menu bar is a bar, the side island is a pill, the
  dock is islands. Nothing is a floating card unless it is a flyout.
- **Type does the work.** Space Grotesk for anything that names something,
  Inter for text, JetBrains Mono for numbers.

## The mark

`assets/canopy.png` is the launcher mark; `canopy.svg` is the vector version for
menu entries and window icons. The mark is drawn in the accent colour
(`custom_image_colorize = true`), so it follows the palette instead of carrying
its own colours — that is what makes it read as part of the system rather than
a sticker.

## Colour

Canopy has its own palette, `Canopy`, defined in
`src/theme/builtin_palettes.cpp` (dark **and** light, plus a terminal ANSI set):

| token | dark | light |
| --- | --- | --- |
| primary (accent) | `#7C5CFC` violet | `#6246EA` |
| secondary | `#56CCF2` sky | `#1B7F9E` |
| tertiary | `#F2C14E` amber | `#8A5B00` |
| surface | `#14131C` | `#FBFAFF` |
| surfaceVariant | `#1E1C29` | `#F1F0F7` |
| onSurface | `#F2F0F7` | `#171622` |
| outline | `#2C2939` | `#DAD7E6` |

Rules:

- Violet is the *only* accent. It marks "this is Canopy": the launcher mark, the
  active item, the selected row, the menu-bar hairline.
- Amber and sky are for state (warning, information), never for decoration.
- Surfaces are near-black with a violet cast, not neutral grey. Neutral grey is
  what makes a fork look like the thing it forked.

The Willow edition deliberately reuses Canopy's surfaces with a green accent —
same skeleton, different brand. If a palette is missing, the shell falls back to
the upstream one and the desktop silently stops looking like Canopy; that is why
the palette name in `config/canopy/config.toml` (`builtin = "Canopy"`) is part of
the identity contract.

## Materials

There is no background blur on labwc (no `ext-background-effect-v1`), so depth is
built from three things, always together:

1. **Translucency** — panels at 0.78–0.88 opacity.
2. **A hairline** — 1 px `outline`, or the accent for the menu bar.
3. **A shadow** — soft, offset, never a glow.

An acrylic panel without the hairline looks broken; a shadow without translucency
looks like a 2010 theme.

## Spacing

- Everything is a multiple of **4 px**; panels pad by 8–12.
- Icons sit in a cell with **6 px** of padding. A pill that is trimmed to the icon
  edge reads as cramped — that is a bug, not a style.

## Type

- Wordmark: Space Grotesk, sentence case, never all-caps.
- Window and panel titles: Space Grotesk semibold at 10–11 px.
- Body and menus: Inter 10.
- Numbers (clock, sysmon): JetBrains Mono.

## Voice

Short, literal, no upstream jargon and no product names from the codebase
("plugin", "hook", "widget" are fine; "Noctalia", "palette token", "compositor
socket" are not). Error messages say what to do next.

## Where the identity actually lives

| Surface | File |
| --- | --- |
| Palette, accent, ANSI | `src/theme/builtin_palettes.cpp` (`Canopy`) |
| Menu bar, island, dock geometry | `config/canopy/config.toml` |
| Window decorations (SSD) | `config/labwc/themes/canopy/openbox-3/` |
| Window decorations (CSD apps) | `config/gtk-3.0/gtk.css`, `config/gtk-4.0/gtk.css` |
| Login screen | `greeter/assets/` |
| Wallpapers | `assets/wallpapers/` |
| Type | `assets/fonts/` |

## Known gaps

These still carry upstream's design language and are the honest answer to "it
has no soul of its own yet":

- the launcher's layout and search presentation,
- the control centre (tiles, section order),
- notification toasts (spacing, corner treatment),
- the lock screen.

Each of them is a localised change; none of them requires touching the shell's
architecture. Pick one and it gets the palette, the type scale and the materials
above.