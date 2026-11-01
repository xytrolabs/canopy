import os
OUT = "/run/media/raf/Z/Willow-Canopy/config/labwc/themes/canopy/openbox-3"
W = H = 12

def disc(radius=5.0):
    cx = cy = (W - 1) / 2.0
    rows = []
    for y in range(H):
        line = ""
        for x in range(W):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            line += "#" if d <= radius else "."
        rows.append(line)
    return rows

def blank():
    return ["." * W] * H

def write_xbm(name, rows):
    body = []
    for r in rows:
        r = r.ljust(W, ".")
        b1 = b2 = 0
        for i, ch in enumerate(r[:8]):
            if ch == "#": b1 |= (1 << i)
        for i, ch in enumerate(r[8:12]):
            if ch == "#": b2 |= (1 << i)
        body.append("0x%02x, 0x%02x" % (b1, b2))
    text = ("#define im_width %d\n#define im_height %d\n"
            "static unsigned char im_bits[] = {\n  %s };\n"
            % (W, H, ",\n  ".join(body)))
    open(os.path.join(OUT, name), "w").write(text)

os.makedirs(OUT, exist_ok=True)
DOT = disc(5.0)
for button in ("close", "iconify", "max", "restore", "desk"):
    for state in ("unpressed", "pressed", "hover", "toggled", "toggled-unpressed"):
        write_xbm("%s-%s.xbm" % (button, state), DOT)
write_xbm("bullets.xbm", blank())
write_xbm("disabled.xbm", blank())

TITLE="#1E1E26"; TITLE_I="#191920"; TEXT="#F2F2F5"; TEXT_I="#8E8E9A"; ACCENT="#7C5CFC"
themerc = """# Canopy window decoration - macOS traffic lights
border.width: 1

window.active.border.color: #2C2C38
window.inactive.border.color: #232330

window.active.title.bg: flat solid
window.active.title.bg.color: %s
window.inactive.title.bg: flat solid
window.inactive.title.bg.color: %s

window.active.label.bg: parentrelative
window.inactive.label.bg: parentrelative
window.label.text.justify: center
window.active.label.text.color: %s
window.inactive.label.text.color: %s

# traffic-light dots
window.button.width: 22
window.button.height: 22
window.button.spacing: 2

window.active.button.unpressed.bg: parentrelative
window.inactive.button.unpressed.bg: parentrelative

window.active.button.close.unpressed.image.color: #FF5F57
window.active.button.close.hover.image.color: #FF8A84
window.active.button.close.pressed.image.color: #E0443E
window.active.button.iconify.unpressed.image.color: #FEBC2E
window.active.button.iconify.hover.image.color: #FFD470
window.active.button.iconify.pressed.image.color: #DEA123
window.active.button.max.unpressed.image.color: #28C840
window.active.button.max.hover.image.color: #5AE070
window.active.button.max.pressed.image.color: #20A934

window.inactive.button.close.unpressed.image.color: #4A4A55
window.inactive.button.iconify.unpressed.image.color: #4A4A55
window.inactive.button.max.unpressed.image.color: #4A4A55

window.button.hover.bg.color: #00000000
window.button.hover.bg.corner-radius: 0

menu.border.width: 1
menu.border.color: #2C2C38
menu.items.bg.color: #1E1E26
menu.items.text.color: %s
menu.items.active.bg.color: %s
menu.items.active.text.color: #FFFFFF
menu.separator.color: #2C2C38
menu.title.bg.color: %s
menu.title.text.color: %s
""" % (TITLE, TITLE_I, TEXT, TEXT_I, TEXT, ACCENT, TITLE, TEXT)
open(os.path.join(OUT, "themerc"), "w").write(themerc)
print("theme regenerated")
