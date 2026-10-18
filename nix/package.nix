{
  lib,
  stdenvNoCC,
  writeShellApplication,
  writeText,
  quickshell,
  inter,
}: let
  # QML is interpreted: the "build" is a copy of the sources into the store.
  qmlSource = stdenvNoCC.mkDerivation {
    pname = "mnotifications-qml";
    version = "0.1.0";

    src = lib.fileset.toSource {
      root = ../.;
      fileset =
        lib.fileset.difference
        (lib.fileset.fileFilter
          (file: file.hasExt "qml" || file.hasExt "js" || file.name == "qmldir")
          ../.)
        (lib.fileset.maybeMissing ../tests);
    };

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/mnotifications"
      cp -r ./. "$out/share/mnotifications/"
      runHook postInstall
    '';
  };

  # The system configuration plus Inter, so the banners get their font
  # whether or not Inter is installed. Including fonts.conf keeps every other
  # installed font available for fallback glyphs (emoji, CJK).
  fontsConf = writeText "mnotifications-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
      <dir>${inter}/share/fonts</dir>
    </fontconfig>
  '';
in
  writeShellApplication {
    name = "mnotifications";

    runtimeInputs = [quickshell];

    # Qt reads an icon theme only from qt6ct/KDE settings; without one it
    # resolves against hicolor alone, which has no generic icons. Follow the
    # GTK icon theme unless QS_ICON_THEME is already set.
    text = ''
      if [ -z "''${QS_ICON_THEME:-}" ]; then
      	config_home=''${XDG_CONFIG_HOME:-$HOME/.config}
      	for gtk_settings in "$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"; do
      		[ -r "$gtk_settings" ] || continue
      		while IFS='=' read -r key value; do
      			key=''${key//[[:space:]]/}
      			[ "$key" = gtk-icon-theme-name ] || continue
      			value=''${value#"''${value%%[![:space:]]*}"}
      			value=''${value%"''${value##*[![:space:]]}"}
      			if [ -n "$value" ]; then export QS_ICON_THEME=$value; fi
      			break
      		done <"$gtk_settings"
      		[ -n "''${QS_ICON_THEME:-}" ] && break
      	done
      fi

      # A FONTCONFIG_FILE set by the user wins; Inter is then their concern.
      export FONTCONFIG_FILE=''${FONTCONFIG_FILE:-${fontsConf}}

      exec quickshell --path ${qmlSource}/share/mnotifications "$@"
    '';

    meta = {
      description = "macOS-style notification banners for Wayland, written in Quickshell";
      platforms = lib.platforms.linux;
      mainProgram = "mnotifications";
    };
  }
