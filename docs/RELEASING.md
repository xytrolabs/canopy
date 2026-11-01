# Releasing Canopy

Canopy is not packaged by any distribution, so every release is a
self-extracting `.run` built from the tree and published on GitHub. The shell's
**Software updates** card and the `canopy-update` command both read those
releases; the project site mirrors them.

## Cut a release

```sh
# 1. Build the payload for a specific version
CANOPY_VERSION=2026.11.15 sh scripts/build-release.sh
#    -> dist/canopy-2026.11.15.run

# 2. Tag and push; GitHub Actions does the rest
git tag v2026.11.15
git push origin v2026.11.15
```

`.github/workflows/release.yml` builds the payload, writes `SHA256SUMS`, and
attaches **both** to the release:

```
canopy-2026.11.15.run
SHA256SUMS
```

Those two file names are the update protocol. Renaming them breaks
`canopy-update` for everyone, so don't.

## Mirror it on the site (optional)

The site can serve releases itself, which is what `CANOPY_BASE_URL` points at:

```sh
sh scripts/build-release.sh
cp dist/canopy-*.run  ~/Desktop/XytroLabs/canopy-site/releases/
cd ~/Desktop/XytroLabs/canopy-site/releases
sha256sum canopy-*.run > SHA256SUMS
ls canopy-*.run | tail -1 > latest      # one line: the newest payload
```

`install.sh` and `canopy-update` verify the payload against `SHA256SUMS` before
running it, from either source.

## How updates resolve

`canopy-update` looks in this order and remembers which answered:

1. `CANOPY_BASE_URL` — an explicit mirror (the tests use a local server)
2. **GitHub Releases** — `api.github.com/repos/<repo>/releases/latest`, then
   `github.com/<repo>/releases/download/<tag>/canopy-<version>.run`
3. `https://canopy.xytro.site` — the site, if GitHub is unreachable

`CANOPY_REPO` changes the repository, `CANOPY_UPDATE_SOURCE=github|site` forces
one source.

```sh
canopy-update check          # installed / latest / status
canopy-update check --json   # {"installed":…,"latest":…,"update_available":…}
canopy-update apply          # download, verify, install
```

## Version identity

The version is a dotted UTC date (`2026.11.01`). It is written into the payload
as `VERSION`, installed next to the shell, and compared by `canopy-update`. The
updater records the release it installed, so a payload rebuilt from a checkout
does not keep re-offering the same update.
