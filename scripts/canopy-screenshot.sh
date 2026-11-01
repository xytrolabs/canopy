#!/bin/sh
# canopy-screenshot - Canopy's default screenshot helper.
#
#   canopy-screenshot area     region capture (Flameshot when available)
#   canopy-screenshot screen   whole screen, saved + copied to the clipboard
#   canopy-screenshot window   interactive window/region via Flameshot
#
# Flameshot is Canopy's default capture tool. When it is not installed the
# helper falls back to grim + slurp + wl-copy, which work natively on Labwc.
set -u

mode="${1:-area}"
SHOTDIR="$HOME/Pictures/Screenshots"

have() { command -v "$1" >/dev/null 2>&1; }

save_with_grim() {
    mkdir -p "$SHOTDIR"
    file="$SHOTDIR/Canopy-$(date +%Y-%m-%d-%H%M%S).png"
    if grim "$file" 2>/dev/null; then
        if have wl-copy; then wl-copy < "$file" 2>/dev/null || true; fi
        notify-send "Screenshot saved" "$file" 2>/dev/null || true
        return 0
    fi
    return 1
}

case "$mode" in
    screen)
        # Full-screen capture goes straight to grim: it is instant, native and
        # needs no daemon. Flameshot stays the interactive (area) default.
        save_with_grim && exit 0
        if have flameshot; then exec flameshot full -p "$SHOTDIR"; fi
        ;;
    area|window|*)
        if have flameshot; then
            # Flameshot decides between region/window/full itself; "gui" opens
            # its launcher and the user can pick.
            exec flameshot gui
        fi
        if have slurp && have grim && have wl-copy; then
            geom=$(slurp) || exit 0
            grim -g "$geom" - | wl-copy
            exit 0
        fi
        save_with_grim && exit 0
        ;;
esac

echo "canopy-screenshot: no screenshot tool available (install flameshot, or grim+slurp)" >&2
exit 1
