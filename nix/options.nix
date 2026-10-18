# Shared by the home-manager and NixOS modules. The two differ only in where
# config.json is written; Config.qml reads both locations.
{lib}: let
  inherit (lib) mkOption mkEnableOption types literalExpression;
in {
  mkOptions = {defaultPackage}: {
    enable = mkEnableOption "mnotifications, macOS-style notification banners";

    package = mkOption {
      type = types.package;
      default = defaultPackage;
      defaultText = literalExpression "mnotifications.packages.\${pkgs.system}.default";
      description = "The mnotifications package to use.";
    };

    font = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Font family for the banners. Null uses Inter, which the package ships.";
      example = "SF Pro Text";
    };

    maxVisible = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "Banners shown at once; further notifications wait in a queue. Null uses the theme default (4).";
    };

    position = mkOption {
      type = types.nullOr (types.enum ["top-right" "top-left" "bottom-right" "bottom-left"]);
      default = null;
      description = "Screen corner the stack grows from. Null uses top-right.";
    };

    output = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of the monitor to show banners on, as listed by `hyprctl monitors`. Null uses the first monitor.";
      example = "DP-1";
    };

    mode = mkOption {
      type = types.nullOr (types.enum ["dark" "light"]);
      default = null;
      description = "Light or dark banners. Null uses dark.";
    };

    accent = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Accent colour (`#rrggbb`) for the highlighted Options menu row. Null uses system blue.";
      example = "#ff9f0a";
    };

    timeouts = {
      low = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
        description = "Milliseconds before a low-urgency banner is dismissed; 0 keeps it until closed. Null uses 4000.";
      };

      normal = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
        description = "Milliseconds before a normal-urgency banner is dismissed; 0 keeps it until closed. Null uses 6000.";
      };
    };
  };

  # Nulls are dropped so unset options fall through to the QML defaults.
  mkConfigJson = cfg: let
    dropNulls = lib.filterAttrs (_: v: v != null);
  in
    builtins.toJSON (dropNulls {
      inherit (cfg) font maxVisible position output mode accent;
      timeouts = dropNulls {inherit (cfg.timeouts) low normal;};
    });
}
