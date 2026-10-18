# home-manager module. Installs the package and writes
# $XDG_CONFIG_HOME/mnotifications/config.json. It does not start the daemon.
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
    home.packages = [cfg.package];
    xdg.configFile."mnotifications/config.json".text = options.mkConfigJson cfg;
  };
}
