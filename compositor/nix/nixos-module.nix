{ xdg-desktop-portal-canopy }:
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  cfg = config.programs.canopy;
in
{
  # Disable the nixpkgs module to avoid conflicts
  disabledModules = [ "programs/wayland/canopy.nix" ];

  options.programs.canopy = {
    enable = lib.mkEnableOption "Canopy, a Wayland compositor built on wlroots.";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The canopy package to install.";
    };

    portalPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = xdg-desktop-portal-canopy.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "the xdg-desktop-portal-canopy flake's package";
      description = ''
        The xdg-desktop-portal-canopy package to install.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        hardware.graphics.enable = lib.mkDefault true;

        assertions = [
          {
            assertion = cfg.package != null;
            message = "programs.canopy.package cannot be null when programs.canopy.enable is true";
          }
        ];
      }

      (lib.mkIf (cfg.package != null) {
        environment.systemPackages = [
          cfg.package
          # So `just debug` / meson outside `nix develop` can find headers via pkg-config.
          pkgs.tomlplusplus
        ];
        environment.pathsToLink = [ "/share/canopy/effects" ];

        # Required for greetd / noctalia-greeter to discover the session (Name=Canopy).
        # Plain systemPackages .desktop files are not enough; NixOS aggregates via this.
        services.displayManager.sessionPackages = [ cfg.package ];

        systemd.packages = [ cfg.package ];
        systemd.user.services.canopy = {
          restartIfChanged = false;
          enableDefaultPath = false;
        };
      })

      (lib.mkIf (cfg.portalPackage != null) {
        xdg.portal = {
          enable = lib.mkDefault true;
          extraPortals = [ cfg.portalPackage ];
          config.canopy.default = lib.mkDefault [
            "canopy"
            "gtk"
          ];
        };
      })

      (import "${modulesPath}/programs/wayland/wayland-session.nix" {
        inherit lib pkgs;
        enableXWayland = false;
        enableWlrPortal = false;
      })
    ]
  );
}
