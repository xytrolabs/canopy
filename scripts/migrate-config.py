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
    # Fluent pass: one UI face, shipped with the shell.
    ("shell", "font_family", '"Space Grotesk"', '"Inter"'),
    # The menu bar carries the workspace switcher, the way every desktop does.
    ("bar.main", "start", '["launcher", "wordmark", "active_window"]',
     '["launcher", "wordmark", "workspaces", "active_window"]'),
    # Fluent elevation is a hint, not a halo.
    ("shell.shadow", "alpha", "0.45", "0.35"),
    # Neutral hairlines; the accent is for interaction.
    ("bar.main", "border", '"primary"', '"outline_variant"'),
    ("bar.main", "widget_spacing", "6", "8"),
    # Dock: icons fill the pill (56 in 76) instead of floating in padding.
    ("dock", "icon_size", "44", "56"),
    ("dock", "cross_axis_padding", "14", "4"),
    ("dock", "item_spacing", "16", "14"),
    ("dock", "inactive_scale", "0.92", "1.0"),
    ("dock", "radius", "12", "8"),
    ("dock", "radius_top_left", "12", "8"),
    ("dock", "radius_top_right", "12", "8"),
    ("dock", "radius_bottom_left", "12", "8"),
    ("dock", "radius_bottom_right", "12", "8"),
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
    ("colors.border", "focused", '"#7C5CFCFF"', '"#3A3652FF"'),
    ("colors.border", "unfocused", '"#2C2939FF"', '"#26243AFF"'),
    ("colors.border", "outer", '"#1E1C29FF"', '"#14131CFF"'),
]

# Keys that did not exist in older configs. Added under their section when
# missing, so a shipped default can appear without touching anything the user
# wrote. (section, key, value)
ADDITIONS: list[tuple[str, str, str]] = [
    # The dock launcher was a generic grid glyph; it is the Canopy mark now.
    ("dock", "launcher_custom_image", '"~/.local/share/icons/hicolor/scalable/apps/canopy.png"'),
    ("dock", "launcher_custom_image_colorize", "true"),
]

SECTION_RE = re.compile(r"^\s*\[([^\]]+)\]\s*$")
# A comment only starts at whitespace + '#': colours are written "#RRGGBBAA" and
# an earlier version of this pattern ate them, silently skipping their keys.
KEY_RE = re.compile(
    r"^(?P<indent>\s*)(?P<key>[A-Za-z0-9_]+)(?P<sep>\s*=\s*)(?P<value>.*?)(?P<rest>\s+(?:#.*)?)?$"
)


def migrate_text(text: str, migrations=MIGRATIONS) -> tuple[str, list[str]]:
    updated, applied = _rewrite_values(text, migrations)
    updated, added = _add_missing_keys(updated)
    return updated, applied + added


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
    wanted = {(section, key): (old, new) for section, key, old, new in migrations}
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
        rule = wanted.get((section, key))
        if rule is None:
            out.append(line)
            continue

        old, new = rule
        if key_match.group("value").strip() != old:
            out.append(line)
            continue

        rebuilt = (
            f"{key_match.group('indent')}{key}{key_match.group('sep')}{new}"
            f"{key_match.group('rest') or ''}"
        )
        out.append(rebuilt + ("\n" if line.endswith("\n") else ""))
        applied.append(f"[{section}] {key}: {old} -> {new}")

    return "".join(out), applied


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    migrations = MIGRATIONS_COMPOSITOR if "--compositor" in argv else MIGRATIONS
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
        updated, applied = migrate_text(original, migrations)
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