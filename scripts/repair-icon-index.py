#!/usr/bin/env python3
"""Complete a hicolor icon-theme index so every real directory is visible.

A user hicolor theme shadows the system one: the index defines the *only*
directories that exist, so a stanza the index forgets makes those icons invisible
to every application. A hand-written index that lists `scalable/apps` but not
`scalable/status` is why a tray icon can vanish while its file sits on disk.

This keeps the user's own icons, and completes the index from the system
hicolor theme: every directory listed by either theme that actually exists
becomes a `Directories` entry with a proper stanza. Nothing is deleted.

    python3 scripts/repair-icon-index.py [--dry-run] [theme-dir ...]
"""

from __future__ import annotations

import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

SYSTEM_THEME = Path("/usr/share/icons/hicolor")
DEFAULTS = [Path.home() / ".local/share/icons/hicolor", Path("/usr/local/share/icons/hicolor")]

SECTION_RE = re.compile(r"^\s*\[([^\]]+)\]\s*$")


def parse_index(path: Path) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """Return ({section: lines}, {'': header lines}). Keeps formatting."""
    sections: dict[str, list[str]] = {}
    order: list[str] = []
    current = ""
    if not path.is_file():
        return {}, []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = SECTION_RE.match(line)
        if match:
            current = match.group(1).strip()
            order.append(current)
            sections[current] = []
        else:
            sections.setdefault(current, []).append(line)
    return sections, order


def listed_dirs(lines: list[str]) -> list[str]:
    for line in lines:
        if line.strip().startswith("Directories"):
            return [d.strip() for d in line.split("=", 1)[1].split(",") if d.strip()]
    return []


def dirs_on_disk(root: Path) -> list[str]:
    found: list[str] = []
    if not root.is_dir():
        return found
    for entry in sorted(root.iterdir()):
        if not entry.is_dir():
            continue
        if entry.name.startswith("."):
            continue
        for child in sorted(entry.iterdir()):
            if child.is_dir():
                found.append(f"{entry.name}/{child.name}")
    return found


def synthesise_stanza(directory: str) -> list[str]:
    context = directory.split("/", 1)[1] if "/" in directory else "Apps"
    context = {
        "apps": "Applications",
        "status": "Status",
        "mimetypes": "MimeTypes",
        "places": "Places",
        "devices": "Devices",
        "categories": "Categories",
        "actions": "Actions",
        "emblems": "Emblems",
        "animations": "Animations",
        "intl": "International",
    }.get(context, "Applications")
    size_part = directory.split("/", 1)[0]
    if size_part.startswith("scalable"):
        return [
            f"[{directory}]",
            "Size=64",
            "MinSize=8",
            "MaxSize=512",
            "Type=Scalable",
            f"Context={context}",
            "",
        ]
    match = re.match(r"(\d+)x\d+", size_part)
    size = match.group(1) if match else "48"
    return [f"[{directory}]", f"Size={size}", f"Context={context}", "Type=Fixed", ""]


def repair(theme_dir: Path, dry_run: bool) -> bool:
    index = theme_dir / "index.theme"
    if not index.is_file():
        print(f"repair-icon-index: no index.theme in {theme_dir}, skipping")
        return False

    text = index.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    declared = listed_dirs(lines)

    available: list[str] = []
    seen: set[str] = set()
    for directory in declared + dirs_on_disk(theme_dir) + dirs_on_disk(SYSTEM_THEME):
        if directory in seen:
            continue
        exists = (theme_dir / directory).is_dir() or (SYSTEM_THEME / directory).is_dir()
        if not exists:
            continue
        seen.add(directory)
        available.append(directory)

    added = [d for d in available if d not in declared]
    system_sections, _ = parse_index(SYSTEM_THEME)

    missing_stanzas = [
        d for d in available if d not in declared and not any(
            SECTION_RE.match(line) and SECTION_RE.match(line).group(1).strip() == d
            for line in lines
        )
    ]

    if not added and not missing_stanzas:
        print(f"repair-icon-index: {index} already lists every directory")
        return False

    print(f"repair-icon-index: {index}")
    if added:
        print(f"  Directories += {', '.join(added)}")
    for directory in missing_stanzas:
        print(f"  stanza += [{directory}]")

    if dry_run:
        return True

    out: list[str] = []
    wrote_directories = False
    for line in lines:
        if not wrote_directories and line.strip().startswith("Directories"):
            out.append("Directories=" + ",".join(available))
            wrote_directories = True
            continue
        out.append(line)
    if not wrote_directories:
        out.insert(1, "Directories=" + ",".join(available))

    for directory in missing_stanzas:
        out.append("")
        out.extend(system_sections.get(directory) or synthesise_stanza(directory))

    backup = index.with_suffix(index.suffix + f".bak-{datetime.now():%Y%m%d-%H%M%S}")
    shutil.copy2(index, backup)
    index.write_text("\n".join(out).rstrip("\n") + "\n", encoding="utf-8")
    print(f"  backup: {backup}")

    cache = theme_dir / "icon-theme.cache"
    if cache.exists():
        cache.unlink()
        print("  removed stale icon-theme.cache")

    return True


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    targets = [Path(os.path.expanduser(a)) for a in argv[1:] if not a.startswith("-")]
    if not targets:
        targets = DEFAULTS
    for target in targets:
        repair(target, dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))