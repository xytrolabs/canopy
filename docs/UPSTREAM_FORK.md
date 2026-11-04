# Canopy upstream fork notes

## Upstream source

- Project: Noctalia
- Repository: https://github.com/noctalia-dev/noctalia
- License: MIT (copyright and attribution retained)
- Pinned upstream tag: `v5.4.1`
- Pinned upstream commit: `815aebe1cfd79c9a18197441eea92f0b275035fc`

## Xytro Labs fork

- Branch: `canopy-dev`
- Version: `2026.11.04`
- Compositor: Labwc
- Build: `just configure release && just build release`

## Synchronization

1. Add/fetch the upstream remote.
2. `git fetch upstream --tags`
3. Create an integration branch from `canopy-dev`.
4. Merge or cherry-pick upstream changes, resolving branding and path changes.
5. Rebuild and verify with `just build release` before publishing.

## Branding maintained in this fork

- Binary and application identity: `canopy`
- Installed asset directory: `share/canopy`
- Default user config/state location: `~/.config/canopy`
- Window/application identifier: `dev.canopy.Canopy`
- Labwc configuration and window decoration theme: `config/labwc`
- Desktop entry: `assets/dev.canopy.Canopy.desktop`

Internal C++ namespaces remain `noctalia::` intentionally for practical upstream synchronization. User-facing names and storage paths use Canopy identifiers.
