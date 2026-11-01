# Supported distributions

Canopy needs three things: a `labwc` compositor, a `quickshell` runtime, and a
Qt 6 QML stack. Everything else — NetworkManager, PipeWire, UPower, BlueZ — is
already standard on a modern Linux desktop.

`scripts/lib-distro.sh` is the single place that knows which distribution you
are on and what its packages are called. `scripts/deps.sh` uses it to tell you
what is missing; the installer uses it to pick an icon theme that exists.

```sh
sh scripts/deps.sh plan        # what this machine lacks, and the exact command
sh scripts/deps.sh install     # install it (asks for sudo)
```

## Verified versions

Read from each project's own package index on 2026-11-01 — not from memory:

| Distribution | labwc | quickshell | Result |
| --- | --- | --- | --- |
| Arch / CachyOS (rolling) | 0.20.2 | 0.3.2 (`extra`) | **works from packages** |
| Fedora 45 | 0.20.2 | 0.2.1 | build the runtime (0.2.1 is too old) |
| Fedora 44 | 0.9.6 | 0.2.1 | build the runtime |
| Fedora 43 | 0.9.6 | absent | build the runtime |
| Debian trixie | 0.8.3 | 0.3.0 (`trixie-backports`) | backports for the shell, build labwc |
| Debian forky / sid | 0.20.2 | 0.3.2 | **works from packages** once trixie moves on |
| openSUSE | unverified | unverified | treated as manual |

Canopy targets the **quickshell 0.3.x** API (Networking, PipeWire, Pam,
Bluetooth services, `SystemTray`). quickshell 0.2.1 will start the shell and
then fail on those imports, so “too old” is a real failure, not a nicety.

## Distributions that need work

**Fedora 43/44/45** — build the runtime. The payload carries the helper:

```sh
sh scripts/build-quickshell.sh            # pins v0.3.2, installs to /usr/local
```

**Debian trixie** — two packages, two different answers:

```sh
# shell runtime: 0.3.0 is enough, and it is in backports
sudo apt-get install -t trixie-backports quickshell

# compositor: trixie's 0.8.3 predates the 0.20 keybind behaviour the panel uses.
# wlroots 0.18.2 is in trixie, so wlroots 0.20.2 goes in first:
sh scripts/build-wlroots.sh
sh scripts/build-labwc.sh
```

Keeping the packaged labwc 0.8.3 also works — the shell itself is not
version-locked — but window rules and `onRelease` keybinds differ.

## Anything else

If `lib-distro.sh` cannot identify the distribution it prints `unknown` and
`deps.sh plan` lists the runtime by capability rather than by package name.
Install labwc, quickshell and a Qt 6 QML stack however that distribution does
it; the shell only needs `quickshell -c canopy` to be able to start.

Adding a distribution is one `case` arm in `canopy_pkgs()` — the rest of the
code never mentions a package manager.
