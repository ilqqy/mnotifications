{
  description = "mnotifications - macOS-style notification banners for Wayland, written in Quickshell";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: let
      mnotifications = pkgs.callPackage ./nix/package.nix {};
    in {
      default = mnotifications;
      inherit mnotifications;
    });

    apps = forAllSystems (pkgs: {
      default = {
        type = "app";
        program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/mnotifications";
        meta.description = "Run the mnotifications daemon";
      };
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        # `nix develop` then `qs -p .` runs the daemon straight from the
        # checkout. tests/isolated.sh needs libnotify, grim and dbus.
        packages = [
          pkgs.quickshell
          pkgs.qt6.qtdeclarative # qmllint, qmlformat, qmlls
          pkgs.libnotify
          pkgs.grim
          pkgs.dbus
          pkgs.alejandra
          pkgs.shellcheck
        ];

        shellHook = ''
          export QML_IMPORT_PATH="${pkgs.quickshell}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
          export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
        '';
      };
    });

    formatter = forAllSystems (pkgs: pkgs.alejandra);

    homeManagerModules.default = import ./nix/hm-module.nix self;
    homeManagerModules.mnotifications = self.homeManagerModules.default;

    nixosModules.default = import ./nix/nixos-module.nix self;
    nixosModules.mnotifications = self.nixosModules.default;
  };
}
