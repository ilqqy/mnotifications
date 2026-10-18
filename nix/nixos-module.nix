# NixOS module. Installs the package and writes
# /etc/xdg/mnotifications/config.json, which a per-user config.json
# overrides key by key. It does not start the daemon.
self: {
  config,
  lib,
  pkgs,
  ...
}: let
  options = import ./options.nix {inherit lib;};
  cfg = config.programs.mnotifications;
in {
  options.programs.mnotifications = options.mkOptions {
    defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
    environment.etc."xdg/mnotifications/config.json".text = options.mkConfigJson cfg;
  };
}
