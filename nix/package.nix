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
    # GTK icon theme unless QS_ICON_THEME is already set, switched to its
    # light or dark sibling to match the banners (see below).
    text = ''
      config_home=''${XDG_CONFIG_HOME:-$HOME/.config}

      # Light or dark, resolved as Config.qml does: the user's config.json,
      # then the system one, then dark. Read once, at launch.
      mode=dark
      for config in "''${MNOTIFICATIONS_CONFIG:-$config_home/mnotifications/config.json}" /etc/xdg/mnotifications/config.json; do
      	[ -r "$config" ] || continue
      	content=$(<"$config")
      	if [[ $content =~ \"mode\"[[:space:]]*:[[:space:]]*\"light\" ]]; then
      		mode=light
      		break
      	fi
      	[[ $content =~ \"mode\"[[:space:]]*: ]] && break
      done

      if [ -z "''${QS_ICON_THEME:-}" ]; then
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

      	# The symbolic icons of a dark theme are near-white and vanish on light
      	# banners, and the reverse. Use the installed sibling that matches the
      	# mode: Papirus on light, Papirus-Dark on dark (likewise breeze and
      	# breeze-dark). A theme without such a sibling is used as it is.
      	if [ -n "''${QS_ICON_THEME:-}" ]; then
      		case $QS_ICON_THEME in
      		*-[Dd]ark | *-[Ll]ight) base=''${QS_ICON_THEME%-*} ;;
      		*) base=$QS_ICON_THEME ;;
      		esac
      		if [ "$mode" = light ]; then
      			candidates=("$base" "$base-Light" "$base-light")
      		else
      			candidates=("$base-Dark" "$base-dark" "$base")
      		fi
      		IFS=: read -ra data_dirs <<<"''${XDG_DATA_HOME:-$HOME/.local/share}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
      		icon_dirs=("$HOME/.icons")
      		for dir in "''${data_dirs[@]}"; do icon_dirs+=("$dir/icons"); done
      		for candidate in "''${candidates[@]}"; do
      			for dir in "''${icon_dirs[@]}"; do
      				if [ -r "$dir/$candidate/index.theme" ]; then
      					export QS_ICON_THEME=$candidate
      					break 2
      				fi
      			done
      		done
      	fi
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
