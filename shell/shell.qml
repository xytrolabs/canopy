//@ pragma UseQApplication
// Required for platform (DBusMenu) popups: StatusNotifierItem applications
// expose their context menu as a DBusMenu, and QsMenuAnchor can only render it
// when Quickshell runs in QApplication mode. Without this line every tray
// application's native menu fails to open with
// "Cannot call QsMenuAnchor.open() as quickshell was not started in
// QApplication mode".
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Pam
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import "Settings"
import "Components"
import QtQuick.Controls

ShellRoot {
    id: rootShell

    // ---- Bundled typefaces ----------------------------------------------
    // These ship in shell/fonts and are also installed to the user's font
    // directory by scripts/install.sh, so the family names Theme uses resolve
    // whether Canopy runs from the repo or from an installed copy. Keep them
    // first: FontLoader registration must happen before the Text items in
    // this file are created.
    FontLoader { source: "fonts/SpaceGrotesk-Regular.ttf" }
    FontLoader { source: "fonts/SpaceGrotesk-Medium.ttf" }
    FontLoader { source: "fonts/SpaceGrotesk-SemiBold.ttf" }
    FontLoader { source: "fonts/SpaceGrotesk-Bold.ttf" }
    FontLoader { source: "fonts/Inter-Regular.ttf" }
    FontLoader { source: "fonts/Inter-Medium.ttf" }
    FontLoader { source: "fonts/Inter-SemiBold.ttf" }
    FontLoader { source: "fonts/JetBrainsMono-Regular.ttf" }
    FontLoader { source: "fonts/JetBrainsMono-Medium.ttf" }

    property bool launcherOpen: false
    property bool calendarOpen: false
    property string qsSection: "home"
    property string trayHoverTitle: ""
    property bool notificationsOpen: false
    property bool settingsOpen: false
    property int settingsPage: 0
    property bool dockAutoHideEnabled: true
    property bool panelVisible: true
    property bool trayAutoHide: true
    property real dockIconSize: 40
    property bool dockMagnify: true
    property bool showRecommended: true
    property bool notificationsEnabled: true
    property bool dnd: false
    property bool confirmReset: false

    // ---- Software updates -------------------------------------------------
    // Canopy is not packaged by any distribution, so it updates itself: the
    // same payload that installed it is what upgrades it. scripts/canopy-update.sh
    // does the work (check / download / verify / install) and this state is the
    // UI's view of it.
    property string installedVersion: ""
    property string availableVersion: ""
    property bool updateAvailable: false
    property bool updateChecking: false
    property bool updateInstalling: false
    property string updateStatus: ""
    property string updateError: ""
    property bool autoUpdate: true
    property double lastUpdateCheck: 0
    property bool updateNotified: false
    property string updateLog: ""

    readonly property string updateScript:
        (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config"))
        + "/quickshell/canopy/scripts/canopy-update.sh"

    // ---- Wallpaper & component customisation ----
    property string wallpaper: ""
    property string wallpaperMode: "crop"
    property int panelHeight: 34
    property string trayPosition: "left"
    property int trayIconSize: 22
    property string dockAlignment: "center"
    property int dockMargin: 12

    // ---- Single-source setters -------------------------------------------
    // Every settings control AND the IPC surface funnel through these, so the
    // persisted value, the live state and the desktop can never diverge.
    function setWallpaper(path: string) {
        wallpaper = String(path)
        store.wallpaper = wallpaper
    }
    function clearWallpaper() { setWallpaper("") }
    function setWallpaperMode(m) {
        const valid = ["crop", "fit", "stretch", "tile", "center"]
        wallpaperMode = valid.indexOf(m) >= 0 ? m : "crop"
        store.wallpaperMode = wallpaperMode
    }
    function setPanelHeight(v) {
        panelHeight = Math.min(48, Math.max(30, Math.round(v)))
        store.panelHeight = panelHeight
    }
    function setTrayPosition(pos) {
        trayPosition = (pos === "right") ? "right" : "left"
        store.trayPosition = trayPosition
    }
    function setTrayIconSize(v) {
        trayIconSize = Math.min(28, Math.max(16, Math.round(v)))
        store.trayIconSize = trayIconSize
    }
    function setDockAlignment(a) {
        dockAlignment = (a === "left" || a === "right") ? a : "center"
        store.dockAlignment = dockAlignment
    }
    function setDockMargin(v) {
        dockMargin = Math.min(40, Math.max(0, Math.round(v)))
        store.dockMargin = dockMargin
    }
    function setDockIconSize(v) {
        dockIconSize = Math.min(56, Math.max(28, Math.round(v)))
        store.dockIconSize = dockIconSize
    }
    function setDockMagnify(on) {
        dockMagnify = !!on
        store.dockMagnify = dockMagnify
    }
    function setPanelVisible(on) {
        panelVisible = !!on
        store.panelVisible = panelVisible
    }
    function setTrayAutoHide(on) {
        trayAutoHide = !!on
        store.trayAutoHide = trayAutoHide
    }
    function setDockAutoHide(on) {
        dockAutoHideEnabled = !!on
        store.dockAutoHide = dockAutoHideEnabled
    }
    function setThemeMode(m) {
        const valid = ["light", "dark", "auto"]
        const mode = valid.indexOf(m) >= 0 ? m : "dark"
        store.themeMode = mode
        Theme.applyThemeMode(mode, new Date().getHours())
    }
    function setAccent(c) {
        Theme.accent = String(c)
        store.accent = String(c)
    }
    function setTransparency(v) {
        Theme.acrylicOpacity = Math.min(1, Math.max(0.5, v))
        store.transparency = Theme.acrylicOpacity
    }
    function setAnimations(on) {
        Theme.animationsEnabled = !!on
        store.animations = Theme.animationsEnabled
    }
    function setUiScale(v) {
        Theme.uiScale = Math.min(1.3, Math.max(0.85, v))
        store.uiScale = Theme.uiScale
    }
    function setDensity(d) {
        Theme.density = Math.min(1.2, Math.max(0.85, d))
        store.density = Theme.density
    }

    // ---- Persistence ------------------------------------------------------
    // Explicit, file-backed settings store: ~/.config/canopy/settings.json.
    // Quickshell's PersistentProperties is kept as an in-memory mirror, but it
    // never reached disk on this build, so Canopy writes and reads the JSON
    // file itself. Reads once at start-up, writes (debounced) on every change.
    readonly property string settingsDir: (Quickshell.env("HOME") || "") + "/.config/canopy"
    readonly property string settingsPath: settingsDir + "/settings.json"
    property bool settingsReady: false
    property bool _applyingSettings: false

    function scheduleSave() {
        if (!settingsReady || _applyingSettings) return
        saveTimer.restart()
    }

    function flushSettings() {
        const o = {
            panelHeight: panelHeight,
            panelVisible: panelVisible,
            trayPosition: trayPosition,
            trayIconSize: trayIconSize,
            trayAutoHide: trayAutoHide,
            dockAlignment: dockAlignment,
            dockMargin: dockMargin,
            dockIconSize: dockIconSize,
            dockMagnify: dockMagnify,
            dockAutoHide: dockAutoHideEnabled,
            wallpaper: wallpaper,
            wallpaperMode: wallpaperMode,
            themeMode: Theme.themeMode,
            accent: String(Theme.accent),
            transparency: Theme.acrylicOpacity,
            animations: Theme.animationsEnabled,
            uiScale: Theme.uiScale,
            density: Theme.density,
            notificationsEnabled: notificationsEnabled,
            showRecommended: showRecommended,
            dnd: dnd,
            includePictures: includePictures,
            autoUpdate: autoUpdate,
            lastUpdateCheck: lastUpdateCheck,
            pinned: pinnedIds.join(",")
        }
        const json = JSON.stringify(o).replace(/'/g, "'\\''")
        const cmd = "mkdir -p '" + settingsDir + "' && printf '%s' '" + json
                    + "' > '" + settingsPath + "'"
        Quickshell.execDetached(["sh", "-c", cmd])
    }

    Timer {
        id: saveTimer
        interval: 350
        repeat: false
        onTriggered: rootShell.flushSettings()
    }

    Process {
        id: settingsReader
        command: ["sh", "-c", "cat '" + rootShell.settingsPath + "' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: rootShell.applySettingsJson(text)
        }
    }

    function applySettingsJson(txt) {
        let o = null
        try {
            if (txt && txt.trim() !== "") o = JSON.parse(txt)
        } catch (e) {
            o = null
        }
        if (!o) {
            // first run: nothing stored yet, keep the built-in defaults
            settingsReady = true
            return
        }
        _applyingSettings = true
        if (typeof o.panelHeight === "number") setPanelHeight(o.panelHeight)
        if (typeof o.panelVisible === "boolean") setPanelVisible(o.panelVisible)
        if (typeof o.trayPosition === "string") setTrayPosition(o.trayPosition)
        if (typeof o.trayIconSize === "number") setTrayIconSize(o.trayIconSize)
        if (typeof o.trayAutoHide === "boolean") setTrayAutoHide(o.trayAutoHide)
        if (typeof o.dockAlignment === "string") setDockAlignment(o.dockAlignment)
        if (typeof o.dockMargin === "number") setDockMargin(o.dockMargin)
        if (typeof o.dockIconSize === "number") setDockIconSize(o.dockIconSize)
        if (typeof o.dockMagnify === "boolean") setDockMagnify(o.dockMagnify)
        if (typeof o.dockAutoHide === "boolean") setDockAutoHide(o.dockAutoHide)
        if (typeof o.wallpaperMode === "string") setWallpaperMode(o.wallpaperMode)
        if (typeof o.wallpaper === "string") setWallpaper(o.wallpaper)
        if (typeof o.accent === "string") setAccent(o.accent)
        if (typeof o.transparency === "number") setTransparency(o.transparency)
        if (typeof o.animations === "boolean") setAnimations(o.animations)
        if (typeof o.uiScale === "number") setUiScale(o.uiScale)
        if (typeof o.density === "number") setDensity(o.density)
        if (typeof o.notificationsEnabled === "boolean") notificationsEnabled = o.notificationsEnabled
        if (typeof o.showRecommended === "boolean") showRecommended = o.showRecommended
        if (typeof o.dnd === "boolean") dnd = o.dnd
        if (typeof o.autoUpdate === "boolean") autoUpdate = o.autoUpdate
        if (typeof o.lastUpdateCheck === "number") lastUpdateCheck = o.lastUpdateCheck
        // NOTE: applied before the wallpaper scan result matters; the scan is
        // started from Component.onCompleted and re-run when this changes.
        if (typeof o.includePictures === "boolean") includePictures = o.includePictures
        if (typeof o.pinned === "string" && o.pinned !== "") {
            pinnedIds = o.pinned.split(",")
                                .map(function (x) { return x.trim() })
                                .filter(function (x) { return x !== "" })
        }
        // theme last, so mode + accent + scale land together
        if (typeof o.themeMode === "string") setThemeMode(o.themeMode)
        _applyingSettings = false
        settingsReady = true
    }

    // Any change to a live setting is written back (debounced).
    onPanelHeightChanged: scheduleSave()
    onPanelVisibleChanged: scheduleSave()
    onTrayPositionChanged: scheduleSave()
    onTrayIconSizeChanged: scheduleSave()
    onTrayAutoHideChanged: scheduleSave()
    onDockAlignmentChanged: scheduleSave()
    onDockMarginChanged: scheduleSave()
    onDockIconSizeChanged: scheduleSave()
    onDockMagnifyChanged: scheduleSave()
    onWallpaperChanged: scheduleSave()
    onWallpaperModeChanged: scheduleSave()
    onNotificationsEnabledChanged: scheduleSave()
    onShowRecommendedChanged: scheduleSave()
    onDndChanged: scheduleSave()
    onPinnedIdsChanged: scheduleSave()

    // Wi-Fi scanning only runs while something is actually listing networks.
    onQuickSettingsOpenChanged: setWifiScanning(quickSettingsOpen)

    function wallpaperFillMode() {
        if (wallpaperMode === "stretch") return Image.Stretch
        if (wallpaperMode === "fit") return Image.PreserveAspectFit
        if (wallpaperMode === "tile") return Image.Tile
        if (wallpaperMode === "center") return Image.Pad
        return Image.PreserveAspectCrop
    }

    ListModel { id: wallpaperModel }
    property alias wallpaperList: wallpaperModel

    // Opt-in: Canopy only reads wallpaper folders by default. Adding the user's
    // Pictures library is a deliberate choice, made in Settings > Appearance.
    property bool includePictures: false

    // Only wallpaper locations are searched, at a shallow depth and with a hard
    // cap, so the shell never crawls the user's photo library unless asked to.
    function wallpaperFindCommand() {
        const roots = ["\"$HOME/.local/share/wallpapers\"",
                       "/usr/share/backgrounds",
                       "/usr/share/wallpapers"]
        if (includePictures) roots.unshift("\"$HOME/Pictures\"")
        return "find " + roots.join(" ") + " 2>/dev/null "
               + "-maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' "
               + "-o -iname '*.png' -o -iname '*.webp' -o -iname '*.svg' \\) "
               + "| sort | head -40"
    }

    function rescanWallpapers() {
        wallpaperScan.running = false
        wallpaperScan.running = true
    }

    onIncludePicturesChanged: {
        scheduleSave()
        rescanWallpapers()
    }

    Process {
        id: wallpaperScan
        command: ["sh", "-c", rootShell.wallpaperFindCommand()]
        stdout: StdioCollector {
            onStreamFinished: {
                wallpaperModel.clear()
                const lines = (text || "").trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const l = lines[i].trim()
                    if (l !== "") wallpaperModel.append({ "path": l })
                }
            }
        }
    }

    Component.onCompleted: {
        wallpaperScan.running = true
        settingsReader.running = true
        // DesktopEntries is populated asynchronously; wait for it rather than
        // racing a first run that would otherwise pin nothing.
        defaultPinTimer.running = true
    }

    Timer {
        id: defaultPinTimer
        interval: 1500
        repeat: false
        running: false
        onTriggered: rootShell.applyDefaultPins()
    }

    readonly property int appCount: DesktopEntries.applications.values
                                    ? DesktopEntries.applications.values.length : 0
    readonly property int notificationCount: notificationModel.count

    // ---- Live system readouts shared by the panel, tray and dock ----
    readonly property real batteryPercent: (UPower.displayDevice && UPower.displayDevice.percentage > 0)
                                           ? UPower.displayDevice.percentage : -1
    readonly property bool hasBattery: batteryPercent >= 0
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property bool audioAvailable: !!(audioSink && audioSink.audio)
    readonly property real volumeLevel: audioAvailable ? audioSink.audio.volume : 0
    readonly property bool audioMuted: audioAvailable ? audioSink.audio.muted : false
    readonly property bool btAvailable: !!Bluetooth.defaultAdapter
    readonly property bool btEnabled: btAvailable ? Bluetooth.defaultAdapter.enabled : false

    // A vertical pill can only hold so much. Show the first few StatusNotifier
    // items and always keep Canopy's own controls reachable.
    readonly property var trayItems: asList(SystemTray.items).slice(0, 5)

    function batteryIconName() {
        if (!hasBattery) return "battery-missing-symbolic"
        if (batteryPercent >= 90) return "battery-full-symbolic"
        if (batteryPercent >= 50) return "battery-good-symbolic"
        if (batteryPercent >= 20) return "battery-low-symbolic"
        return "battery-caution-symbolic"
    }
    function volumeIconName() {
        if (!audioAvailable || audioMuted || volumeLevel <= 0.001) return "audio-volume-muted-symbolic"
        if (volumeLevel < 0.34) return "audio-volume-low-symbolic"
        if (volumeLevel < 0.67) return "audio-volume-medium-symbolic"
        return "audio-volume-high-symbolic"
    }
    function activeWindowTitle() {
        const t = ToplevelManager.activeToplevel
        return t ? (t.title || "") : ""
    }


    function allApps() { return DesktopEntries.applications.values || [] }

    function pinnableApps() {
        const apps = DesktopEntries.applications.values || []
        const out = []
        for (let i = 0; i < apps.length && out.length < 24; i++) {
            const a = apps[i]
            if (!a || a.noDisplay) continue
            if (pinnedIds.indexOf(a.id) >= 0) continue
            out.push(a)
        }
        return out
    }

    function isPinned(id) { return pinnedIds.indexOf(id) >= 0 }

    function togglePinned(id) {
        if (pinnedIds.indexOf(id) >= 0)
            pinnedIds = pinnedIds.filter(function (x) { return x !== id })
        else
            pinnedIds = pinnedIds.concat([id])
        store.pinned = pinnedIds.join(",")
    }

    function clearNotifications() { notificationModel.clear() }

    function sendTestNotification() {
        notificationModel.append({ "title": "Canopy", "body": "Notifications are working." })
    }

    function resetAppearance() {
        Theme.applyThemeMode("dark", 12)
        Theme.accent = "#7C5CFC"
        Theme.acrylicOpacity = 0.92
        Theme.animationsEnabled = true
        Theme.uiScale = 1.0
        Theme.density = 1.0
        store.themeMode = "dark"
        store.accent = "#7C5CFC"
        store.transparency = 0.92
        store.animations = true
        store.uiScale = 1.0
        store.density = 1.0
    }

    function restartShell() {
        // Kill by process name (-x): a `pkill -f <pattern>` also matches the
        // `sh -c` wrapper running the kill, so the pattern used to kill the
        // restart command itself and leave no shell at all. `-x quickshell`
        // catches every launch form (with and without -n) and nothing else.
        Quickshell.execDetached(["sh", "-c",
            "sleep 0.4; pkill -x quickshell; sleep 0.8; quickshell -n -c canopy >/dev/null 2>&1 &"])
    }

    // ---- Updates ----------------------------------------------------------
    function checkForUpdates(silent) {
        if (updateChecking || updateInstalling) return
        updateChecking = true
        if (!silent) updateStatus = "Checking…"
        updateError = ""
        updateCheckProc.running = true
    }

    function applyUpdateJson(txt) {
        try {
            const o = JSON.parse(String(txt || "{}"))
            if (o.installed) installedVersion = String(o.installed)
            if (o.latest) availableVersion = String(o.latest)
            updateAvailable = !!o.update_available
            if (o.error) {
                updateError = String(o.error)
                updateStatus = "Could not reach the release host"
            } else if (updateAvailable) {
                updateStatus = "Canopy " + availableVersion + " is available"
            } else {
                updateStatus = installedVersion !== "" ? ("Up to date · " + installedVersion) : "Up to date"
            }
        } catch (e) {
            updateError = "Unreadable response from the updater"
            updateStatus = updateError
        }
        lastUpdateCheck = Date.now()
        scheduleSave()
        if (updateAvailable && !updateNotified && notificationsEnabled) {
            updateNotified = true
            notificationModel.append({
                "title": "Canopy " + availableVersion + " is available",
                "body": "Open Settings → System to install, or run canopy-update apply."
            })
        }
    }

    function installUpdate() {
        if (updateInstalling) return
        updateInstalling = true
        updateStatus = "Installing " + availableVersion + "…"
        updateError = ""
        updateApplyProc.running = true
    }

    function setAutoUpdate(on) {
        autoUpdate = !!on
        scheduleSave()
    }

    // Read the version we are running, once, from the installed VERSION file.
    function loadInstalledVersion(txt) {
        const v = String(txt || "").trim()
        if (v !== "") installedVersion = v
    }

    Process {
        id: updateCheckProc
        command: ["sh", rootShell.updateScript, "check", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: rootShell.applyUpdateJson(text)
        }
        onExited: (code, status) => {
            rootShell.updateChecking = false
            if (code !== 0 && rootShell.updateError === "") {
                rootShell.updateError = "The update checker did not run"
                rootShell.updateStatus = rootShell.updateError
            }
        }
    }

    Process {
        id: updateApplyProc
        command: ["sh", rootShell.updateScript, "apply", "--yes"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: rootShell.updateLog = text
        }
        onExited: (code, status) => {
            rootShell.updateInstalling = false
            if (code === 0) {
                rootShell.updateStatus = "Updated to " + rootShell.availableVersion
                rootShell.installedVersion = rootShell.availableVersion
                rootShell.updateAvailable = false
                rootShell.updateNotified = false
                // The files under the running shell have just been replaced;
                // restart so every surface reloads the new build.
                rootShell.restartShell()
            } else {
                rootShell.updateStatus = "Update failed"
                rootShell.updateError = "The updater did not complete. Run canopy-update apply in a terminal."
            }
        }
    }

    // Version stamp written by the installer.
    Process {
        id: versionReader
        command: ["sh", "-c",
            "cat '" + (Quickshell.env("XDG_CONFIG_HOME")
                       || ((Quickshell.env("HOME") || "") + "/.config"))
            + "/quickshell/canopy/VERSION' 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: rootShell.loadInstalledVersion(text)
        }
    }

    // Check shortly after start, then once a day. A check uses the recorded
    // timestamp so a shell that is restarted often does not hammer the host.
    Timer {
        id: updateStartupTimer
        interval: 45000
        running: true
        repeat: false
        onTriggered: {
            if (!rootShell.autoUpdate) return
            const age = Date.now() - rootShell.lastUpdateCheck
            if (age > 24 * 60 * 60 * 1000) rootShell.checkForUpdates(true)
        }
    }
    Timer {
        id: updateDailyTimer
        interval: 24 * 60 * 60 * 1000
        running: rootShell.autoUpdate
        repeat: true
        onTriggered: rootShell.checkForUpdates(true)
    }

    function requestReset() {
        if (!confirmReset) {
            confirmReset = true
            resetGuard.restart()
            return
        }
        confirmReset = false
        resetAppearance()
        store.dockedReset = true
        pinnedIds = defaultPinnedIds()
        store.pinned = pinnedIds.join(",")
    }

    Timer {
        id: resetGuard
        interval: 4000
        onTriggered: rootShell.confirmReset = false
    }
    property bool locked: false
    property string lockMessage: ""

    // quickshell ipc call canopy lock
    IpcHandler {
        target: "canopy"
        function lock() { rootShell.closeOverlays(); rootShell.locked = true }
        function unlock() { rootShell.locked = false }
        function openLauncher() { rootShell.openLauncher() }
        function toggleLauncher() { rootShell.toggleLauncher() }
        function closeAll() { rootShell.closeOverlays() }
        function openSettings() { rootShell.openSettingsAt(rootShell.settingsPage) }
        function openSettingsAtPage(page: int) { rootShell.openSettingsAt(page) }
        function openNotifications() { rootShell.notificationsOpen = true }
        function openQuickSettings() { rootShell.quickSettingsOpen = true }

        // automation surface - same setters the UI uses
        function settingsPage(i: int) { rootShell.settingsPage = i }
        function setWallpaper(path: string) { rootShell.setWallpaper(path) }
        function clearWallpaper() { rootShell.clearWallpaper() }
        function wallpaperMode(m: string) { rootShell.setWallpaperMode(m) }
        function panelHeight(v: int) { rootShell.setPanelHeight(v) }
        function trayPosition(p: string) { rootShell.setTrayPosition(p) }
        function trayIconSize(v: int) { rootShell.setTrayIconSize(v) }
        function dockAlignment(a: string) { rootShell.setDockAlignment(a) }
        function dockMargin(v: int) { rootShell.setDockMargin(v) }
        function dockIconSize(v: int) { rootShell.setDockIconSize(v) }
        function dockMagnify(on: bool) { rootShell.setDockMagnify(on) }
        function trayAutoHide(on: bool) { rootShell.setTrayAutoHide(on) }
        function dockAutoHide(on: bool) { rootShell.setDockAutoHide(on) }
        function panelVisible(on: bool) { rootShell.setPanelVisible(on) }
        function themeMode(m: string) { rootShell.setThemeMode(m) }
        function resetAll() { rootShell.requestReset() }
        // Software updates. `checkUpdates` is safe to call at any time; it only
        // reads the release host. `installUpdate` downloads, verifies and
        // installs, then restarts the shell.
        function checkUpdates() { rootShell.checkForUpdates(false) }
        function installUpdate() { rootShell.installUpdate() }
        function autoUpdate(on: bool) { rootShell.setAutoUpdate(on) }
        function updateState() {
            return rootShell.updateAvailable ? "available:" + rootShell.availableVersion
                                             : (rootShell.installedVersion !== "" ? "current:" + rootShell.installedVersion
                                                                                  : "unknown")
        }
    }

    // ---- Persistent settings (Quickshell PersistentProperties) ----
    // Stored by Quickshell itself and restored on every launch, so no
    // hand-rolled JSON parsing is needed.
    PersistentProperties {
        id: store
        property bool darkMode: true
        property string accent: "#7C5CFC"
        property bool dockAutoHide: true
        property string pinned: "firefox,thunar,code-oss,kitty,google-chrome,discord,steam,mpv"
        property bool trayAutoHide: true
        property string themeMode: "dark"
        property real transparency: 0.92
        property bool animations: true
        property real uiScale: 1.0
        property real density: 1.0
        property bool panelVisible: true
        property real dockIconSize: 40
        property bool dockMagnify: true
        property bool showRecommended: true
        property bool notificationsEnabled: true
        property bool dnd: false
        property string wallpaper: ""
        property string wallpaperMode: "crop"
        property int panelHeight: 34
        property string trayPosition: "left"
        property int trayIconSize: 22
        property string dockAlignment: "center"
        property int dockMargin: 12

        onLoaded: rootShell.applyApplyStoreFallback()
        onReloaded: rootShell.applyApplyStoreFallback()
    }

    function applySettings() {
        // theme: prefer the three-state preference, fall back to the old boolean
        const mode = store.themeMode !== "" ? store.themeMode : (store.darkMode ? "dark" : "light")
        Theme.applyThemeMode(mode, new Date().getHours())
        Theme.acrylicOpacity = store.transparency
        Theme.animationsEnabled = store.animations
        Theme.uiScale = store.uiScale
        Theme.density = store.density
        panelVisible = store.panelVisible
        trayAutoHide = store.trayAutoHide
        dockIconSize = store.dockIconSize
        dockMagnify = store.dockMagnify
        showRecommended = store.showRecommended
        notificationsEnabled = store.notificationsEnabled
        dnd = store.dnd
        wallpaper = store.wallpaper
        wallpaperMode = store.wallpaperMode
        panelHeight = store.panelHeight
        trayPosition = store.trayPosition
        trayIconSize = store.trayIconSize
        dockAlignment = store.dockAlignment
        dockMargin = store.dockMargin
        Theme.darkMode = store.darkMode
        Theme.accent = store.accent
        dockAutoHideEnabled = store.dockAutoHide
        const list = (store.pinned || "").split(",").map(function (x) { return x.trim() })
                                            .filter(function (x) { return x !== "" })
        if (list.length > 0) pinnedIds = list
    }

    // Keep the store in sync with anything that changes the live values
    Connections {
        target: Theme
        function onDarkModeChanged() { store.darkMode = Theme.darkMode }
        function onAccentChanged() { store.accent = String(Theme.accent); rootShell.scheduleSave() }
        function onAcrylicOpacityChanged() { rootShell.scheduleSave() }
        function onAnimationsEnabledChanged() { rootShell.scheduleSave() }
        function onUiScaleChanged() { rootShell.scheduleSave() }
        function onDensityChanged() { rootShell.scheduleSave() }
        function onThemeModeChanged() { rootShell.scheduleSave() }
    }
    onDockAutoHideEnabledChanged: {
        store.dockAutoHide = dockAutoHideEnabled
        scheduleSave()
    }

    // Human-readable export alongside the persisted state (optional)
    function saveSettings() {
        store.pinned = pinnedIds.join(",")
        flushSettings()
    }

    // Used only if no JSON store exists yet: fall back to whatever
    // PersistentProperties happens to hold in memory.
    function applyApplyStoreFallback() {
        if (settingsReady) return
        applySettings()
    }

    function runCmd(argv) { Quickshell.execDetached(argv) }

    // ---- Interaction helpers ---------------------------------------------
    // Opening one surface always dismisses the others; any open menu or
    // tooltip is cleared first so it can never float above a new surface.
    function closeOverlays() {
        MenuController.close()
        Tooltip.hide()
        launcherOpen = false
        quickSettingsOpen = false
        calendarOpen = false
        notificationsOpen = false
        settingsOpen = false
    }

    function openLauncher() {
        closeOverlays()
        launcherOpen = true
    }
    function toggleLauncher() {
        if (launcherOpen) closeOverlays()
        else openLauncher()
    }
    function toggleCalendar() {
        const was = calendarOpen
        closeOverlays()
        calendarOpen = !was
    }
    function toggleNotifications() {
        const was = notificationsOpen
        closeOverlays()
        notificationsOpen = !was
    }
    function toggleQuickSettings(section) {
        const was = quickSettingsOpen
        closeOverlays()
        if (was && (section === undefined || section === qsSection)) return
        qsSection = section ? section : "home"
        quickSettingsOpen = true
    }
    function openSettingsAt(page) {
        closeOverlays()
        settingsPage = page
        settingsOpen = true
    }

    function showDesktop() {
        const tls = toplevelList
        for (let i = 0; i < tls.length; i++) {
            if (tls[i] && !tls[i].minimized) tls[i].minimized = true
        }
    }

    // ---- Session / screenshots ------------------------------------------
    // Log out by asking labwc to exit. That tears the session down cleanly and
    // returns to the TTY (or the display manager). Using loginctl
    // terminate-user killed the shell first and left the session hanging.
    function logoutSession() {
        Quickshell.execDetached(["sh", "-c",
            "labwc -e 2>/dev/null || loginctl terminate-session \"$XDG_SESSION_ID\""])
    }

    function takeScreenshot(mode) {
        // $HOME/.local/bin/canopy-screenshot prefers Flameshot, then grim+slurp
        Quickshell.execDetached(["sh", "-c",
            "exec $HOME/.local/bin/canopy-screenshot " + (mode ? mode : "area")])
    }

    // ---- Networking -------------------------------------------------------
    readonly property var wifiDevices: asList(Networking.devices).filter(function (d) {
        return d && d.scannerEnabled !== undefined
    })

    // Wi-Fi scanning is what makes networks actually appear. It is switched on
    // while a surface that lists networks is open, and off again afterwards.
    function setWifiScanning(on) {
        const devs = wifiDevices
        for (let i = 0; i < devs.length; i++) {
            try { devs[i].scannerEnabled = on } catch (e) { }
        }
    }

    function rescanNetworks() {
        setWifiScanning(false)
        Qt.callLater(function () { rootShell.setWifiScanning(true) })
    }

    function signalLevel(n) {
        if (!n || n.signalStrength === undefined) return 0
        const s = n.signalStrength
        return s <= 1 ? Math.round(s * 100) : Math.round(s)
    }

    // All visible networks, connected first, then strongest first.
    function wifiNetworks() {
        const out = []
        const devs = wifiDevices
        for (let i = 0; i < devs.length; i++) {
            const list = asList(devs[i].networks)
            for (let j = 0; j < list.length; j++) {
                const n = list[j]
                if (n && n.name) out.push(n)
            }
        }
        out.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            return rootShell.signalLevel(b) - rootShell.signalLevel(a)
        })
        return out
    }

    // ---- Audio ------------------------------------------------------------
    readonly property var audioSinks: asList(Pipewire.nodes).filter(function (n) {
        return n && n.isSink === true && n.audio
    })
    readonly property var audioSources: asList(Pipewire.nodes).filter(function (n) {
        return n && n.isSink === false && n.isStream === false && n.audio
    })

    function setDefaultSink(node) {
        if (!node) return
        try { Pipewire.preferredDefaultAudioSink = node } catch (e) { }
    }
    function sinkLabel(node) {
        if (!node) return "Unknown device"
        return node.description && node.description !== "" ? node.description
                                                          : (node.nickname || node.name || "Audio device")
    }

    function asList(v) {
        if (!v) return []
        if (v.values) return v.values
        return v
    }

    // ---- Context-menu builders -------------------------------------------
    // Every menu is produced from live state, so no entry is ever decorative.
    function sessionMenu() {
        const items = [
            { label: "Lock screen", icon: "system-lock-screen-symbolic",
              run: function () { rootShell.closeOverlays(); rootShell.locked = true } },
            { label: "Settings", icon: "preferences-system-symbolic",
              run: function () { rootShell.openSettingsAt(0) } }
        ]
        // Only offer the entry when there is something to install: a menu item
        // that opens a card saying "up to date" is noise.
        if (updateAvailable) {
            items.push({ sep: true })
            items.push({ label: "Install Canopy " + availableVersion, icon: "software-update-available-symbolic",
                         run: function () { rootShell.closeOverlays(); rootShell.installUpdate() } })
        } else if (updateError !== "") {
            items.push({ sep: true })
            items.push({ label: "Update check failed", icon: "dialog-warning-symbolic",
                         run: function () { rootShell.openSettingsAt(7) } })
        }
        return items.concat([
            { sep: true },
            { label: "Suspend", icon: "system-suspend-symbolic",
              run: function () { Quickshell.execDetached(["systemctl", "suspend"]) } },
            { label: "Take screenshot\u2026", icon: "applets-screenshooter",
              run: function () { rootShell.takeScreenshot("area") } },
            { label: "Log out", icon: "system-log-out-symbolic",
              run: function () { rootShell.logoutSession() } },
            { sep: true },
            { label: "Restart", icon: "system-reboot-symbolic", danger: true,
              run: function () { Quickshell.execDetached(["systemctl", "reboot"]) } },
            { label: "Shut down", icon: "system-shutdown-symbolic", danger: true,
              run: function () { Quickshell.execDetached(["systemctl", "poweroff"]) } }
        ])
    }

    function panelMenu() {
        return [
            { label: "Quick settings", icon: "preferences-other-symbolic",
              run: function () { rootShell.toggleQuickSettings("home") } },
            { label: "Notifications", icon: "notifications-symbolic",
              run: function () { rootShell.toggleNotifications() } },
            { label: "Open settings", icon: "preferences-system-symbolic",
              run: function () { rootShell.openSettingsAt(0) } },
            { sep: true },
            { label: "Show desktop", icon: "view-restore-symbolic",
              enabled: rootShell.windowCount > 0,
              run: function () { rootShell.showDesktop() } },
            { label: "Lock screen", icon: "system-lock-screen-symbolic",
              run: function () { rootShell.closeOverlays(); rootShell.locked = true } },
            { sep: true },
            { label: "Restart shell", icon: "view-refresh-symbolic",
              run: function () { rootShell.restartShell() } }
        ]
    }

    function desktopMenu() {
        return [
            { label: "Open launcher", icon: "view-app-grid-symbolic",
              run: function () { rootShell.openLauncher() } },
            { label: "Open settings", icon: "preferences-system-symbolic",
              run: function () { rootShell.openSettingsAt(0) } },
            { label: "Change wallpaper\u2026", icon: "preferences-desktop-wallpaper",
              run: function () { rootShell.openSettingsAt(0) } },
            { sep: true },
            { label: "Show desktop", icon: "view-restore-symbolic",
              enabled: rootShell.windowCount > 0,
              run: function () { rootShell.showDesktop() } },
            { label: "Take screenshot\u2026", icon: "applets-screenshooter",
              run: function () { rootShell.takeScreenshot("area") } },
            { label: "Notification centre", icon: "notifications-symbolic",
              run: function () { rootShell.toggleNotifications() } },
            { sep: true },
            { label: "Lock screen", icon: "system-lock-screen-symbolic",
              run: function () { rootShell.closeOverlays(); rootShell.locked = true } }
        ]
    }

    function entryBaseId(entry) {
        let s = (entry && entry.id) ? String(entry.id).toLowerCase() : ""
        const cut = s.indexOf(".desktop")
        if (cut > 0) s = s.substring(0, cut)
        return s
    }

    function toplevelsForEntry(entry) {
        const base = entryBaseId(entry)
        const out = []
        if (base === "") return out
        const tls = toplevelList
        for (let i = 0; i < tls.length; i++) {
            const t = tls[i]
            const aid = (t && t.appId) ? String(t.appId).toLowerCase() : ""
            if (aid === "") continue
            if (aid === base || aid.indexOf(base) >= 0 || base.indexOf(aid) >= 0) out.push(t)
        }
        return out
    }

    function newWindowAction(entry) {
        try {
            const acts = entry ? entry.actions : null
            if (!acts) return null
            for (let i = 0; i < acts.length; i++) {
                const a = acts[i]
                const n = (a && a.name) ? String(a.name).toLowerCase() : ""
                if (n.indexOf("new window") >= 0 || n.indexOf("new private") >= 0) return a
            }
        } catch (e) { }
        return null
    }

    function dockMenuForEntry(entry) {
        if (!entry) return []
        const tls = rootShell.toplevelsForEntry(entry)
        const pinned = rootShell.isPinned(entry.id)
        const items = []
        items.push({ label: "Open", icon: entry.icon ? entry.icon : "application-x-executable",
                     run: function () { entry.execute() } })

        // The application's own actions, taken verbatim from its .desktop
        // Actions= entries (e.g. Firefox: "New Window", "New Private Window").
        // Canopy does not invent or rename these.
        let acts = []
        try {
            acts = entry.actions ? Array.prototype.slice.call(entry.actions) : []
        } catch (e) {
            acts = []
        }
        const actionItems = []
        for (let i = 0; i < acts.length; i++) {
            const a = acts[i]
            if (!a || !a.name) continue
            actionItems.push({ label: a.name, run: function () { a.execute() } })
        }
        if (actionItems.length > 0) {
            for (let i = 0; i < actionItems.length; i++) items.push(actionItems[i])
        }

        if (tls.length > 0) {
            items.push({ sep: true })
            items.push({ label: tls.length > 1 ? "Show windows" : "Show window", icon: "view-restore-symbolic",
                         run: function () { for (let i = 0; i < tls.length; i++) tls[i].activate() } })
            items.push({ label: "Minimize", icon: "window-minimize-symbolic",
                         run: function () { for (let i = 0; i < tls.length; i++) tls[i].minimized = true } })
            items.push({ label: tls.length > 1 ? "Close windows" : "Close window", icon: "window-close-symbolic",
                         danger: true,
                         run: function () { for (let i = 0; i < tls.length; i++) tls[i].close() } })
        }
        items.push({ sep: true })
        items.push({ label: pinned ? "Unpin from dock" : "Pin to dock", icon: "emblem-favorite-symbolic",
                     run: function () { rootShell.togglePinned(entry.id) } })
        return items
    }

    function dockMenuForToplevel(t, entry) {
        if (!t) return []
        const items = []
        items.push({ label: "Show window", icon: "view-restore-symbolic",
                     run: function () { t.activate() } })
        items.push({ label: t.minimized ? "Restore" : "Minimize", icon: "window-minimize-symbolic",
                     run: function () { if (t.minimized) t.activate(); else t.minimized = true } })
        items.push({ sep: true })
        items.push({ label: "Close window", icon: "window-close-symbolic", danger: true,
                     run: function () { t.close() } })
        if (entry) {
            items.push({ label: rootShell.isPinned(entry.id) ? "Unpin from dock" : "Pin to dock",
                         icon: "emblem-favorite-symbolic",
                         run: function () { rootShell.togglePinned(entry.id) } })
        }
        return items
    }

    function networkMenu() {
        const items = []
        items.push({ label: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on",
                     icon: Networking.wifiEnabled ? "network-wireless-symbolic" : "network-wireless-offline-symbolic",
                     run: function () { Networking.wifiEnabled = !Networking.wifiEnabled } })

        // Make sure the list is fresh before showing it.
        rootShell.setWifiScanning(true)
        const nets = rootShell.wifiNetworks()

        if (nets.length > 0) items.push({ sep: true })
        for (let k = 0; k < nets.length && k < 10; k++) {
            const n = nets[k]
            const lvl = rootShell.signalLevel(n)
            items.push({
                label: n.name + (n.connected ? "  (connected)" : (lvl > 0 ? "  " + lvl + "%" : "")),
                checked: n.connected === true,
                run: function () {
                    if (n.connected) n.disconnect()
                    else n.connect()
                }
            })
        }
        items.push({ sep: true })
        items.push({ label: "Scan for networks", icon: "view-refresh-symbolic",
                     run: function () { rootShell.rescanNetworks() } })
        items.push({ label: "Network settings", icon: "preferences-system-symbolic",
                     run: function () { rootShell.openSettingsAt(4) } })
        return items
    }

    function audioMenu() {
        const sink = Pipewire.defaultAudioSink
        const ok = !!(sink && sink.audio)
        return [
            { label: (ok && sink.audio.muted) ? "Unmute" : "Mute",
              icon: (ok && sink.audio.muted) ? "audio-volume-muted" : "audio-volume-high-symbolic",
              enabled: ok,
              run: function () { if (ok) sink.audio.muted = !sink.audio.muted } },
            { label: "Volume up", enabled: ok,
              run: function () { if (ok) sink.audio.volume = Math.min(1, sink.audio.volume + 0.05) } },
            { label: "Volume down", enabled: ok,
              run: function () { if (ok) sink.audio.volume = Math.max(0, sink.audio.volume - 0.05) } },
            { sep: true },
            { label: "Quick settings", icon: "preferences-other-symbolic",
              run: function () { rootShell.toggleQuickSettings("audio") } },
            { label: "Sound settings", icon: "preferences-system-symbolic",
              run: function () { rootShell.openSettingsAt(5) } }
        ]
    }

    function bluetoothMenu() {
        const ad = Bluetooth.defaultAdapter
        const items = []
        if (ad) {
            items.push({ label: ad.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on",
                         icon: "network-bluetooth-symbolic",
                         run: function () { ad.enabled = !ad.enabled } })
            items.push({ sep: true })
            const devs = rootShell.asList(ad.devices)
            for (let i = 0; i < devs.length && i < 6; i++) {
                const d = devs[i]
                if (!d || !d.name) continue
                items.push({ label: (d.connected ? "\u2713 " : "") + d.name,
                             run: function () { d.connected = !d.connected } })
            }
            if (devs.length > 0) items.push({ sep: true })
        } else {
            items.push({ label: "No Bluetooth adapter", enabled: false })
            items.push({ sep: true })
        }
        items.push({ label: "Quick settings", icon: "preferences-other-symbolic",
                     run: function () { rootShell.toggleQuickSettings("bluetooth") } })
        return items
    }

    function batteryMenu() {
        const dev = UPower.displayDevice
        const pct = (dev && dev.percentage > 0) ? Math.round(dev.percentage) + "%" : "No battery"
        return [
            { label: "Battery: " + pct, enabled: false },
            { sep: true },
            { label: "Power settings", icon: "preferences-system-symbolic",
              run: function () { rootShell.openSettingsAt(6) } },
            { label: "Suspend", icon: "system-suspend-symbolic",
              run: function () { Quickshell.execDetached(["systemctl", "suspend"]) } }
        ]
    }

    function notificationsMenu() {
        return [
            { label: "Notification centre", icon: "notifications-symbolic",
              run: function () { rootShell.toggleNotifications() } },
            { label: "Clear all", enabled: notificationModel.count > 0,
              run: function () { notificationModel.clear() } },
            { sep: true },
            { label: "Notification settings", icon: "preferences-system-symbolic",
              run: function () { rootShell.openSettingsAt(3) } }
        ]
    }

    function settingsTrayMenu() {
        return [
            { label: "Open settings", icon: "preferences-system-symbolic",
              run: function () { rootShell.openSettingsAt(0) } },
            { label: "Appearance", icon: "preferences-desktop-theme",
              run: function () { rootShell.openSettingsAt(0) } },
            { label: "Desktop", icon: "preferences-desktop",
              run: function () { rootShell.openSettingsAt(1) } },
            { sep: true },
            { label: "Restart shell", icon: "view-refresh-symbolic",
              run: function () { rootShell.restartShell() } }
        ]
    }


    function attemptUnlock() {
        lockMessage = ""
        if (pam.active) { pam.abort(); return }
        pam.start()
    }

    function openQuickSettings(section) {
        qsSection = section
        quickSettingsOpen = true
    }
    property bool quickSettingsOpen: false

    property var pinnedIds: []

    // Pin what is actually installed. The old list (firefox, thunar, code-oss,
    // kitty, chrome, discord, steam, mpv) is Arch-specific and left the dock
    // empty - or full of dead entries - on any machine without those exact
    // apps. Discovery asks the desktop database instead, one app per role,
    // terminal first because that is the one thing a desktop must offer.
    function defaultPinnedIds() {
        const apps = DesktopEntries.applications.values ? DesktopEntries.applications.values : []
        const out = []
        const seen = {}
        function take(re) {
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i]
                if (!a || a.noDisplay || seen[a.id]) continue
                const hay = ((a.id || "") + " " + (a.name || "") + " " + (a.genericName || "")).toLowerCase()
                if (re.test(hay)) { seen[a.id] = true; out.push(a.id); return true }
            }
            return false
        }
        take(/terminal|alacritty|kitty|foot|console|konsole|xterm|wezterm|tilix/)
        take(/zen/)
        take(/firefox|chromium|chrome|browser/)
        take(/nautilus|thunar|dolphin|nemo|pcmanfm|file manager|files/)
        take(/text editor|kate|gedit|zed|code|writer/)
        take(/settings|control center/)
        return out
    }

    // A first run, or a reset, ends up here.
    function applyDefaultPins() {
        if (pinnedIds.length === 0) {
            pinnedIds = defaultPinnedIds()
            store.pinned = pinnedIds.join(",")
        }
    }

    function isPinnedAppId(appId) {
        if (!appId) return false
        const low = appId.toLowerCase()
        return pinnedIds.some(function(p){ return low.indexOf(p) >= 0 })
    }

    // Search matches the visible name first, then generic name / comment /
    // desktop id, so typing "browser" finds Firefox and "edit" finds editors.
    function filteredApps(query) {
        const all = DesktopEntries.applications.values ? DesktopEntries.applications.values : []
        const q = (query || "").toLowerCase().trim()
        if (q === "") {
            const plain = []
            for (let i = 0; i < all.length && plain.length < 120; i++) {
                if (all[i] && !all[i].noDisplay) plain.push(all[i])
            }
            return plain
        }
        const head = []
        const rest = []
        for (let i = 0; i < all.length; i++) {
            const a = all[i]
            if (!a || a.noDisplay) continue
            const name = (a.name || "").toLowerCase()
            if (name.indexOf(q) === 0) { head.push(a); continue }
            const hay = (name + " " + (a.genericName || "") + " " + (a.comment || "") + " " + (a.id || "")).toLowerCase()
            if (hay.indexOf(q) >= 0) rest.push(a)
        }
        return head.concat(rest).slice(0, 120)
    }

    function pinnedEntries() {
        const out = []
        const apps = DesktopEntries.applications.values ? DesktopEntries.applications.values : []
        for (let i = 0; i < pinnedIds.length; i++) {
            const key = pinnedIds[i].toLowerCase()
            let e = DesktopEntries.byId(pinnedIds[i])
            if (!e) {
                for (let j = 0; j < apps.length; j++) {
                    const a = apps[j]
                    if (a && a.id && a.id.toLowerCase().indexOf(key) >= 0) { e = a; break }
                }
            }
            if (e) out.push(e)
        }
        return out
    }

    readonly property int windowCount: (ToplevelManager.toplevels && ToplevelManager.toplevels.values)
                                        ? ToplevelManager.toplevels.values.length : 0
    // Intelligent auto-hide: an empty desktop keeps the dock visible so there is
    // always something to launch from; once windows exist the dock gets out of
    // the way and reappears on hover.
    // Reveal state for the auto-hiding surfaces. Hiding is delayed so the
    // pointer can travel from the screen edge onto the surface without it
    // snapping away mid-click.
    property bool trayRevealed: false
    property bool dockRevealed: false

    Timer {
        id: trayHideTimer
        interval: 260
        onTriggered: if (!rootShell.trayHovered) rootShell.trayRevealed = false
    }
    Timer {
        id: dockHideTimer
        interval: 260
        onTriggered: if (!rootShell.dockHovered) rootShell.dockRevealed = false
    }
    property bool trayHovered: false
    property bool dockHovered: false

    function revealTray() {
        rootShell.trayRevealed = true
        trayHideTimer.stop()
    }
    function scheduleHideTray() {
        trayHideTimer.restart()
    }
    function revealDock() {
        rootShell.dockRevealed = true
        dockHideTimer.stop()
    }
    function scheduleHideDock() {
        dockHideTimer.restart()
    }

    readonly property var toplevelList: (ToplevelManager.toplevels && ToplevelManager.toplevels.values)
                                         ? ToplevelManager.toplevels.values : []
    readonly property int minimizedCount: {
        let c = 0
        for (let i = 0; i < toplevelList.length; i++) {
            const t = toplevelList[i]
            if (t && t.minimized && !isPinnedAppId(t.appId)) c++
        }
        return c
    }
    readonly property int activeUnpinnedCount: {
        let c = 0
        for (let i = 0; i < toplevelList.length; i++) {
            const t = toplevelList[i]
            if (t && !t.minimized && !isPinnedAppId(t.appId)) c++
        }
        return c
    }

    readonly property bool hasMinimized: {
        const v = (ToplevelManager.toplevels && ToplevelManager.toplevels.values)
                  ? ToplevelManager.toplevels.values : []
        for (let i = 0; i < v.length; i++) if (v[i] && v[i].minimized) return true
        return false
    }
    readonly property bool dockAutoHidden: dockAutoHideEnabled && windowCount > 0

    function isRunning(pinnedId) {
        if (!ToplevelManager || !ToplevelManager.toplevels) return false
        const values = ToplevelManager.toplevels.values ? ToplevelManager.toplevels.values : []
        for (let i = 0; i < values.length; i++) {
            const t = values[i]
            if (t && t.appId && t.appId.toLowerCase().indexOf(pinnedId) >= 0) return true
        }
        return false
    }

    // Notifications
    NotificationServer {
        id: notificationServer
        keepOnReload: true
        onNotification: (n) => {
            notificationModel.append({"title": n.summary, "body": n.body})
        }
    }
    ListModel { id: notificationModel }

    // ---- Desktop background (layer-shell "background") ----
    PanelWindow {
        id: background
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "canopy-background"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The desktop is clickable (right-click menu, click-to-dismiss), so the
        // background surface needs an input region. Windows still stack above
        // it because they live on higher layers.
        mask: Region { item: bgInput }

        // gradient fallback (also shown while the wallpaper loads)
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.darkMode ? "#1C1B24" : "#EEF0F6" }
                GradientStop { position: 0.55; color: Theme.darkMode ? "#141320" : "#E4E7F0" }
                GradientStop { position: 1.0; color: Theme.darkMode ? "#0B0A10" : "#DDE0EA" }
            }
        }

        Image {
            id: wallpaperImage
            anchors.fill: parent
            asynchronous: true
            cache: true
            fillMode: rootShell.wallpaperFillMode()
            source: rootShell.wallpaper !== "" ? "file://" + rootShell.wallpaper : ""
            visible: status === Image.Ready
        }

        // subtle scrim so panel/tray/dock text stays readable on bright images
        Rectangle {
            anchors.fill: parent
            visible: wallpaperImage.visible
            color: "black"
            opacity: Theme.darkMode ? 0.25 : 0.10
        }

        // very soft vignette: lifts the shell surfaces off the wallpaper
        Rectangle {
            anchors.fill: parent
            visible: wallpaperImage.visible
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.darkMode ? "#33000000" : "#14000000" }
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1.0; color: Theme.darkMode ? "#4D000000" : "#1A000000" }
            }
        }

        // Invisible click target covering the whole desktop.
        Rectangle {
            id: bgInput
            anchors.fill: parent
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) {
                        // Opens exactly at the pointer (screen coords, because
                        // this surface is anchored at the screen origin).
                        MenuController.showAt(rootShell.desktopMenu(), m.x, m.y, "below")
                    } else {
                        rootShell.closeOverlays()
                    }
                }
            }
        }
    }


    // ---- Lock screen ----
    // NOTE: Quickshell 0.3.2 has no ext-session-lock-v1 binding, so this is a
    // layer-shell overlay (Overlay layer, exclusive keyboard focus, idle
    // inhibited) rather than a true session lock. See docs/COMPONENT_REUSE.md.
    PanelWindow {
        id: lockWin
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: rootShell.locked
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "canopy-lock"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        PamContext {
            id: pam
            config: "login"
            user: Quickshell.env("USER")
            onResponseRequiredChanged: {
                if (responseRequired) pam.respond(passField.text)
            }
            onCompleted: (result, response) => {
                if (result === PamResult.Success) {
                    rootShell.locked = false
                    rootShell.lockMessage = ""
                    passField.text = ""
                } else {
                    rootShell.lockMessage = "Incorrect password"
                    passField.text = ""
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.darkMode ? "#0B0A10" : "#EEF0F6"

            // soft accent wash
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.darkMode ? "#331C1B24" : "#22FFFFFF" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 18

                Rectangle {
                    width: 88; height: 88; radius: 44
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: (Quickshell.env("USER") || "u").charAt(0).toUpperCase()
                        color: "white"
                        font.pixelSize: 38
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Quickshell.env("USER") || ""
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeXl
                    font.weight: Font.DemiBold
                    font.family: Theme.fontFamily
                }

                SystemClock { id: lockClock; precision: SystemClock.Minutes }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(lockClock.date, "HH:mm")
                    color: Theme.textPrimary
                    font.pixelSize: 44
                    font.weight: Font.Medium
                    font.letterSpacing: Theme.trackingDisplay
                    font.family: Theme.fontDisplay
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(lockClock.date, "dddd d MMMM")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMd
                    font.family: Theme.fontFamily
                }

                Rectangle {
                    width: 280; height: 42; radius: 21
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.darkMode ? "#26FFFFFF" : "#11000000"
                    border.color: passField.activeFocus ? Theme.accent : (Theme.darkMode ? "#33FFFFFF" : "#1F000000")
                    border.width: 1

                    TextInput {
                        id: passField
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeMd
                        font.family: Theme.fontFamily
                        selectionColor: Theme.accent
                        focus: rootShell.locked
                        onAccepted: rootShell.attemptUnlock()
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeMd
                        font.family: Theme.fontFamily
                        visible: passField.text === ""
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: rootShell.lockMessage
                    color: Theme.danger
                    font.pixelSize: Theme.fontSizeSm
                    font.family: Theme.fontFamily
                    opacity: rootShell.lockMessage === "" ? 0 : 1
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    Rectangle {
                        width: 130; height: 38; radius: 19
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: pam.active ? "Checking..." : "Unlock"
                            color: "white"
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Font.DemiBold
                            font.family: Theme.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootShell.attemptUnlock()
                        }
                    }

                    Rectangle {
                        width: 90; height: 38; radius: 19
                        color: Theme.darkMode ? "#1FFFFFFF" : "#0D000000"
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { rootShell.locked = false; rootShell.lockMessage = "" }
                        }
                    }
                }
            }
        }
    }

    // ---- Top System Panel ----
    PanelWindow {
        id: topPanel
        anchors { top: true; left: true; right: true }
        implicitHeight: rootShell.panelHeight
        visible: rootShell.panelVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Auto

        readonly property int itemHeight: Math.max(24, rootShell.panelHeight - 8)

        // --- material: base fill, top highlight, bottom hairline ---
        Rectangle {
            anchors.fill: parent
            color: Theme.panelBg
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.darkMode ? "#14FFFFFF" : "#40FFFFFF" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.panelBorder
        }

        // Panel surface: right-click opens the panel menu, left-click closes
        // whatever is open. Sits behind the items so they keep their own input.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => {
                if (m.button === Qt.RightButton)
                    MenuController.show(rootShell.panelMenu(), panelMenuAnchor, "below")
                else
                    rootShell.closeOverlays()
            }
        }
        Item { id: panelMenuAnchor; anchors.centerIn: parent; width: 1; height: 1; opacity: 0 }

        // ---- Left: launcher + active application ----
        Row {
            id: panelLeft
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            IconButton {
                imageSource: Qt.resolvedUrl("assets/canopy-mark.svg")
                iconSize: 19
                buttonSize: topPanel.itemHeight
                label: "Applications"
                tipDetail: "Open the Canopy launcher  (Super)"
                active: rootShell.launcherOpen
                onClicked: rootShell.toggleLauncher()
            }

            Item {
                width: 1
                height: topPanel.itemHeight
                Rectangle {
                    anchors.centerIn: parent
                    width: 1; height: 15
                    color: Theme.hairline
                }
            }

            // macOS menu-bar convention: the front application's name, bold.
            Item {
                id: appNameArea
                width: Math.min(appNameText.implicitWidth, 190)
                height: topPanel.itemHeight

                Text {
                    id: appNameText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 190)
                    text: {
                        if (!ToplevelManager.activeToplevel) return "Canopy"
                        const a = ToplevelManager.activeToplevel.appId || ""
                        const e = DesktopEntries.heuristicLookup(a)
                        return (e && e.name) ? e.name : (ToplevelManager.activeToplevel.title || "Canopy")
                    }
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    font.family: Theme.fontDisplay
                    elide: Text.ElideRight
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            const t = rootShell.activeWindowTitle()
                            Tooltip.show(appNameArea, appNameText.text, t !== "" ? t : "", "bottom")
                        } else {
                            Tooltip.hide()
                        }
                    }
                }
            }
        }

        // ---- Centre: clock + date ----
        // A MouseArea may NOT live inside a Row - positioners ignore child
        // anchors, which collapsed the clock to zero width and made the time
        // vanish as soon as a window opened. Wrap it in an Item instead.
        Item {
            id: clockArea
            anchors.centerIn: parent
            width: clockPill.width
            height: clockPill.height

            Rectangle {
                id: clockPill
                width: clockRow.width + 20
                height: topPanel.itemHeight
                radius: Theme.radiusSmall
                color: (clockHover.hovered || rootShell.calendarOpen) ? Theme.hoverBg : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    id: clockRow
                    anchors.centerIn: parent
                    spacing: 8

                    SystemClock {
                        id: clock
                        precision: SystemClock.Seconds
                    }

                    Text {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        font.letterSpacing: Theme.trackingWide
                        font.family: Theme.fontDisplay
                    }
                    // Same "time · date" rhythm as the Canopy site's panel.
                    Text {
                        text: "\u00B7"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeMd
                        font.family: Theme.fontDisplay
                    }
                    Text {
                        text: Qt.formatDateTime(clock.date, "ddd d MMM")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.Medium
                        font.letterSpacing: Theme.tracking
                        font.family: Theme.fontDisplay
                    }
                }
            }

            HoverHandler {
                id: clockHover
                onHoveredChanged: {
                    if (hovered) Tooltip.show(clockArea, "Calendar", "Click for the month view", "bottom")
                    else Tooltip.hide()
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: rootShell.toggleCalendar()
            }
        }

        // ---- Right: workspaces, system status, power ----
        Row {
            id: panelRight
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            // Workspace hints. Labwc exposes no workspace query, so these are
            // rendered as unselected markers rather than claiming a state the
            // shell cannot know. Switching stays on the compositor binds.
            Item {
                id: wsArea
                width: wsRow.width + 14
                height: topPanel.itemHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 3
                    anchors.bottomMargin: 3
                    radius: 8
                    color: wsHover.hovered ? Theme.hoverBg : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 5

                    Repeater {
                        model: 4
                        delegate: Item {
                            id: wsDot
                            width: 6
                            height: 14

                            Rectangle {
                                anchors.centerIn: parent
                                width: 6
                                height: 6
                                radius: 3
                                color: wsDotHover.hovered ? Theme.textPrimary : Theme.textMuted
                                opacity: wsDotHover.hovered ? 0.9 : 0.45
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }

                            HoverHandler {
                                id: wsDotHover
                                onHoveredChanged: {
                                    if (hovered)
                                        Tooltip.show(wsDot, "Workspace " + (index + 1), "Switch with Super " + (index + 1), "bottom")
                                    else
                                        Tooltip.hide()
                                }
                            }
                        }
                    }
                }

                HoverHandler { id: wsHover }
            }

            Item {
                width: 1
                height: topPanel.itemHeight
                Rectangle {
                    anchors.centerIn: parent
                    width: 1; height: 15
                    color: Theme.hairline
                }
            }

            IconButton {
                id: wifiBtn
                iconName: Networking.wifiEnabled ? "network-wireless-symbolic" : "network-wireless-offline-symbolic"
                iconSize: 17
                buttonSize: topPanel.itemHeight
                label: "Wi-Fi"
                tipLabel: Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                tipDetail: "Left-click for quick settings, right-click for networks"
                onClicked: rootShell.toggleQuickSettings("network")
                onRightClicked: MenuController.show(rootShell.networkMenu(), wifiBtn, "bottom")
            }

            IconButton {
                id: volBtn
                iconName: rootShell.volumeIconName()
                iconSize: 17
                buttonSize: topPanel.itemHeight
                label: "Sound"
                tipLabel: rootShell.audioAvailable
                         ? (rootShell.audioMuted ? "Muted" : "Volume " + Math.round(rootShell.volumeLevel * 100) + "%")
                         : "No audio device"
                tipDetail: "Left-click for quick settings, right-click for volume"
                onClicked: rootShell.toggleQuickSettings("audio")
                onRightClicked: MenuController.show(rootShell.audioMenu(), volBtn, "bottom")
            }

            IconButton {
                id: batBtn
                visible: rootShell.hasBattery
                iconName: rootShell.batteryIconName()
                iconSize: 17
                buttonSize: topPanel.itemHeight
                label: "Battery"
                tipLabel: "Battery " + Math.round(rootShell.batteryPercent) + "%"
                tipDetail: "Left-click for quick settings, right-click for power options"
                onClicked: rootShell.toggleQuickSettings("battery")
                onRightClicked: MenuController.show(rootShell.batteryMenu(), batBtn, "bottom")
            }

            Item {
                width: 1
                height: topPanel.itemHeight
                Rectangle {
                    anchors.centerIn: parent
                    width: 1; height: 15
                    color: Theme.hairline
                }
            }

            IconButton {
                id: sessBtn
                iconName: "system-shutdown-symbolic"
                iconSize: 17
                buttonSize: topPanel.itemHeight
                label: "Power"
                tipDetail: "Lock, log out, restart or shut down"
                active: MenuController.open
                onClicked: MenuController.show(rootShell.sessionMenu(), sessBtn, "bottom")
                onRightClicked: MenuController.show(rootShell.sessionMenu(), sessBtn, "bottom")
            }
        }
    }

    // ---- Auto-hide edge sensors ----
    // Tiny, always-present layer surfaces. Their mask never changes, so hover
    // is stable; they only ever *reveal* the tray/dock, never swallow clicks
    // outside their 6px strip.
    PanelWindow {
        id: trayEdge
        anchors { left: true; top: true; bottom: true }
        implicitWidth: 6
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: trayEdgeFill }

        Rectangle {
            id: trayEdgeFill
            anchors.fill: parent
            color: "transparent"
            HoverHandler {
                onHoveredChanged: {
                    rootShell.trayHovered = hovered
                    if (hovered) rootShell.revealTray()
                    else rootShell.scheduleHideTray()
                }
            }
        }
    }

    PanelWindow {
        id: dockEdgeWin
        anchors { left: true; right: true; bottom: true }
        implicitHeight: 6
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: dockEdgeFill }

        Rectangle {
            id: dockEdgeFill
            anchors.fill: parent
            color: "transparent"
            HoverHandler {
                onHoveredChanged: {
                    rootShell.dockHovered = hovered
                    if (hovered) rootShell.revealDock()
                    else rootShell.scheduleHideDock()
                }
            }
        }
    }

    // ---- Left System Tray (floating pill) ----
    PanelWindow {
        id: leftTray
        anchors { top: true; bottom: true }
        anchors.left: rootShell.trayPosition === "left"
        anchors.right: rootShell.trayPosition === "right"
        implicitWidth: 76
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        // Input covers only the pill; the pill itself is off-screen while
        // hidden, so the window never steals clicks. A separate 6px edge
        // window (trayEdge) drives the reveal - its mask never changes, which
        // is what used to make hover flicker and eat clicks.
        mask: Region { item: trayPill }

        Rectangle {
            id: trayPill
            property bool opened: rootShell.quickSettingsOpen
            width: 56
            // hug the content, but never grow past the screen
            height: Math.min(trayCol.implicitHeight + 20, parent.height - 60)
            anchors.verticalCenter: parent.verticalCenter
            x: (rootShell.trayRevealed || opened || !rootShell.trayAutoHide)
               ? (leftTray.width - width) / 2 : -(width + 8)
            Behavior on x {
                NumberAnimation { duration: Theme.animMedium; easing.type: Easing.OutCubic }
            }
            HoverHandler {
                onHoveredChanged: {
                    rootShell.trayHovered = hovered
                    if (hovered) rootShell.revealTray()
                    else rootShell.scheduleHideTray()
                }
            }

            radius: 26
            color: Theme.darkMode ? "#E6141419" : "#F2FFFFFF"
            border.color: Theme.darkMode ? "#2EFFFFFF" : "#1F000000"
            border.width: 1

            // inner highlight ring: reads as a raised glass surface without blur
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.color: Theme.darkMode ? "#14FFFFFF" : "#80FFFFFF"
                border.width: 1
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: 5
                contentHeight: trayCol.implicitHeight
                contentWidth: width
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: trayCol
                    width: 40
                    x: (parent.width - width) / 2
                    spacing: 2

                    IconButton {
                        iconName: "view-app-grid-symbolic"
                        buttonSize: 40
                        buttonRadius: 12
                        iconSize: rootShell.trayIconSize
                        label: "Applications"
                        tipDetail: "Open the Canopy launcher  (Super)"
                        tipPlacement: "right"
                        active: rootShell.launcherOpen
                        onClicked: rootShell.toggleLauncher()
                    }

                    IconButton {
                        iconName: "preferences-other-symbolic"
                        buttonSize: 40
                        buttonRadius: 12
                        iconSize: rootShell.trayIconSize
                        label: "Quick settings"
                        tipDetail: "Wi-Fi, Bluetooth, sound and power"
                        tipPlacement: "right"
                        active: rootShell.quickSettingsOpen
                        onClicked: rootShell.toggleQuickSettings("home")
                    }

                    IconButton {
                        id: trayWifi
                        iconName: Networking.wifiEnabled ? "network-wireless-symbolic" : "network-wireless-offline-symbolic"
                        buttonSize: 40
                        buttonRadius: 12
                        iconSize: rootShell.trayIconSize
                        label: Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                        tipDetail: "Right-click for available networks"
                        tipPlacement: "right"
                        onClicked: rootShell.toggleQuickSettings("network")
                        onRightClicked: MenuController.show(rootShell.networkMenu(), trayWifi, "right")
                    }

                    // Divider: launcher / quick access above, system controls below
                    Item {
                        width: 40
                        height: 9
                        Rectangle {
                            anchors.centerIn: parent
                            width: 22; height: 1
                            color: Theme.hairline
                        }
                    }

                    IconButton {
                        id: trayAudio
                        iconName: rootShell.volumeIconName()
                        buttonSize: 40
                        buttonRadius: 12
                        iconSize: rootShell.trayIconSize
                        label: "Sound"
                        tipLabel: rootShell.audioAvailable
                                  ? (rootShell.audioMuted ? "Muted" : "Volume " + Math.round(rootShell.volumeLevel * 100) + "%")
                                  : "No audio device"
                        tipDetail: "Right-click for volume controls"
                        tipPlacement: "right"
                        onClicked: rootShell.toggleQuickSettings("audio")
                        onRightClicked: MenuController.show(rootShell.audioMenu(), trayAudio, "right")
                    }

                    IconButton {
                        id: trayBluetooth
                        iconName: "network-bluetooth-symbolic"
                        buttonSize: 40
                        buttonRadius: 12
                        iconSize: rootShell.trayIconSize
                        label: "Bluetooth"
                        tipLabel: !rootShell.btAvailable ? "No Bluetooth adapter"
                                 : (rootShell.btEnabled ? "Bluetooth on" : "Bluetooth off")
                        tipDetail: "Right-click to toggle or connect"
                        tipPlacement: "right"
                        active: rootShell.btEnabled
                        onClicked: rootShell.toggleQuickSettings("bluetooth")
                        onRightClicked: MenuController.show(rootShell.bluetoothMenu(), trayBluetooth, "right")
                    }

                // Background / tray-only applications (StatusNotifier items)
                Repeater {
                    model: rootShell.trayItems
                    delegate: Rectangle {
                        id: sniItem
                        width: 40; height: 40; radius: 12
                        color: (sniHover.hovered || sniHit.containsMouse) ? Theme.hoverBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        // Applications ship full-colour tray icons, some of which
                        // are white-on-transparent and disappear on a light tray.
                        // A faint backplate keeps them visible without tinting
                        // artwork Canopy does not own.
                        Rectangle {
                            visible: !Theme.darkMode
                            anchors.centerIn: parent
                            width: 30; height: 30; radius: 8
                            color: "#14000000"
                        }

                        CanopyIcon {
                            size: rootShell.trayIconSize
                            anchors.centerIn: parent
                            // StatusNotifier icons are often absolute paths or
                            // names missing from the index - CanopyIcon falls
                            // back to <name>-symbolic, then a letter glyph.
                            iconName: {
                                if (modelData.icon && modelData.icon !== "") return modelData.icon
                                if (modelData.id && modelData.id !== "") return modelData.id
                                return "application-x-executable"
                            }
                        }

                        HoverHandler {
                            id: sniHover
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(sniItem,
                                                 (modelData.title && modelData.title !== "") ? modelData.title
                                                                                            : (modelData.id || "Application"),
                                                 modelData.hasMenu ? "Right-click for options" : "",
                                                 "right")
                                else
                                    Tooltip.hide()
                            }
                        }

                        // Real DBusMenu popup anchored to the icon
                        QsMenuAnchor {
                            id: sniMenu
                            menu: modelData.menu
                            anchor {
                                item: sniHit
                                edges: Edges.Right | Edges.Bottom
                                gravity: Edges.Bottom
                            }
                        }

                        MouseArea {
                            id: sniHit
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (m) => {
                                Tooltip.hide()
                                if (m.button === Qt.LeftButton) modelData.activate()
                                else if (modelData.hasMenu) sniMenu.open()
                                else modelData.secondaryActivate()
                            }
                        }
                    }
                }

                // Battery
                IconButton {
                    id: trayBattery
                    visible: rootShell.hasBattery
                    iconName: rootShell.batteryIconName()
                    buttonSize: 40
                    buttonRadius: 12
                    iconSize: rootShell.trayIconSize
                    label: "Battery"
                    tipLabel: "Battery " + Math.round(rootShell.batteryPercent) + "%"
                    tipDetail: "Right-click for power options"
                    tipPlacement: "right"
                    onClicked: rootShell.toggleQuickSettings("battery")
                    onRightClicked: MenuController.show(rootShell.batteryMenu(), trayBattery, "right")
                }

                // Divider: system status above, shell surfaces below
                Item {
                    width: 40
                    height: 9
                    Rectangle {
                        anchors.centerIn: parent
                        width: 22; height: 1
                        color: Theme.hairline
                    }
                }

                IconButton {
                    id: trayNotifications
                    iconName: "notifications-symbolic"
                    buttonSize: 40
                    buttonRadius: 12
                    iconSize: rootShell.trayIconSize
                    label: "Notifications"
                    tipLabel: rootShell.notificationCount > 0
                              ? "Notifications (" + rootShell.notificationCount + ")"
                              : "Notifications"
                    tipDetail: "Right-click for options"
                    tipPlacement: "right"
                    active: rootShell.notificationsOpen
                    onClicked: rootShell.toggleNotifications()
                    onRightClicked: MenuController.show(rootShell.notificationsMenu(), trayNotifications, "right")

                    // unread badge
                    Rectangle {
                        visible: rootShell.notificationCount > 0
                        width: 15; height: 15; radius: 7.5
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: rootShell.notificationCount > 9 ? "9+" : String(rootShell.notificationCount)
                            color: "white"
                            font.pixelSize: 8
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                    }
                }

                IconButton {
                    id: traySettings
                    iconName: "preferences-system-symbolic"
                    buttonSize: 40
                    buttonRadius: 12
                    iconSize: rootShell.trayIconSize
                    label: "Settings"
                    tipDetail: "Appearance, desktop, sound and more"
                    tipPlacement: "right"
                    active: rootShell.settingsOpen
                    onClicked: rootShell.openSettingsAt(rootShell.settingsPage)
                    onRightClicked: MenuController.show(rootShell.settingsTrayMenu(), traySettings, "right")
                }
                }
            }
        }
    }

    // ---- Application Dock ----
    PanelWindow {
        id: dockWin
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 108
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        // Only the bar accepts input (it is off-screen while hidden).
        mask: Region { item: dock }

        Rectangle {
            id: dock
            readonly property int cell: Math.round(rootShell.dockIconSize + 16)
            readonly property int barHeight: cell + 14

            HoverHandler {
                onHoveredChanged: {
                    rootShell.dockHovered = hovered
                    if (hovered) rootShell.revealDock()
                    else rootShell.scheduleHideDock()
                }
            }

            property bool visibleDock: rootShell.dockRevealed || !rootShell.dockAutoHidden || rootShell.hasMinimized
            x: {
                if (rootShell.dockAlignment === "left") return rootShell.dockMargin
                if (rootShell.dockAlignment === "right") return dockWin.width - width - rootShell.dockMargin
                return (dockWin.width - width) / 2
            }
            y: visibleDock ? (dockWin.height - height - Math.max(8, rootShell.dockMargin))
                           : (dockWin.height + 12)
            opacity: visibleDock ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Theme.animMedium } }
            Behavior on y {
                NumberAnimation { duration: Theme.animMedium; easing.type: Easing.OutCubic }
            }
            Behavior on x {
                NumberAnimation { duration: Theme.animMedium; easing.type: Easing.OutCubic }
            }

            height: barHeight
            radius: 20
            color: Theme.darkMode ? "#B81A1A21" : "#D9FFFFFF"
            border.color: Theme.darkMode ? "#38FFFFFF" : "#22000000"
            border.width: 1
            width: dockRow.implicitWidth + 26

            // inner highlight ring for the floating-material look
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.color: Theme.darkMode ? "#14FFFFFF" : "#80FFFFFF"
                border.width: 1
            }

            Row {
                id: dockRow
                anchors.centerIn: parent
                spacing: Theme.spacingSm

                // ---- Section 1: pinned applications ----
                Repeater {
                    model: rootShell.pinnedEntries()
                    delegate: Item {
                        id: pinnedCell
                        width: dock.cell + 2
                        height: dock.cell + 2

                        readonly property var tls: rootShell.toplevelsForEntry(modelData)
                        readonly property bool running: tls.length > 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: dock.cell
                            height: dock.cell
                            radius: 13
                            color: pinHover.hovered ? Theme.hoverBg : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            CanopyIcon {
                                id: pinIcon
                                anchors.centerIn: parent
                                size: rootShell.dockIconSize
                                iconName: modelData.icon ? modelData.icon : ""
                                scale: (pinHover.hovered && rootShell.dockMagnify) ? 1.14 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        // running indicator: a bar when running, invisible otherwise
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: pinnedCell.running ? 16 : 0
                            height: 3
                            radius: 1.5
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: Theme.animFast } }
                        }

                        HoverHandler {
                            id: pinHover
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(pinnedCell, modelData.name ? modelData.name : (modelData.id || ""),
                                                 pinnedCell.running ? "Running - click to show" : "Click to launch",
                                                 "top")
                                else
                                    Tooltip.hide()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                Tooltip.hide()
                                if (m.button === Qt.RightButton) {
                                    MenuController.show(rootShell.dockMenuForEntry(modelData), pinnedCell, "above")
                                } else if (pinnedCell.tls.length > 0) {
                                    pinnedCell.tls[0].activate()
                                } else {
                                    modelData.execute()
                                }
                            }
                        }
                    }
                }

                // Divider: pinned | minimized (only when that section has content)
                Item {
                    visible: rootShell.minimizedCount > 0 || rootShell.activeUnpinnedCount > 0
                    width: 9
                    height: dock.cell
                    Rectangle {
                        anchors.centerIn: parent
                        width: 1
                        height: Math.round(dock.cell * 0.62)
                        color: Theme.darkMode ? "#3DFFFFFF" : "#2E000000"
                    }
                }

                // ---- Section 2: minimized windows ----
                Repeater {
                    model: ToplevelManager.toplevels
                    delegate: Item {
                        id: minCell
                        readonly property bool shown: modelData.minimized && !rootShell.isPinnedAppId(modelData.appId)
                        width: shown ? dock.cell + 2 : 0
                        height: dock.cell + 2
                        visible: shown

                        readonly property var entry: DesktopEntries.heuristicLookup(modelData.appId)

                        Rectangle {
                            anchors.centerIn: parent
                            width: dock.cell
                            height: dock.cell
                            radius: 13
                            color: minHover.hovered ? Theme.hoverBg : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            CanopyIcon {
                                anchors.centerIn: parent
                                size: Math.round(rootShell.dockIconSize * 0.85)
                                opacity: 0.75
                                iconName: (minCell.entry && minCell.entry.icon) ? minCell.entry.icon : ""
                                scale: (minHover.hovered && rootShell.dockMagnify) ? 1.12 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        // minimized indicator: dim, thin bar
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 10
                            height: 3
                            radius: 1.5
                            color: Theme.textMuted
                            opacity: 0.6
                        }

                        HoverHandler {
                            id: minHover
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(minCell, modelData.title ? modelData.title : (modelData.appId || "Window"),
                                                 "Minimized - click to restore", "top")
                                else
                                    Tooltip.hide()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                Tooltip.hide()
                                if (m.button === Qt.RightButton)
                                    MenuController.show(rootShell.dockMenuForToplevel(modelData, minCell.entry), minCell, "above")
                                else
                                    modelData.activate()
                            }
                        }
                    }
                }

                // Divider: minimized | active (only between two populated sections)
                Item {
                    visible: rootShell.minimizedCount > 0 && rootShell.activeUnpinnedCount > 0
                    width: 9
                    height: dock.cell
                    Rectangle {
                        anchors.centerIn: parent
                        width: 1
                        height: Math.round(dock.cell * 0.62)
                        color: Theme.darkMode ? "#3DFFFFFF" : "#2E000000"
                    }
                }

                // ---- Section 3: active, unpinned windows ----
                Repeater {
                    model: ToplevelManager.toplevels
                    delegate: Item {
                        id: actCell
                        readonly property bool shown: !modelData.minimized && !rootShell.isPinnedAppId(modelData.appId)
                        width: shown ? dock.cell + 2 : 0
                        height: dock.cell + 2
                        visible: shown

                        readonly property var entry: DesktopEntries.heuristicLookup(modelData.appId)

                        Rectangle {
                            anchors.centerIn: parent
                            width: dock.cell
                            height: dock.cell
                            radius: 13
                            color: actHover.hovered ? Theme.hoverBg : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            CanopyIcon {
                                anchors.centerIn: parent
                                size: Math.round(rootShell.dockIconSize * 0.85)
                                iconName: (actCell.entry && actCell.entry.icon) ? actCell.entry.icon : ""
                                scale: (actHover.hovered && rootShell.dockMagnify) ? 1.12 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: modelData.activated ? 18 : 10
                            height: 3
                            radius: 1.5
                            color: modelData.activated ? Theme.accent : Theme.textMuted
                            opacity: modelData.activated ? 1.0 : 0.6
                            Behavior on width { NumberAnimation { duration: Theme.animFast } }
                        }

                        HoverHandler {
                            id: actHover
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(actCell, modelData.title ? modelData.title : (modelData.appId || "Window"),
                                                 modelData.activated ? "Active window" : "Running",
                                                 "top")
                                else
                                    Tooltip.hide()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                Tooltip.hide()
                                if (m.button === Qt.RightButton)
                                    MenuController.show(rootShell.dockMenuForToplevel(modelData, actCell.entry), actCell, "above")
                                else
                                    modelData.activate()
                            }
                        }
                    }
                }
            }

        }
    }

    // ---- Launcher (Windows 11 Start) ----
    PanelWindow {
        id: launcherWin
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: rootShell.launcherOpen
        exclusionMode: ExclusionMode.Ignore
        focusable: true

        // Keys must reach the launcher the moment it opens, so it takes the
        // keyboard exclusively while visible (Super is bound in labwc and
        // toggles this window from outside the shell).
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "canopy-launcher"
        WlrLayershell.keyboardFocus: rootShell.launcherOpen ? WlrKeyboardFocus.Exclusive
                                                          : WlrKeyboardFocus.None

        property string query: ""
        property int cursor: 0
        property bool allAppsView: false
        readonly property var results: rootShell.filteredApps(query)
        readonly property int columns: 6

        onVisibleChanged: {
            if (visible) {
                cursor = 0
                query = ""
                Qt.callLater(function () { searchInput.forceActiveFocus() })
            } else {
                query = ""
                allAppsView = false
            }
        }

        readonly property var pinnedSlice: {
            if (query !== "") return results.slice(0, 18)
            const favs = rootShell.pinnedEntries()
            const seen = {}
            const out = []
            for (let i = 0; i < favs.length; i++) {
                if (seen[favs[i].id]) continue
                seen[favs[i].id] = true
                out.push(favs[i])
            }
            for (let i = 0; i < results.length && out.length < 18; i++) {
                if (seen[results[i].id]) continue
                seen[results[i].id] = true
                out.push(results[i])
            }
            return out.slice(0, 18)
        }
        readonly property var recommendedSlice: {
            const skip = {}
            for (let i = 0; i < pinnedSlice.length; i++) skip[pinnedSlice[i].id] = true
            const out = []
            for (let i = 0; i < results.length && out.length < 4; i++) {
                if (!skip[results[i].id]) out.push(results[i])
            }
            return out
        }

        function move(delta) {
            const n = pinnedSlice.length
            if (n === 0) return
            cursor = (cursor + delta + n) % n
        }
        function moveRow(delta) {
            const n = pinnedSlice.length
            if (n === 0) return
            const next = cursor + delta * columns
            if (next >= 0 && next < n) cursor = next
            else if (next < 0) cursor = Math.max(0, cursor % columns)
            else cursor = n - 1
        }
        function launchCurrent() {
            if (pinnedSlice.length > 0 && cursor >= 0 && cursor < pinnedSlice.length) {
                const entry = pinnedSlice[cursor]
                closeLauncher()
                entry.execute()
            }
        }
        function closeLauncher() {
            rootShell.closeOverlays()
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.darkMode ? "#99000000" : "#4D000000"
            MouseArea { anchors.fill: parent; onClicked: launcherWin.closeLauncher() }

            // --- Start card, bottom anchored like Windows 11 ---
            Rectangle {
                id: startCard
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 104
                width: Math.min(parent.width * 0.58, 760)
                height: Math.min(parent.height - 150, 660)
                radius: 16
                color: Theme.darkMode ? "#F01B1B22" : "#F7FFFFFF"
                border.color: Theme.darkMode ? "#33FFFFFF" : "#1A000000"
                border.width: 1
                // Nothing may cross the rounded corners, no matter how many
                // results the search produces or how tall the recommended list gets.
                clip: true
                clip: true

                // ---- content ----
                Column {
                    id: startColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    readonly property real innerW: width
                    readonly property real cellW: Math.floor(innerW / 6)
                    readonly property real cellH: Math.min(100, Math.floor(cellW * 0.92))
                    readonly property int gridRows: Math.min(3, Math.max(1, Math.ceil(launcherWin.pinnedSlice.length / 6)))
                    readonly property real gridH: cellH * gridRows + 6
                    readonly property real recH: Math.max(46, height - 38 - 24 - gridH - 20 - 44 - 12 * 5)
                    readonly property var allList: rootShell.filteredApps("")

                    // search capsule
                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: 19
                        color: Theme.darkMode ? "#26FFFFFF" : "#11000000"
                        border.color: searchInput.activeFocus ? Theme.accent
                                                              : (Theme.darkMode ? "#33FFFFFF" : "#1F000000")
                        border.width: 1
                clip: true
                // Cabinet contents never spill past the rounded corners.
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "edit-find-symbolic"
                            tint: Theme.textSecondary
                        }

                        TextInput {
                            id: searchInput
                            anchors.left: parent.left
                            anchors.leftMargin: 40
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeMd
                            font.family: Theme.fontFamily
                            selectionColor: Theme.accent
                            focus: rootShell.launcherOpen
                            onTextChanged: { launcherWin.query = text; launcherWin.cursor = 0 }
                            Keys.onPressed: (e) => {
                                if (e.key === Qt.Key_Escape) { launcherWin.closeLauncher(); e.accepted = true }
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { launcherWin.launchCurrent(); e.accepted = true }
                                else if (e.key === Qt.Key_Down) { launcherWin.moveRow(1); e.accepted = true }
                                else if (e.key === Qt.Key_Up) { launcherWin.moveRow(-1); e.accepted = true }
                                else if (e.key === Qt.Key_Right) { launcherWin.move(1); e.accepted = true }
                                else if (e.key === Qt.Key_Left) { launcherWin.move(-1); e.accepted = true }
                            }
                            // Pressing Super while the launcher is open must close it.
                            // The labwc keybind cannot fire here: the launcher holds the
                            // keyboard exclusively, so the compositor never sees the key.
                            Keys.onReleased: (e) => {
                                if (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta) {
                                    launcherWin.closeLauncher()
                                    e.accepted = true
                                }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 40
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search applications"
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeMd
                            font.family: Theme.fontFamily
                            visible: searchInput.text === ""
                        }
                    }

                    // section header
                    Row {
                        width: parent.width
                        height: 24
                        spacing: 10

                        Text {
                            text: launcherWin.allAppsView ? "All apps"
                                  : (launcherWin.query === "" ? "Pinned" : "Best matches")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            font.family: Theme.fontFamily
                        }
                        Item { width: parent.width - 88 - 60; height: 1 }

                        Rectangle {
                            width: 88; height: 24; radius: 12
                            color: allMa.containsMouse ? (Theme.darkMode ? "#33FFFFFF" : "#14000000") : "transparent"
                            border.color: Theme.darkMode ? "#33FFFFFF" : "#1F000000"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: launcherWin.allAppsView ? "\u2039  Back" : "All apps  \u203A"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeXs
                                font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: allMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: launcherWin.allAppsView = !launcherWin.allAppsView
                            }
                        }
                    }

                    // empty search state
                    Text {
                        visible: !launcherWin.allAppsView && launcherWin.pinnedSlice.length === 0
                        width: parent.width
                        height: visible ? startColumn.gridH : 0
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: launcherWin.query === "" ? "No applications found"
                                                        : "No matches for \u201C" + launcherWin.query + "\u201D"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSm
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    // pinned grid (3 rows)
                    GridView {
                        id: grid
                        visible: !launcherWin.allAppsView
                        width: parent.width
                        height: launcherWin.allAppsView ? 0 : startColumn.gridH
                        cellWidth: startColumn.cellW
                        cellHeight: startColumn.cellH
                        clip: true
                        model: launcherWin.pinnedSlice
                        currentIndex: launcherWin.cursor
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            width: grid.cellWidth
                            height: grid.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 10
                                color: (index === launcherWin.cursor || hov.hovered)
                                       ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000")
                                       : "transparent"

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 7
                                    CanopyIcon {
                                        size: 38
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        iconName: modelData.icon ? modelData.icon : ""
                                    }
                                    Text {
                                        width: grid.cellWidth - 20
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.name
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSizeXs
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            HoverHandler {
                                id: hov
                                onHoveredChanged: if (hovered) launcherWin.cursor = index
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { modelData.execute(); launcherWin.closeLauncher() }
                            }
                        }
                    }

                    // recommended header
                    Row {
                        readonly property bool shown: !launcherWin.allAppsView
                                                      && launcherWin.recommendedSlice.length > 0
                        width: parent.width
                        height: shown ? 24 : 0
                        spacing: 10
                        visible: shown

                        Text {
                            text: "Recommended"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            font.family: Theme.fontFamily
                        }
                        Item { width: Math.max(0, parent.width - 150); height: 1 }
                        Rectangle {
                            width: 62; height: 20; radius: 10
                            color: moreMa.containsMouse ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000") : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "More  \u203A"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeXs
                                font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: moreMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: launcherWin.allAppsView = true
                            }
                        }
                    }

                    // recommended list
                    GridView {
                        width: parent.width
                        height: (!launcherWin.allAppsView && launcherWin.recommendedSlice.length > 0)
                                ? startColumn.recH : 0
                        visible: !launcherWin.allAppsView && launcherWin.recommendedSlice.length > 0
                        cellWidth: Math.floor(width / 2)
                        cellHeight: 46
                        clip: true
                        model: launcherWin.recommendedSlice
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: GridView.view.cellWidth
                            height: 46
                            radius: 8
                            color: rma.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                CanopyIcon {
                                    size: 26
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: modelData.icon ? modelData.icon : ""
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    Text {
                                        text: modelData.name
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSizeSm
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                        width: 200
                                    }
                                    Text {
                                        text: "Application"
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontFamily
                                    }
                                }
                            }
                            MouseArea {
                                id: rma
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { modelData.execute(); launcherWin.closeLauncher() }
                            }
                        }
                    }

                    // --- all apps list ---
                    ListView {
                        visible: launcherWin.allAppsView
                        width: parent.width
                        height: Math.max(120, parent.height - 38 - 24 - 44 - 12 * 4)
                        clip: true
                        model: startColumn.allList
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: 2

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 40
                            radius: 8
                            color: ama.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                CanopyIcon {
                                    size: 24
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: modelData.icon ? modelData.icon : ""
                                }
                                Text {
                                    width: ListView.view ? ListView.view.width - 72 : 240
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeSm
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: ama
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { modelData.execute(); launcherWin.closeLauncher() }
                            }
                        }
                    }

                    // ---- footer ----
                    Rectangle {
                        id: footerBar
                        width: parent.width
                        height: 44
                        radius: 10
                        color: Theme.darkMode ? "#14FFFFFF" : "#0A000000"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: (Quickshell.env("USER") || "u").charAt(0).toUpperCase()
                                    color: "white"
                                    font.pixelSize: Theme.fontSizeXs
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Quickshell.env("USER") || ""
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                            }
                        }

                        CanopyIcon {
                            size: 17
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "system-shutdown-symbolic"
                            tint: Theme.textSecondary
                        }
                    }
                }
            }
        }
    }

    // ---- Calendar (click the clock) ----
    PanelWindow {
        id: calendarWin
        anchors { top: true; left: true; right: true }
        implicitHeight: 356
        color: "transparent"
        visible: rootShell.calendarOpen
        exclusionMode: ExclusionMode.Ignore

        // Only the card accepts input. Without this the full-width window
        // covers the panel and the clock can no longer be clicked to close it.
        mask: Region { item: calCard }

        property date ref: new Date()
        readonly property int year: ref.getFullYear()
        readonly property int month: ref.getMonth()
        readonly property int firstDow: new Date(year, month, 1).getDay()
        readonly property int days: new Date(year, month + 1, 0).getDate()
        readonly property int today: new Date().getDate()
        readonly property bool isCurrentMonth: {
            const n = new Date()
            return n.getFullYear() === year && n.getMonth() === month
        }

        function shift(delta) {
            ref = new Date(year, month + delta, 1)
        }

        Rectangle {
            id: calCard
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 38
            width: 320
            height: 296
            radius: 14
            color: Theme.darkMode ? "#F21B1B22" : "#FAFFFFFF"
            border.color: Theme.darkMode ? "#33FFFFFF" : "#1A000000"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                // header
                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: 26; height: 26; radius: 8
                        color: prevMa.containsMouse ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000") : "transparent"
                        Text { anchors.centerIn: parent; text: "\u2039"; color: Theme.textPrimary; font.pixelSize: 16 }
                        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: calendarWin.shift(-1) }
                    }

                    Text {
                        width: parent.width - 68
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(calendarWin.ref, "MMMM yyyy")
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        font.family: Theme.fontFamily
                    }

                    Rectangle {
                        width: 26; height: 26; radius: 8
                        color: nextMa.containsMouse ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000") : "transparent"
                        Text { anchors.centerIn: parent; text: "\u203A"; color: Theme.textPrimary; font.pixelSize: 16 }
                        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: calendarWin.shift(1) }
                    }
                }

                // weekday header
                Row {
                    width: parent.width
                    Repeater {
                        model: ["S", "M", "T", "W", "T", "F", "S"]
                        delegate: Text {
                            width: parent.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontFamily
                        }
                    }
                }

                // day grid
                Grid {
                    columns: 7
                    width: parent.width
                    Repeater {
                        model: 42
                        delegate: Item {
                            width: parent.width / 7
                            height: 32
                            property int dayNum: index - calendarWin.firstDow + 1
                            property bool valid: dayNum >= 1 && dayNum <= calendarWin.days
                            property bool isToday: valid && calendarWin.isCurrentMonth && dayNum === calendarWin.today

                            Rectangle {
                                anchors.centerIn: parent
                                width: 28; height: 28; radius: 14
                                color: parent.isToday ? Theme.accent
                                                     : (dayMa.containsMouse && parent.valid ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000") : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.parent.valid ? String(parent.parent.dayNum) : ""
                                    color: parent.parent.isToday ? "white"
                                           : (parent.parent.valid ? Theme.textPrimary : "transparent")
                                    font.pixelSize: Theme.fontSizeSm
                                    font.family: Theme.fontFamily
                                }
                                MouseArea { id: dayMa; anchors.fill: parent; hoverEnabled: true }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Quick Settings (control-panel style) ----
    PanelWindow {
        id: qsWin
        anchors { top: true; right: true }
        margins.top: rootShell.panelVisible ? rootShell.panelHeight : 0
        implicitWidth: 372
        // Never taller than the space under the panel - a long network list
        // scrolls inside the card instead of running off the screen.
        implicitHeight: Math.min(qsCard.implicitHeight + 20,
                                 (screen ? screen.height : 720) - (rootShell.panelVisible ? rootShell.panelHeight : 0) - 16)
        visible: rootShell.quickSettingsOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        mask: Region { item: qsCard }

        readonly property var sink: Pipewire.defaultAudioSink
        readonly property real volume: (sink && sink.audio) ? sink.audio.volume : 0

        Rectangle {
            id: qsCard
            anchors.fill: parent
            anchors.margins: 10
            implicitHeight: qsCol.implicitHeight + 32
            radius: 20
            color: Theme.darkMode ? "#F21B1B22" : "#FAFFFFFF"
            border.color: Theme.darkMode ? "#33FFFFFF" : "#1A000000"
            border.width: 1

            Flickable {
                id: qsFlick
                anchors.fill: parent
                anchors.margins: 16
                clip: true
                contentWidth: width
                contentHeight: qsCol.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: qsCol
                    width: qsFlick.width
                    spacing: 14
                // header
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width - 34
                        text: "Quick settings"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Font.DemiBold
                        font.family: Theme.fontFamily
                    }
                    Rectangle {
                        width: 26; height: 26; radius: 8
                        color: qsCloseMa.containsMouse ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000") : "transparent"
                        Text { anchors.centerIn: parent; text: "\u00D7"; color: Theme.textSecondary; font.pixelSize: 16 }
                        MouseArea { id: qsCloseMa; anchors.fill: parent; hoverEnabled: true; onClicked: rootShell.quickSettingsOpen = false }
                    }
                }

                // ---- toggle tiles ----
                Grid {
                    columns: 2
                    spacing: 10
                    width: parent.width
                    readonly property real tileW: (width - 10) / 2

                    // Wi-Fi
                    Rectangle {
                        id: wifiTile
                        width: parent.tileW; height: 74; radius: 14
                        color: Networking.wifiEnabled ? Theme.accent
                                                      : (Theme.darkMode ? "#1FFFFFFF" : "#0F000000")
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        HoverHandler {
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(wifiTile, "Wi-Fi",
                                                 Networking.wifiEnabled ? "On - click to turn off" : "Off - click to turn on",
                                                 "bottom")
                                else
                                    Tooltip.hide()
                            }
                        }

                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            CanopyIcon {
                                size: 22
                                iconName: "network-wireless-symbolic"
                                tint: Networking.wifiEnabled ? "white" : Theme.textPrimary
                            }
                            Text {
                                text: "Wi-Fi"
                                color: Networking.wifiEnabled ? "white" : Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: Networking.wifiEnabled ? "On" : "Off"
                                color: Networking.wifiEnabled ? "#D9FFFFFF" : Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                    }

                    // Bluetooth
                    Rectangle {
                        id: btTile
                        width: parent.tileW; height: 74; radius: 14
                        readonly property bool on: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
                        color: on ? Theme.accent : (Theme.darkMode ? "#1FFFFFFF" : "#0F000000")
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        HoverHandler {
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(btTile, "Bluetooth",
                                                 Bluetooth.defaultAdapter
                                                     ? (btTile.on ? "On - click to turn off" : "Off - click to turn on")
                                                     : "No adapter detected",
                                                 "bottom")
                                else
                                    Tooltip.hide()
                            }
                        }

                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            CanopyIcon {
                                size: 22
                                iconName: "network-bluetooth-symbolic"
                                tint: parent.parent.on ? "white" : Theme.textPrimary
                            }
                            Text {
                                text: "Bluetooth"
                                color: parent.parent.on ? "white" : Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: Bluetooth.defaultAdapter ? (parent.parent.on ? "On" : "Off") : "Unavailable"
                                color: parent.parent.on ? "#D9FFFFFF" : Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Bluetooth.defaultAdapter)
                                    Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                            }
                        }
                    }

                    // Dark mode
                    Rectangle {
                        id: themeTile
                        width: parent.tileW; height: 74; radius: 14
                        color: Theme.darkMode ? Theme.accent : (Theme.darkMode ? "#1FFFFFFF" : "#0F000000")
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        HoverHandler {
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(themeTile, "Appearance",
                                                 Theme.darkMode ? "Dark theme - click for light" : "Light theme - click for dark",
                                                 "bottom")
                                else
                                    Tooltip.hide()
                            }
                        }

                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            CanopyIcon {
                                size: 22
                                iconName: "preferences-desktop-theme"
                                tint: "transparent"
                            }
                            Text {
                                text: "Dark mode"
                                color: Theme.darkMode ? "white" : Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: Theme.darkMode ? "On" : "Off"
                                color: Theme.darkMode ? "#D9FFFFFF" : Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { rootShell.setThemeMode(Theme.darkMode ? "light" : "dark"); rootShell.saveSettings() }
                        }
                    }

                    // Power profile
                    Rectangle {
                        id: batteryTile
                        width: parent.tileW; height: 74; radius: 14
                        color: Theme.darkMode ? "#1FFFFFFF" : "#0F000000"

                        HoverHandler {
                            onHoveredChanged: {
                                if (hovered)
                                    Tooltip.show(batteryTile, "Battery",
                                                 rootShell.hasBattery
                                                     ? Math.round(rootShell.batteryPercent) + "% - right-click for power options"
                                                     : "No battery detected",
                                                 "bottom")
                                else
                                    Tooltip.hide()
                            }
                        }

                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            CanopyIcon {
                                size: 22
                                iconName: "battery"
                                tint: Theme.textPrimary
                            }
                            Text {
                                text: "Battery"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: rootShell.hasBattery
                                      ? (Math.round(rootShell.batteryPercent) + "%")
                                      : "No battery"
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }

                // ---- volume ----
                Column {
                    width: parent.width
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 8

                        // speaker doubles as the mute toggle
                        Item {
                            width: 22
                            height: 18
                            CanopyIcon {
                                anchors.centerIn: parent
                                size: 18
                                iconName: qsWin.sink && qsWin.sink.audio && qsWin.sink.audio.muted
                                        ? "audio-volume-muted-symbolic" : rootShell.volumeIconName()
                                tint: Theme.textPrimary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (qsWin.sink && qsWin.sink.audio)
                                        qsWin.sink.audio.muted = !qsWin.sink.audio.muted
                                }
                            }
                        }
                        Text {
                            text: rootShell.sinkLabel(qsWin.sink)
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            width: parent.width - 130
                        }
                        Item { width: Math.max(0, parent.width - 190); height: 1 }
                        Text {
                            text: (qsWin.sink && qsWin.sink.audio && qsWin.sink.audio.muted)
                                  ? "Muted" : Math.round(qsWin.volume * 100) + "%"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeXs
                            font.family: Theme.fontFamily
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 10
                        radius: 5
                        color: Theme.darkMode ? "#2EFFFFFF" : "#14000000"

                        Rectangle {
                            width: Math.max(10, parent.width * Math.min(1, Math.max(0, qsWin.volume)))
                            height: parent.height
                            radius: 5
                            color: Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function setVol(mx) {
                                if (!qsWin.sink || !qsWin.sink.audio) return
                                const v = Math.min(1, Math.max(0, mx / width))
                                qsWin.sink.audio.volume = v
                            }
                            onClicked: (m) => setVol(m.x)
                            onPositionChanged: (m) => { if (pressed) setVol(m.x) }
                        }
                    }
                }

                // ---- network list (shown when opened from the tray) ----
                Column {
                    width: parent.width
                    spacing: 6
                    visible: rootShell.qsSection === "network" || rootShell.qsSection === "home"

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Networks"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeXs
                            font.family: Theme.fontFamily
                        }
                        Item { width: Math.max(0, parent.width - 120); height: 1 }

                        // Forces NetworkManager to rescan right now
                        Rectangle {
                            width: 74; height: 22; radius: 11
                            color: scanMa.containsMouse ? Theme.hoverBg : "transparent"
                            border.color: Theme.border
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Scan"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeXs
                                font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: scanMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootShell.rescanNetworks()
                            }
                        }
                    }

                    Text {
                        visible: Networking.wifiEnabled && rootShell.wifiNetworks().length === 0
                        text: "No networks found yet - scanning\u2026"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                        font.family: Theme.fontFamily
                    }

                    Repeater {
                        model: rootShell.wifiNetworks()

                        delegate: Rectangle {
                            readonly property int level: rootShell.signalLevel(modelData)
                            width: parent.width
                            height: 36
                            radius: 10
                            color: netMa.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                CanopyIcon {
                                    size: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: modelData.connected ? "network-wireless-symbolic"
                                                                  : "network-wireless-signal-none-symbolic"
                                    opacity: modelData.connected ? 1.0 : 0.55 + (level / 250)
                                    tint: Theme.textPrimary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 120
                                    text: modelData.name
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeSm
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.connected ? "Connected"
                                          : (level > 0 ? level + "%" : "")
                                    color: modelData.connected ? Theme.accent : Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontFamily
                                }
                                CanopyIcon {
                                    visible: modelData.security !== undefined
                                             && String(modelData.security) !== "Open"
                                    size: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "security-high-symbolic"
                                    tint: Theme.textMuted
                                }
                            }

                            MouseArea {
                                id: netMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (m) => {
                                    if (m.button === Qt.RightButton) {
                                        const items = []
                                        if (modelData.connected)
                                            items.push({ label: "Disconnect",
                                                         run: function () { modelData.disconnect() } })
                                        else
                                            items.push({ label: "Connect",
                                                         run: function () { modelData.connect() } })
                                        if (modelData.known)
                                            items.push({ label: "Forget network", danger: true,
                                                         run: function () { modelData.forget() } })
                                        items.push({ sep: true })
                                        items.push({ label: "Network settings", icon: "preferences-system-symbolic",
                                                     run: function () { rootShell.openSettingsAt(4) } })
                                        MenuController.show(items, netMa, "left")
                                    } else if (modelData.connected) {
                                        modelData.disconnect()
                                    } else {
                                        modelData.connect()
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- output devices (PipeWire sinks) ----
                Column {
                    width: parent.width
                    spacing: 4
                    visible: rootShell.qsSection === "audio" || rootShell.qsSection === "home"

                    Row {
                        width: parent.width
                        spacing: 8
                        Text {
                            text: "Output device"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeXs
                            font.family: Theme.fontFamily
                        }
                    }

                    Repeater {
                        model: rootShell.audioSinks

                        delegate: Rectangle {
                            width: parent.width
                            height: 34
                            radius: 10
                            color: devMa.containsMouse ? Theme.hoverBg
                                   : (Pipewire.defaultAudioSink === modelData ? Theme.selectedBg : "transparent")

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                CanopyIcon {
                                    size: 15
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "audio-speakers-symbolic"
                                    tint: Pipewire.defaultAudioSink === modelData ? Theme.accent : Theme.textPrimary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 46
                                    text: rootShell.sinkLabel(modelData)
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeXs
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                }
                                CanopyIcon {
                                    visible: Pipewire.defaultAudioSink === modelData
                                    size: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "emblem-ok-symbolic"
                                    tint: Theme.accent
                                }
                            }

                            MouseArea {
                                id: devMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootShell.setDefaultSink(modelData)
                            }
                        }
                    }
                }

                    Item { width: 1; height: 1; LayoutMirroring.enabled: false }
                }
            }
        }
    }

    // ---- Notification centre ----
    PanelWindow {
        id: notifWin
        anchors { top: true; right: true; bottom: true }
        margins.top: rootShell.panelVisible ? rootShell.panelHeight : 0
        implicitWidth: 372
        visible: rootShell.notificationsOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        mask: Region { item: notifCard }

        Rectangle {
            id: notifCard
            anchors.fill: parent
            anchors.margins: 10
            radius: 20
            color: Theme.darkMode ? "#F21B1B22" : "#FAFFFFFF"
            border.color: Theme.darkMode ? "#33FFFFFF" : "#1A000000"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 8
                    Text {
                        width: parent.width - 100
                        text: "Notifications"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Font.DemiBold
                        font.family: Theme.fontFamily
                    }
                    Rectangle {
                        width: 70; height: 24; radius: 12
                        color: clearMa.containsMouse ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000") : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "Clear all"
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeXs
                            font.family: Theme.fontFamily
                        }
                        MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; onClicked: notificationModel.clear() }
                    }
                }

                Text {
                    visible: notificationModel.count === 0
                    text: "No notifications"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSm
                    font.family: Theme.fontFamily
                }

                ListView {
                    width: parent.width
                    height: parent.height - 90
                    clip: true
                    spacing: 8
                    model: notificationModel
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        width: ListView.view ? ListView.view.width : 300
                        height: 74
                        radius: 12
                        color: Theme.darkMode ? "#1FFFFFFF" : "#0D000000"

                        Row {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            CanopyIcon {
                                size: 20
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "dialog-information"
                            }
                            Column {
                                width: parent.width - 60
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: model.title
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: model.body
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeXs
                                    font.family: Theme.fontFamily
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            Rectangle {
                                width: 22; height: 22; radius: 11
                                anchors.verticalCenter: parent.verticalCenter
                                color: disMa.containsMouse ? (Theme.darkMode ? "#26FFFFFF" : "#0F000000") : "transparent"
                                Text { anchors.centerIn: parent; text: "\u00D7"; color: Theme.textSecondary; font.pixelSize: 13 }
                                MouseArea { id: disMa; anchors.fill: parent; hoverEnabled: true; onClicked: notificationModel.remove(index) }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Settings (modular subsystem in shell/Settings) ----
    SettingsWindow {
        id: settingsWin
        visible: rootShell.settingsOpen
        store: store
        shell: rootShell
        onCloseRequested: rootShell.settingsOpen = false
    }

    // ---- Shared tooltips + context menus ----
    // One overlay renders every tooltip and context menu in the shell, so
    // styling, delay and edge handling are identical everywhere.
    InteractionOverlay {
        id: interactionOverlay
    }

    // ---- Notifications ----
    Repeater {
        model: notificationModel
        delegate: PanelWindow {
            anchors { top: true; right: true }
            implicitWidth: 340
            implicitHeight: 84
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            margins { top: 52 + index * 92; right: 12 }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: Theme.radiusMedium
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: Theme.spacingMd

                                        CanopyIcon {
                        size: 24
                        iconName: "dialog-information"
                    }
                    Column {
                        spacing: 2
                        Text { text: model.title; color: Theme.textPrimary; font.weight: Font.Bold; font.pixelSize: Theme.fontSizeMd; width: 280; elide: Text.ElideRight }
                        Text { text: model.body; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSm; width: 280; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                }
            }
        }
    }
}
