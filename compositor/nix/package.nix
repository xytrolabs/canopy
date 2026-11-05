{
  lib,
  stdenv,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  wlroots_0_20,
  libxkbcommon,
  libinput,
  libei,
  systemd,
  pixman,
  cairo,
  pango,
  libGL,
  libdrm,
  libdisplay-info,
  libgbm,
  libxcb,
  libxcb-wm,
  lcms2,
  jemalloc,
  tomlplusplus,
  nlohmann_json,
  xwayland,
  makeBinaryWrapper,
  rev ? "unknown",
}:
let
  version = lib.trim (builtins.readFile ../VERSION);
in
stdenv.mkDerivation {
  pname = "canopy";
  inherit version;

  src = ../.;

  nativeBuildInputs = [
    makeBinaryWrapper
    meson
    ninja
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    wayland
    wayland-protocols
    wlroots_0_20
    libxkbcommon
    libinput
    libei
    # Supplies libudev for the optional native DRM policy support and sd-bus for the systemd-localed keymap.
    systemd
    pixman
    tomlplusplus
    libGL
    nlohmann_json
    libdrm
    libdisplay-info
    libgbm
    libxcb # Includes xcb-randr; development files are selected automatically for builds.
    libxcb-wm
    lcms2
    jemalloc
    cairo
    pango
  ];

  mesonBuildType = "release";

  mesonFlags = [ (lib.mesonEnable "tests" false) ];

  postPatch = ''
    substituteInPlace meson.build \
      --replace-fail "canopy_git_revision_config.set('VCS_TAG', 'unknown')" "canopy_git_revision_config.set('VCS_TAG', '${rev}')"
  '';

  postInstall = ''
    if [ -f "$out/share/wayland-sessions/canopy.desktop" ]; then
      substituteInPlace "$out/share/wayland-sessions/canopy.desktop" \
        --replace-fail 'Exec=start-canopy' "Exec=$out/bin/start-canopy"
    fi
    wrapProgram $out/bin/canopy \
      --prefix PATH : ${lib.makeBinPath [ xwayland ]} \
  '';

  passthru.providedSessions = [ "canopy" ];

  meta = with lib; {
    description = "A Wayland compositor built on wlroots";
    homepage = "https://github.com/xytrolabs/canopy";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "canopy";
  };
}
