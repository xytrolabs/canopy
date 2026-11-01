-- Canopy configuration
-- (Loaded by legacy integrations; Quickshell reads theme tokens from Theme.qml)

canopy = {}

canopy.theme = "dark"      -- "light" or "dark"
canopy.accent = "#7C5CFC" -- Xytro Labs restrained violet

canopy.panel = {
    height = 40,
    position = "top",
}

canopy.tray = {
    position = "left",
    width = 72,
}

canopy.dock = {
    icon_size = 48,
    pinned = { "firefox", "thunar", "code-oss", "kitty" },
}

canopy.workspaces = 4
