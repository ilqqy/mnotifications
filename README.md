# mnotifications

A notification daemon for Wayland that shows macOS-style banners. It is a
Quickshell configuration: Quickshell's `NotificationServer` owns
`org.freedesktop.Notifications` on the session bus, and the banners are drawn
in a layer-shell surface with the namespace `notif-macos`.

- Rounded, translucent cards (20 px radius) stacked in a screen corner, newest
  nearest the edge. The frosted look comes from a Hyprland layer rule (below).
- App icon on the left, bold title, body, relative timestamp ("now", "5m ago").
  Critical notifications get a small "TIME SENSITIVE" label above the title.
- Hovering a banner shows a close button on its top-left corner and, when the
  notification has actions, an "Options" pill that opens a dropdown of them.
- Banners slide in from the screen edge and fade in, leave the same way in
  reverse, and the stack glides to close gaps.

Tested with Quickshell 0.3.2 and Hyprland 0.56.2 (Lua configuration) from
nixpkgs revision 55bfb4d.

## Behaviour

- **Stack.** At most 4 banners (`maxVisible`) are on screen; further
  notifications wait in a queue and appear as slots free up, oldest first,
  except that critical ones are queued ahead of all others. In a burst,
  banners appear one every 70 ms.
- **Timeouts.** Low urgency: 4 s. Normal: 6 s. Critical: never. An app's
  `expire_timeout` between 1.5 s and 120 s is used instead; `0` keeps the banner
  until it is closed; any other value falls back to the urgency default.
- **Hover** pauses the countdown. When the pointer leaves, the banner gets the
  time it had left, but at least 1.5 s. An open Options menu also pauses it.
- **Click** on a banner invokes its `default` action; without one, the click
  dismisses it. Other actions are in the Options menu. The menu closes on a
  click outside it (through `HyprlandFocusGrab`).
- **Replace.** A notification sent with `replaces_id` updates its banner in
  place, without a new entrance, and restarts its countdown and timestamp.
- **Icons**, first that resolves: the `image-data` / `image-path` hint, the
  `app_icon`, the icon of the sender's desktop entry, `dialog-information` from
  the icon theme, then a tile with the app's initial. Pictures from
  `image-data` are cropped to a square and given rounded corners by a shader
  effect (the rounding itself has not yet been seen in a test run on a real
  compositor).
- **Body markup.** `<b>`, `<i>`, `<u>` and `<a href>` (http, https and mailto
  only) are kept. `<img>` is replaced by its `alt` text; `<br>` and newlines
  break lines; `<script>` and `<style>` are dropped with their content; other
  HTML tags are removed and their text kept; everything else is escaped. The
  body is rebuilt from scratch before it reaches Qt's `StyledText`, so no tag
  or attribute from the sender is passed through. Links open with
  `Qt.openUrlExternally`.
- **Capabilities** advertised to clients: `body`, `body-markup`,
  `body-hyperlinks`, `actions`, `icon-static`. `GetServerInformation` reports
  the name `quickshell` (set by Quickshell).

## Install

The flake exposes `packages.<system>.default` (also `mnotifications`), a
`homeManagerModules.default` and a `nixosModules.default` (also available as
`.mnotifications`). The package's `mnotifications` command starts the daemon.

```nix
# flake.nix
inputs.mnotifications = {
  url = "git+file:///home/ilyanix/mNotifications";  # no remote yet
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Home Manager:

```nix
{ inputs, ... }: {
  imports = [ inputs.mnotifications.homeManagerModules.default ];

  programs.mnotifications = {
    enable = true;
    position = "top-right";
    timeouts.normal = 8000;
  };
}
```

NixOS: the same, with `inputs.mnotifications.nixosModules.default`.

The Home Manager module writes `$XDG_CONFIG_HOME/mnotifications/config.json`,
the NixOS module `/etc/xdg/mnotifications/config.json`; both install the
package. Neither starts the daemon: there is no systemd unit and no D-Bus
activation file, so installing it does not take the bus name from another
daemon. See [Starting it](#starting-it).

### Options

All under `programs.mnotifications`. `null` means "use the built-in default";
null options are left out of `config.json`.

| Option | Type | Default |
| --- | --- | --- |
| `enable` | bool | `false` |
| `package` | package | this flake's package |
| `font` | null or string | `null`: Inter |
| `maxVisible` | null or positive int | `null`: 4 |
| `position` | null or `"top-right"`, `"top-left"`, `"bottom-right"`, `"bottom-left"` | `null`: top-right |
| `output` | null or string, a monitor name as in `hyprctl monitors` | `null`: the first monitor |
| `mode` | null or `"dark"`, `"light"` | `null`: dark |
| `accent` | null or `"#rrggbb"`: the highlighted menu row and links | `null`: `#0a84ff` dark, `#007aff` light |
| `timeouts.low` | null or ms, `0` = until closed | `null`: 4000 |
| `timeouts.normal` | null or ms, `0` = until closed | `null`: 6000 |

### config.json

Without Nix, write the same keys yourself:

```json
{"mode": "light", "maxVisible": 3, "position": "top-right", "timeouts": {"low": 3000}}
```

Keys are merged one by one: the user file
(`$XDG_CONFIG_HOME/mnotifications/config.json`, or the path in
`$MNOTIFICATIONS_CONFIG`) over `/etc/xdg/mnotifications/config.json` over the
defaults. Both files are watched: edits restyle running banners without a
restart, except the icon theme (see [Theming](#theming)).

## Hyprland layer rule

For the frosted glass, add to the Hyprland 0.55+ Lua configuration:

```lua
hl.layer_rule({
  match = { namespace = "notif-macos" },
  blur = true,
  ignore_alpha = 0.2,
  no_anim = true,
})
```

- `blur` blurs what is behind the banners.
- `ignore_alpha = 0.2` limits the blur to the banners themselves. The surface
  is a transparent column along the screen edge; the card fill is at alpha 0.62
  (dark) or 0.70 (light), the menu at 0.80 and the close button at 0.92, all
  blurred, while the drop shadows stay at 0.12 or less and are not.
- `no_anim` turns off Hyprland's layer animation; the daemon animates its own
  banners.

Verified on Hyprland 0.56.2: `Hyprland --verify-config` accepts the rule, and
`tests/isolated.sh` applies it with `hyprctl eval` to a nested instance, where
the banners are blurred. The older hyprlang `layerrule` syntax was not tested.

## Starting it

Start `mnotifications` with the session, for example from the Hyprland Lua
config. This is the form used by Hyprland 0.56.2's built-in example config;
`--verify-config` accepts it, but it checks the callback body only when it
runs:

```lua
hl.on("hyprland.start", function ()
  hl.exec_cmd("mnotifications")
end)
```

### Switching from another daemon

Only one process at a time owns `org.freedesktop.Notifications`. These steps
are instructions; none of them were run against a live session.

1. Find what owns the name now:
   `busctl --user status org.freedesktop.Notifications` prints its PID and
   command line. Another Quickshell-based daemon also reports the name
   `quickshell` in `GetServerInformation`, so go by the command line.
2. Stop that daemon from starting: remove its autostart line, or disable its
   systemd user unit (`systemctl --user disable --now <unit>`), or turn off its
   Home Manager service (for example `services.mako.enable = false`).
3. Add the autostart above, then stop the old daemon and start
   `mnotifications` (or log in again).
4. Check with `busctl --user status org.freedesktop.Notifications` that the
   command line now contains `mnotifications`, then send `notify-send hello`.

If `mnotifications` starts while another daemon still holds the name, it logs
`Could not register notification server ... Registration will be attempted
again if the active service is unregistered`, shows nothing, and takes the
name once the other daemon exits. This was observed with two instances on a
private bus: after the first one was stopped, the second one received the next
notification.

## Theming

`Theme.qml` holds every colour, size, radius, duration and the defaults above;
the components read nothing else. `mode` and `accent` are the switches exposed
as options; for anything more, edit `Theme.qml` (white or black text at fixed
alphas, the glass fills, radii, spacing, durations, easing curves). Fill alphas
must stay above the layer rule's `ignore_alpha` and the shadow alpha below it.

**Font.** Inter, which the package ships: the wrapper points `FONTCONFIG_FILE`
at a file that includes `/etc/fonts/fonts.conf` and adds Inter, so the rest of
the system's fonts stay available for fallback. A `FONTCONFIG_FILE` you set
yourself is left alone; Inter then has to be installed. `font` picks another
family.

**Icon theme.** Qt reads an icon theme only from qt6ct or KDE settings, so the
wrapper takes `gtk-icon-theme-name` from `gtk-3.0/settings.ini` (or
`gtk-4.0`). It then switches to the installed light or dark sibling of that
theme to match `mode`: Papirus for light banners, Papirus-Dark for dark ones
(likewise `breeze` and `breeze-dark`); a theme without such a sibling is used
as it is. The mode is read once, at launch: after changing `mode`, restart the
daemon to get the matching icons. Set `QS_ICON_THEME` to choose a theme
yourself; the wrapper then changes nothing. The daemon logs the theme in use
at startup (`started, icon theme ...`).

## Development and tests

```sh
nix develop                     # quickshell, notify-send, grim, wlrctl, jq, ...
tests/markup.sh                 # sanitizer and timestamp cases, headless
tests/render.sh [scenario...]   # offscreen: real Store/stack on a private bus
tests/isolated.sh               # nested Hyprland, real input, screenshots
```

- `markup.sh` runs the sanitizer cases in a Quickshell instance with no
  window.
- `render.sh` runs the real `Store`, `BannerStack` and `Banner` in an offscreen
  window on a private bus (`dbus-run-session`), sends notifications with
  `notify-send` and `busctl`, calls what a click would call, checks the state
  and saves screenshots to `tests/out/render-*`. Scenarios: capabilities,
  timeouts, reference, actions, icons, long, burst, replace, restart,
  positions. The offscreen platform uses Qt's software renderer, which draws
  no shader effects: its screenshots have no shadows and square image-data
  pictures, and no blur.
- `isolated.sh` refuses to start while the session has a fullscreen window. It
  starts a nested Hyprland (a window on the current session) whose config is a
  single exit bind (Ctrl+Alt+Shift+Q), with its own runtime directory, so its
  socket and instance signature cannot be confused with the session's. It adds
  the layer rule and a fixed-size headless output with `hyprctl eval`, runs the
  packaged daemon on that output on a private bus, and drives it with a
  virtual pointer (`wlrctl`). Results and screenshots go to
  `tests/out/isolated-*`. It stops only processes it started and deletes its
  `/tmp` directory. `MNOTIF_ISOLATED_HOLD=<seconds>` keeps the session up for
  manual testing instead of running the scenarios.

To run from the checkout, `qs -p .` inside `nix develop`. Run it under
`dbus-run-session` (for example `dbus-run-session -- qs -p .`) to keep it off
the session bus, where it would otherwise wait for, or take, the name of the
running daemon. `MNOTIFICATIONS_DEBUG=1` adds layout geometry, hover and menu
events to the log. The log never contains a notification's summary or body.

`nix develop` leaves an empty `/tmp/nix-shell.*` directory behind per
invocation; that is Nix's behaviour, not the tests'.

## Known limitations

- One output: banners appear on the `output` monitor or the first one, not on
  the focused one.
- No notification history or centre, do-not-disturb, sounds, inline replies,
  action icons or progress bars (the `value` hint is ignored).
- No keyboard interaction.
- The Options pill appears only on hover, but its column is reserved whenever a
  notification has actions, so that text never reflows on hover; such bodies
  wrap narrower.
- Hyprland blurs per pixel, where the surface alpha exceeds `ignore_alpha`; a
  fading banner gets its blur when it crosses that threshold rather than
  fading it in.
- Shadows and the rounded corners of image-data pictures are shader effects;
  with Qt's software renderer the shadows are missing and the pictures stay
  square.
- The icon theme follows `mode` only at launch.
- Clicks in the 8 px gaps between banners land on the daemon's surface, not on
  the window below.
- The surface is on the overlay layer; behaviour over fullscreen windows was
  not tested.
- Clicking a link was not exercised by the tests.
- `resident` and `transient` hints were not tested. Invoking an action of a
  non-resident notification closes it (Quickshell does this).
