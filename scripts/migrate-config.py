#!/usr/bin/env python3
"""Bring an existing Canopy config up to the current defaults.

A user config is never replaced wholesale (people edit it), and a config that is
never updated means shipped design changes never reach anyone - which is how a
desktop ends up "still looking the same" after a redesign.

So this only rewrites a key when its current value is still the *old shipped
value*. Anything the user has changed, or added, is left alone. Comments,
ordering and formatting are preserved.

    python3 scripts/migrate-config.py [--dry-run] [path]

Exit status is 0 whether or not anything changed.
"""

from __future__ import annotations

import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

# (section, key, old value, new value). Values are compared as written, without
# surrounding whitespace, so `0.92` and `0.92 ` both match but `1.0` does not.
MIGRATIONS: list[tuple[str, str, str, str]] = [
    # Canopy's face and signature accents. (Older configs were moved to Inter and
    # neutral hairlines for a Fluent pass; those read as generic, so both come
    # back.)
    ("shell", "font_family", '"Inter"', '"Space Grotesk"'),
    # The menu bar carries the workspace switcher, the way every desktop does.
    ("bar.main", "start", '["launcher", "wordmark", "active_window"]',
     '["launcher", "wordmark", "workspaces", "active_window"]'),
    # Fluent elevation is a hint, not a halo.
    ("shell.shadow", "alpha", "0.45", "0.35"),
    # Neutral hairlines; the accent is for interaction.
    ("bar.main", "border", '"primary"', '"outline_variant"'),
    ("bar.main", "border", '"outline"', '"outline_variant"'),
    ("bar.main", "thickness", "32", "34"),
    # Floating sidebar capsule from the original design.
    ("bar.tray", "thickness", "60", "56"),
    ("bar.tray", "radius", "30", "28"),
    ("bar.main", "widget_spacing", "6", "8"),
    # Dock: icons fill the pill (56 in 76) instead of floating in padding.
    ("dock", "icon_size", "44", "56"),
    ("dock", "cross_axis_padding", "14", "4"),
    ("dock", "item_spacing", "16", "14"),
    ("dock", "inactive_scale", "0.92", "1.0"),
    ("dock", "radius", "8", "20"),
    ("dock", "radius_top_left", "8", "20"),
    ("dock", "radius_top_right", "8", "20"),
    ("dock", "radius_bottom_left", "8", "20"),
    ("dock", "radius_bottom_right", "8", "20"),
    ("dock", "margin_edge", "10", "12"),
    ("dock", "shadow", "true", "false"),
    # Launcher buttons go back to the traditional glyph. An image path here was
    # silently dropped in the dock, and a font glyph cannot fail to resolve.
    ("dock", "launcher_custom_image",
     '"~/.local/share/icons/hicolor/scalable/apps/canopy.png"', '""'),
    ("dock", "launcher_custom_image_colorize", "true", "false"),
    ("widget.launcher", "custom_image",
     '"~/.local/share/icons/hicolor/scalable/apps/canopy.png"', '""'),
    ("widget.launcher", "custom_image_colorize", "true", "false"),
    ("widget.launcher", "glyph", '"canopy"', '"grid-dots"'),
    # Acrylic toasts.
    ("notification", "background_opacity", "0.95", "0.92"),
]

# The compositor config (canopywc) has its own shipped defaults and its own
# lifetime: it is seeded on first session start and then belongs to the user.
MIGRATIONS_COMPOSITOR: list[tuple[str, str, str, str]] = [
    # Fluent corner scale.
    ("appearance", "corner_radius", "12", "8"),
    # Mica, not flat grey.
    ("appearance.blur", "radius", "6", "8"),
    ("appearance.blur", "noise", "0.0", "0.03"),
    ("appearance.blur", "brightness", "1.0", "1.02"),
    ("appearance.blur", "saturation", "1.0", "1.15"),
    # 28 px macOS caption; traffic lights on the left, drawn as circles.
    ("appearance.title_bar", "height", "30", "28"),
    ("appearance.title_bar", "button_position", '"right"', '"left"'),
    ("appearance.title_bar", "button_corner_radius", "12", "100"),
    # Neutral outline instead of an accent ring around every focused window.
    ("colors.border", "focused", '"#3A3652FF"', '"#7C5CFCFF"'),
    ("colors.border", "unfocused", '"#26243AFF"', '"#2C2939FF"'),
    ("colors.border", "outer", '"#1E1C29FF"', '"#14131CFF"'),
]

# Keys that did not exist in older configs. Added under their section when
# missing, so a shipped default can appear without touching anything the user
# wrote. (section, key, value)
ADDITIONS: list[tuple[str, str, str]] = []

# Default keybinds added after the compositor config was first seeded. A chord
# the user already bound (to anything, including a different action) is left
# alone, so rebinding always wins. (chord, value)
KEYBIND_ADDITIONS: list[tuple[str, str]] = [
    # Screenshots.
    ("Print", '{ action = "spawn canopy msg screenshot-region", repeat = false }'),
    ("Shift+Print", '{ action = "spawn canopy msg screenshot-fullscreen", repeat = false }'),
    ("Mod+Print", '{ action = "spawn canopy msg screenshot-window", repeat = false }'),
    ("Mod+Shift+Print", '{ action = "spawn canopy msg screenshot-annotate", repeat = false }'),
    # Laptop hardware keys wlroots forwards but nothing was bound to.
    ("XF86KbdBrightnessUp",
     '{ action = "spawn canopy msg keyboard-backlight-up", allow_when_locked = true }'),
    ("XF86KbdBrightnessDown",
     '{ action = "spawn canopy msg keyboard-backlight-down", allow_when_locked = true }'),
    ("XF86AudioMicMute",
     '{ action = "spawn canopy msg mic-mute", allow_when_locked = true, repeat = false }'),
    # Daily toggles: the shell owns the state, these just ask it.
    ("Mod+Shift+N", '{ action = "spawn canopy msg notification-dnd-toggle", repeat = false }'),
    ("Mod+Shift+L", '{ action = "spawn canopy msg nightlight-toggle", repeat = false }'),
    ("Mod+Shift+C", '{ action = "spawn canopy msg caffeine-toggle", repeat = false }'),
    ("Mod+Shift+D", '{ action = "spawn canopy msg theme-mode-toggle", repeat = false }'),
    # Alt+Tab stays the fast cycle; the visual switcher gets its own chord.
    ("Mod+Tab", '{ action = "spawn canopy msg window-switcher", repeat = false }'),
    ("Mod+Control+L", '{ action = "spawn canopy msg lock-and-suspend", repeat = false }'),
]

SECTION_RE = re.compile(r"^\s*\[([^\]]+)\]\s*$")
# A comment only starts at whitespace + '#': colours are written "#RRGGBBAA" and
# an earlier version of this pattern ate them, silently skipping their keys.
KEY_RE = re.compile(
    r"^(?P<indent>\s*)(?P<key>[A-Za-z0-9_]+)(?P<sep>\s*=\s*)(?P<value>.*?)(?P<rest>\s+(?:#.*)?)?$"
)


def migrate_text(text: str, migrations=MIGRATIONS, keybinds=False) -> tuple[str, list[str]]:
    updated, applied = _rewrite_values(text, migrations)
    updated, added = _add_missing_keys(updated)
    if keybinds:
        updated, binds = _add_missing_keybinds(updated)
        added += binds
    return updated, applied + added


def _section_bounds(lines: list[str], header: str) -> tuple[int | None, int]:
    """Return (header line index, exclusive end) for a TOML table."""
    start = None
    for index, line in enumerate(lines):
        if line.strip() == header:
            start = index
            break
    if start is None:
        return None, 0

    for index in range(start + 1, len(lines)):
        if SECTION_RE.match(lines[index]):
            return start, index
    return start, len(lines)


def _add_missing_keybinds(text: str) -> tuple[str, list[str]]:
    """Append shipped default keybinds whose chord is not already present."""
    lines = text.splitlines(keepends=True)
    applied: list[str] = []
    if not KEYBIND_ADDITIONS:
        return text, applied

    start, _ = _section_bounds(lines, "[keybinds]")
    if start is None:
        return text, applied

    missing = []
    for chord, value in KEYBIND_ADDITIONS:
        pattern = re.compile(r'^\s*"' + re.escape(chord) + r'"\s*=')
        _, end = _section_bounds(lines, "[keybinds]")
        if any(pattern.match(line) for line in lines[start + 1 : end]):
            continue
        missing.append((chord, value))

    if not missing:
        return text, applied

    # Insert after the last setting in the table, before any trailing blanks or
    # comments, so the block stays with the rest of the binds.
    start, end = _section_bounds(lines, "[keybinds]")
    insert_at = end
    for index in range(end - 1, start, -1):
        stripped = lines[index].strip()
        if stripped.startswith("#") or not stripped:
            continue
        insert_at = index + 1
        break
    else:
        insert_at = start + 1

    block = [f'"{chord}" = {value}\n' for chord, value in missing]
    lines[insert_at:insert_at] = block
    applied.extend(f"[keybinds] {chord}: added" for chord, _ in missing)
    return "".join(lines), applied


def _add_missing_keys(text: str) -> tuple[str, list[str]]:
    lines = text.splitlines(keepends=True)
    applied: list[str] = []

    for section, key, value in ADDITIONS:
        header = f"[{section}]"
        start = None
        for index, line in enumerate(lines):
            if line.strip() == header:
                start = index
                break
        if start is None:
            continue

        end = len(lines)
        for index in range(start + 1, len(lines)):
            if SECTION_RE.match(lines[index]):
                end = index
                break

        if any(KEY_RE.match(l.rstrip("\n")) and KEY_RE.match(l.rstrip("\n")).group("key") == key
               for l in lines[start + 1 : end]):
            continue

        # Insert after the last setting in the section, before any trailing blanks.
        insert_at = end
        for index in range(end - 1, start, -1):
            stripped = lines[index].strip()
            if stripped.startswith("#") or not stripped:
                continue
            insert_at = index + 1
            break
        else:
            insert_at = start + 1

        lines.insert(insert_at, f"{key} = {value}\n")
        applied.append(f"[{section}] {key}: added {value}")

    return "".join(lines), applied


def _rewrite_values(text: str, migrations=MIGRATIONS) -> tuple[str, list[str]]:
    wanted: dict[tuple[str, str], list[tuple[str, str]]] = {}
    for section, key, old, new in migrations:
        wanted.setdefault((section, key), []).append((old, new))
    applied: list[str] = []
    section = ""
    out: list[str] = []

    for line in text.splitlines(keepends=True):
        match = SECTION_RE.match(line)
        if match:
            section = match.group(1).strip()
            out.append(line)
            continue

        key_match = KEY_RE.match(line.rstrip("\n"))
        if not key_match:
            out.append(line)
            continue

        key = key_match.group("key")
        rules = wanted.get((section, key))
        if not rules:
            out.append(line)
            continue

        current = key_match.group("value").strip()
        rule = next(((old, new) for old, new in rules if current == old), None)
        if rule is None:
            out.append(line)
            continue

        old, new = rule

        rebuilt = (
            f"{key_match.group('indent')}{key}{key_match.group('sep')}{new}"
            f"{key_match.group('rest') or ''}"
        )
        out.append(rebuilt + ("\n" if line.endswith("\n") else ""))
        applied.append(f"[{section}] {key}: {old} -> {new}")

    return "".join(out), applied


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    compositor = "--compositor" in argv
    migrations = MIGRATIONS_COMPOSITOR if compositor else MIGRATIONS
    paths = [a for a in argv[1:] if not a.startswith("-")]
    if not paths:
        print("migrate-config: no path given", file=sys.stderr)
        return 2

    for raw in paths:
        path = Path(raw).expanduser()
        if not path.is_file():
            print(f"migrate-config: {path} does not exist, nothing to do")
            continue

        original = path.read_text(encoding="utf-8")
        updated, applied = migrate_text(original, migrations, keybinds=compositor)
        if not applied:
            print(f"migrate-config: {path} is up to date")
            continue

        print(f"migrate-config: {path}: {len(applied)} setting(s) updated")
        for line in applied:
            print(f"  {line}")

        if dry_run:
            continue

        backup = path.with_suffix(path.suffix + f".bak-{datetime.now():%Y%m%d-%H%M%S}")
        shutil.copy2(path, backup)
        path.write_text(updated, encoding="utf-8")
        print(f"  backup: {backup}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))