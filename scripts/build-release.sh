#!/bin/sh
# build-release.sh — package Canopy into a single self-extracting installer.
#
# Produces: dist/canopy-<version>.run
#
#   sh scripts/build-release.sh                 # build + package
#   CANOPY_VERSION=2026.11.04 sh scripts/build-release.sh
#   CANOPY_SKIP_BUILD=1 sh scripts/build-release.sh   # package an existing build
#
# The payload contains the binary, the asset bundle, the session entry, the
# desktop portal config and every script needed to install, update or uninstall
# Canopy offline:
#
#   sh canopy-<version>.run          user install
#   sudo sh canopy-<version>.run     system install + Wayland session
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${CANOPY_VERSION:-$(tr -d ' \t\r\n' < "$PROJECT_DIR/VERSION" 2>/dev/null || date -u +%Y.%m.%d)}"
VERSION="$(printf '%s' "$VERSION" | sed 's/^v//')"
DIST="$PROJECT_DIR/dist"
STAGE="$DIST/stage"
OUT="$DIST/canopy-$VERSION.run"
BUILD_DIR="${CANOPY_BUILD_DIR:-$PROJECT_DIR/build-release}"

say() { printf '%s\n' "$*"; }

# ---- Build ---------------------------------------------------------------
if [ "${CANOPY_SKIP_BUILD:-0}" != "1" ]; then
    say ">> building Canopy $VERSION"
    if command -v just >/dev/null 2>&1; then
        just configure release >/dev/null
        just build release
    else
        meson setup "$BUILD_DIR" --buildtype=release -Dcpp_std=c++23 -Db_lto=true --prefix=/usr/local >/dev/null
        meson compile -C "$BUILD_DIR"
    fi
fi

[ -x "$BUILD_DIR/canopy" ] || { say "error: $BUILD_DIR/canopy is missing" >&2; exit 1; }

# The compositor is part of the desktop, not an optional extra: build it when it
# is missing so a release never ships a session that falls back to labwc.
COMPOSITOR_BUILD="${CANOPY_COMPOSITOR_BUILD:-$PROJECT_DIR/build-compositor}"
if [ "${CANOPY_SKIP_COMPOSITOR:-0}" != "1" ] && [ ! -x "$COMPOSITOR_BUILD/canopywc" ]; then
    say ">> building the compositor (canopywc)"
    if [ -f "$COMPOSITOR_BUILD/build.ninja" ]; then
        meson compile -C "$COMPOSITOR_BUILD"
    else
        meson setup "$COMPOSITOR_BUILD" "$PROJECT_DIR/compositor" --buildtype=release >/dev/null
        meson compile -C "$COMPOSITOR_BUILD"
    fi
fi

# ---- Stage ---------------------------------------------------------------
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/assets" "$STAGE/config" "$STAGE/scripts" "$STAGE/share"

cp "$BUILD_DIR/canopy" "$STAGE/bin/canopy"
if [ -x "$COMPOSITOR_BUILD/canopywc" ]; then
    say ">> including canopywc"
    mkdir -p "$STAGE/compositor"
    cp "$COMPOSITOR_BUILD/canopywc" "$STAGE/compositor/canopywc"
else
    say "error: canopywc is required in every Canopy release but is missing" >&2
    exit 1
fi
cp -a "$PROJECT_DIR"/assets/. "$STAGE/assets/"
cp -a "$PROJECT_DIR"/config/. "$STAGE/config/"
cp -a "$PROJECT_DIR"/scripts/. "$STAGE/scripts/"
cp "$PROJECT_DIR/README.md" "$STAGE/share/README.md" 2>/dev/null || true
cp "$PROJECT_DIR/LICENSE" "$STAGE/share/LICENSE" 2>/dev/null || true
cp "$PROJECT_DIR/docs/CANOPY_DESIGN.md" "$STAGE/share/CANOPY_DESIGN.md" 2>/dev/null || true
printf '%s\n' "$VERSION" > "$STAGE/VERSION"

# ---- Bundle shared libraries ---------------------------------------------
# A release has to run on a machine that has none of the build-time libraries.
# Copy every .so both binaries link against and point them at the bundle with an
# $ORIGIN rpath, so the payload carries its own copy instead of depending on the
# distribution's versions.
#
# glibc and the dynamic loader are deliberately excluded: bundling them breaks
# NSS and dlopen in ways that are much worse than the problem being solved, and
# every supported distribution has them. Graphics drivers (Mesa, libdrm) are also
# left out here because they must match the running kernel and GPU; the installer
# still checks those.
bundle_libraries() {
    _bin="$1"
    _dest="$2"
    [ -x "$_bin" ] || return 0
    _exclude='^/(usr/lib64/)?ld-linux|libc\.so|libm\.so|libpthread\.so|librt\.so|libdl\.so|libresolv\.so|libutil\.so'
    ldd "$_bin" 2>/dev/null \
        | awk '/=>/ { print $3 }' \
        | grep -v '^$' \
        | sort -u \
        | while IFS= read -r _lib; do
            [ -f "$_lib" ] || continue
            # Resolve symlinks so the real soname is copied, then keep the name.
            _name="$(basename "$_lib")"
            printf '%s\n' "$_lib" | grep -Eq "$_exclude" && continue
            [ -f "$_dest/$_name" ] || cp -L "$_lib" "$_dest/$_name" 2>/dev/null || true
        done
}

say ">> bundling shared libraries"
mkdir -p "$STAGE/lib"
bundle_libraries "$STAGE/bin/canopy" "$STAGE/lib"
bundle_libraries "$STAGE/compositor/canopywc" "$STAGE/lib"
_BUNDLED="$(find "$STAGE/lib" -type f 2>/dev/null | wc -l)"
say "   $_BUNDLED libraries ($(du -sh "$STAGE/lib" 2>/dev/null | cut -f1))"

# Point both binaries at the bundle, and give every bundled library $ORIGIN so
# the libraries can find each other.
#
# The second half matters more than it looks: glibc does not inherit RUNPATH.
# The shell's own RUNPATH finds libjxl.so.0.12 in the bundle, but when that
# library asks for libjxl_cms.so.0.12 the search falls back to the default
# system paths -- so the bundled copy is ignored and a distro that ships a
# different soname breaks startup. Each bundled library therefore needs its own
# $ORIGIN, which is what this loop sets.
#
# patchelf is the only reliable way to do that on an existing ELF (objcopy has
# no --add-rpath, and hand-editing the dynamic section corrupts the file). It is
# not part of a base install, so fetch a static build when it is missing rather
# than shipping a payload whose bundle silently does not work.
CANOPY_PATCHELF="${CANOPY_PATCHELF:-$(command -v patchelf 2>/dev/null || true)}"
if [ -z "$CANOPY_PATCHELF" ]; then
    _pf_dir="$PROJECT_DIR/build-release/.tools"
    _pf_bin="$_pf_dir/patchelf"
    if [ ! -x "$_pf_bin" ]; then
        mkdir -p "$_pf_dir"
        _pf_url="https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-x86_64.tar.gz"
        say ">> patchelf not found; fetching a static build"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$_pf_dir/patchelf.tar.gz" "$_pf_url" 2>/dev/null || true
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$_pf_dir/patchelf.tar.gz" "$_pf_url" 2>/dev/null || true
        fi
        if [ -s "$_pf_dir/patchelf.tar.gz" ] &&
           tar -xzf "$_pf_dir/patchelf.tar.gz" -C "$_pf_dir" 2>/dev/null &&
           [ -x "$_pf_dir/bin/patchelf" ]; then
            mv "$_pf_dir/bin/patchelf" "$_pf_bin"
            rm -rf "$_pf_dir/bin" "$_pf_dir/share" "$_pf_dir/patchelf.tar.gz"
        fi
    fi
    [ -x "$_pf_bin" ] && CANOPY_PATCHELF="$_pf_bin"
fi

if [ -n "$CANOPY_PATCHELF" ] && [ -x "$CANOPY_PATCHELF" ]; then
    for _target in "$STAGE/bin/canopy" "$STAGE/compositor/canopywc"; do
        [ -x "$_target" ] || continue
        "$CANOPY_PATCHELF" --set-rpath '$ORIGIN/../lib' "$_target" 2>/dev/null || true
    done
    # Libraries load each other; each needs $ORIGIN to look in the bundle first.
    _rpath_fail=0
    for _lib in "$STAGE/lib"/*.so*; do
        [ -f "$_lib" ] || continue
        [ -L "$_lib" ] && continue
        "$CANOPY_PATCHELF" --set-rpath '$ORIGIN' "$_lib" 2>/dev/null || _rpath_fail=$((_rpath_fail + 1))
    done
    if [ "$_rpath_fail" -gt 0 ]; then
        say "   warning: could not set RUNPATH on $_rpath_fail bundled libraries" >&2
    fi
else
    say "   WARNING: no patchelf available, so the bundled libraries will not" >&2
    say "            find each other. The payload will work only on a machine" >&2
    say "            whose system libraries match the build host." >&2
    say "            Install patchelf or set CANOPY_PATCHELF=/path/to/patchelf." >&2
fi

# The login greeter is part of the desktop, so it ships in the same payload when
# it has been built. `install.sh --with-greeter` picks it up from greeter/build.
GREETER_BUILD="${CANOPY_GREETER_BUILD:-$PROJECT_DIR/greeter/build}"
if [ -x "$GREETER_BUILD/canopy-greeter" ]; then
    say ">> including Canopy Greeter"
    mkdir -p "$STAGE/greeter/build"
    for b in canopy-greeter canopy-greeter-compositor canopy-greeter-apply-appearance; do
        [ -x "$GREETER_BUILD/$b" ] && cp "$GREETER_BUILD/$b" "$STAGE/greeter/build/$b"
    done
    mkdir -p "$STAGE/greeter/scripts" "$STAGE/greeter/assets"
    cp "$PROJECT_DIR/greeter/scripts/canopy-greeter-session" "$STAGE/greeter/scripts/" 2>/dev/null || true
    cp -a "$PROJECT_DIR"/greeter/assets/. "$STAGE/greeter/assets/" 2>/dev/null || true
fi

# The payload keeps bin/canopy in place: the binary's RUNPATH is $ORIGIN/../lib,
# which only resolves to the bundled lib/ from inside bin/. Flattening it to the
# root made the loader look one directory too high and fall back to system
# libraries, which is exactly what the bundle exists to avoid.
ln -sf bin/canopy "$STAGE/canopy" 2>/dev/null || true

# ---- Header --------------------------------------------------------------
cat > "$OUT" <<'HEADER'
#!/bin/sh
# =====================================================================
#  Canopy - the Xytro Labs desktop environment
#
#  One file containing the whole desktop: the shell, its assets, the
#  Labwc session configuration, the desktop portal setup and the
#  install / update / uninstall scripts.
#
#    sh canopy-*.run           install for the current user
#    sudo sh canopy-*.run      install system-wide, register the session
# =====================================================================
set -e

PAYLOAD_LINE=$(awk '/^__CANOPY_PAYLOAD_BELOW__$/ { print NR + 1; exit 0; }' "$0")
WORKDIR="${TMPDIR:-/tmp}/canopy-install-$$"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

echo ">> extracting Canopy..."
tail -n +"$PAYLOAD_LINE" "$0" | tar -xzf - -C "$WORKDIR"

# install.sh locates the binaries through CANOPY_BUILD_DIR and expects them at the root of
# that directory, while the payload stages them under bin/ and compositor/. Copy (not
# symlink) so the layout survives the system install's relocation to /usr/local/share.
#
# The staged tree also carries $STAGE/canopy as a symlink to bin/canopy, so that a
# directly-executed payload still finds its RUNPATH ($ORIGIN/../lib). After extraction
# that symlink is present, and copying bin/canopy onto it is copying a file onto itself:
# cp aborts with "are the same file" and the install stops. Materialise the real file by
# resolving the link first, and leave an already-correct layout alone.
materialise_root_binary() {
    _src="$1"
    _dst="$2"
    [ -x "$_src" ] || return 0
    if [ -e "$_dst" ] && [ "$_src" -ef "$_dst" ]; then
        # Already the same inode through the symlink. Replace the link with a real
        # copy so relocation to /usr/local/share cannot leave a dangling target.
        rm -f "$_dst" || return 1
    fi
    cp -f "$_src" "$_dst"
}

materialise_root_binary "$WORKDIR/bin/canopy" "$WORKDIR/canopy" || {
    echo "error: could not place the canopy binary at the payload root." >&2
    exit 1
}
if [ ! -x "$WORKDIR/canopywc" ]; then
    materialise_root_binary "$WORKDIR/compositor/canopywc" "$WORKDIR/canopywc" || {
        echo "error: could not place the compositor at the payload root." >&2
        exit 1
    }
fi

# Fail loudly and specifically if the payload is malformed, rather than letting a
# generic error from a deeper script appear after a successful checksum. Test for a
# regular file, not merely something executable: a dangling symlink must not pass.
if [ ! -f "$WORKDIR/canopy" ] || [ -L "$WORKDIR/canopy" ]; then
    echo "error: this payload has no canopy binary; it is not a complete Canopy release." >&2
    exit 1
fi

# The payload is laid out like a source tree, which is what install.sh expects.
if [ "$(id -u)" -eq 0 ]; then
    DEST=/usr/local/share/canopy-src
    mkdir -p "$DEST"
    cp -a "$WORKDIR"/. "$DEST"/
    CANOPY_BUILD_DIR="$DEST" sh "$DEST/scripts/install.sh"
    # The shell runs from the user's own session, so a system install also
    # refreshes that user's copy of the configuration and helpers.
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
            echo ">> refreshing $SUDO_USER's Canopy configuration"
            su "$SUDO_USER" -s /bin/sh -c \
                "HOME='$USER_HOME' CANOPY_BUILD_DIR='$DEST' sh '$DEST/scripts/install.sh'" || true
        fi
    fi
    rm -rf "$DEST"
    echo
    echo ">> Canopy installed system-wide."
    echo "   Log out and pick \"Canopy\" in your display manager,"
    echo "   or start it from a TTY with:  canopy-session"
else
    CANOPY_BUILD_DIR="$WORKDIR" sh "$WORKDIR/scripts/install.sh"
    echo
    echo ">> Canopy installed for $(id -un)."
fi

echo
echo "## helpers"
echo "  canopy-update check          # is there a newer release?"
echo "  canopy-session               # start the desktop"
echo "  sh scripts/uninstall.sh      # remove it again"

# Runtime dependencies come from the distribution's own package manager, so this
# is one command rather than a "now go install these 20 packages" list. It only
# runs when something is actually missing, and stops at the first failure rather
# than leaving a half-working desktop.
if [ "${CANOPY_SKIP_DEPS:-0}" != "1" ] && [ -x "$WORKDIR/scripts/deps.sh" ]; then
    echo ""
    echo ">> checking runtime dependencies"
    # deps.sh plan always exits 0 (it is a report), so look at what it says rather than
    # at the status. "missing      : nothing on this machine" is the satisfied case.
    _deps_report="$(sh "$WORKDIR/scripts/deps.sh" plan 2>/dev/null || true)"
    if printf '%s\n' "$_deps_report" | grep -q 'missing      : nothing on this machine'; then
        echo "   all runtime pieces present"
    else
        echo "   some runtime pieces are missing."
        _missing_list="$(printf '%s\n' "$_deps_report" | awk '/^missing      :/ { sub(/^[^:]*: */, ""); print }')"
        [ -n "$_missing_list" ] && echo "   missing:$_missing_list"
        if [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
            printf '   install them now with the system package manager? [Y/n] '
            read -r _answer </dev/tty 2>/dev/null || _answer=y
            case "${_answer:-y}" in
                [Nn]*) echo "   skipped: run 'sh scripts/deps.sh install' yourself." ;;
                *)     sh "$WORKDIR/scripts/deps.sh" install || {
                           echo "error: dependency install failed; fix the packages above and re-run." >&2
                           exit 1
                       } ;;
            esac
        else
            echo "   install them with: sh scripts/deps.sh install"
        fi
    fi
fi

_missing_deps=""
command -v canopywc >/dev/null 2>&1 || _missing_deps="$_missing_deps canopywc"
command -v xdg-desktop-portal >/dev/null 2>&1 || _missing_deps="$_missing_deps xdg-desktop-portal"
if [ -n "$_missing_deps" ]; then
    echo ""
    echo "missing runtime pieces:$_missing_deps"
    echo "  sh scripts/deps.sh install   # install them now"
fi
echo ""
echo "Done."
exit 0
__CANOPY_PAYLOAD_BELOW__
HEADER

tar -czf - -C "$STAGE" . >> "$OUT"
chmod +x "$OUT"

say "built: $OUT ($(du -h "$OUT" | cut -f1))"