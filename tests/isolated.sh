#!/usr/bin/env bash
# End-to-end test on a real compositor, isolated from the running session.
#
# A nested Hyprland is started as a window on the current Wayland session.
# Its config is a single exit bind (CTRL + ALT + SHIFT + Q). It gets its own
# XDG_RUNTIME_DIR under a fresh /tmp directory, so its Wayland socket and its
# instance signature live there: hyprctl, called only through nhyprctl()
# below with that runtime directory, cannot reach the session's Hyprland. The
# nested instance also gets throwaway XDG config/data/state/cache homes.
# The layer rule from the README is added to the nested instance at runtime
# with `hyprctl eval`.
#
# The daemon is the flake package, run inside the nested compositor on a
# private D-Bus bus (dbus-run-session), so a running notification daemon is
# never contacted. Pointer input comes from a virtual pointer (wlrctl) bound
# to the nested compositor only.
#
# Safety: the script refuses to start when the session has a fullscreen
# window; it signals only the PIDs it started itself; it deletes its /tmp
# directory on exit. Screenshots and logs are kept in tests/out/isolated-*.
#
# Usage: tests/isolated.sh   (inside `nix develop`; Hyprland from the system)
set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [ "${1:-}" != --inner ]; then
	for tool in Hyprland hyprctl wlrctl grim notify-send dbus-run-session busctl jq nix; do
		command -v "$tool" >/dev/null || {
			echo "isolated.sh: $tool not found; run inside nix develop" >&2
			exit 2
		}
	done

	runtime=${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}
	parent=${WAYLAND_DISPLAY:-}
	if [ -z "$parent" ]; then
		mapfile -t sockets < <(find "$runtime" -maxdepth 1 -type s -regex '.*/wayland-[0-9]+' -printf '%f\n')
		if [ "${#sockets[@]}" != 1 ]; then
			echo "isolated.sh: set WAYLAND_DISPLAY to the session's socket" >&2
			exit 2
		fi
		parent=${sockets[0]}
	fi
	case $parent in
	/*) parent_path=$parent ;;
	*) parent_path=$runtime/$parent ;;
	esac
	[ -S "$parent_path" ] || {
		echo "isolated.sh: no Wayland socket at $parent_path" >&2
		exit 2
	}

	# Read-only query of the session's window list (wlr-foreign-toplevel).
	# An impossible match must fail, or the answer means nothing.
	if WAYLAND_DISPLAY=$parent_path wlrctl toplevel find app_id:mnotifications-no-such-app; then
		echo "isolated.sh: cannot query the session's windows; not starting" >&2
		exit 3
	fi
	if WAYLAND_DISPLAY=$parent_path wlrctl toplevel find state:fullscreen; then
		echo "isolated.sh: a fullscreen window is open on this session; not starting the nested compositor" >&2
		exit 3
	fi

	pkg=$(nix build "$repo#default" --no-link --print-out-paths)

	work=$(mktemp -d /tmp/mnotif-isolated.XXXXXX)
	trap 'rm -rf -- "$work"' EXIT
	out=$repo/tests/out/isolated-$(date +%Y%m%d-%H%M%S)
	mkdir -p "$out"
	mkdir -m 700 "$work/run"
	mkdir -p "$work/xdg/config" "$work/xdg/data" "$work/xdg/state" "$work/xdg/cache"
	cat >"$work/hyprland.lua" <<'EOF'
-- Throwaway config for tests/isolated.sh: an exit bind and nothing else.
hl.bind("CTRL + ALT + SHIFT + Q", hl.dsp.exit())
EOF

	status=0
	env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD -u DISPLAY \
		dbus-run-session -- "$0" --inner "$work" "$out" "$parent_path" "$pkg" "${@}" || status=$?
	echo "screenshots and logs: $out"
	exit "$status"
fi

work=$2
out=$3
parent_path=$4
pkg=$5
export XDG_RUNTIME_DIR=$work/run

hypr_pid=
daemon_pid=
sig=
nested=

nhyprctl() {
	[ -n "$sig" ] && [ -S "$work/run/hypr/$sig/.socket.sock" ] || {
		echo "nhyprctl: nested instance socket missing" >&2
		return 1
	}
	XDG_RUNTIME_DIR=$work/run HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl "$@"
}

alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

stop_pid() {
	local pid=$1
	alive "$pid" || return 0
	kill "$pid" 2>/dev/null || true
	for _ in $(seq 50); do
		alive "$pid" || break
		sleep 0.1
	done
	alive "$pid" && kill -9 "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null || true
}

cleanup() {
	stop_pid "$daemon_pid"
	if alive "$hypr_pid"; then
		nhyprctl dispatch exit >/dev/null 2>&1 || true
		for _ in $(seq 30); do
			alive "$hypr_pid" || break
			sleep 0.1
		done
		stop_pid "$hypr_pid"
	fi
	cp "$work/daemon.log" "$out/daemon.log" 2>/dev/null || true
	cp "$work/hyprland.out" "$out/hyprland.out" 2>/dev/null || true
	cp "$work"/run/hypr/*/hyprland.log "$out/" 2>/dev/null || true
}
trap cleanup EXIT

echo "== nested Hyprland"
XDG_CONFIG_HOME=$work/xdg/config XDG_DATA_HOME=$work/xdg/data \
	XDG_STATE_HOME=$work/xdg/state XDG_CACHE_HOME=$work/xdg/cache \
	WAYLAND_DISPLAY=$parent_path HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 \
	HYPRLAND_NO_CRASHREPORTER=1 \
	Hyprland --config "$work/hyprland.lua" >"$work/hyprland.out" 2>&1 &
hypr_pid=$!

for _ in $(seq 200); do
	for dir in "$work"/run/hypr/*/; do
		[ -S "$dir.socket.sock" ] && sig=$(basename "$dir")
	done
	nested=$(find "$work/run" -maxdepth 1 -type s -regex '.*/wayland-[0-9]+' -printf '%f\n' | head -1)
	[ -n "$sig" ] && [ -n "$nested" ] && break
	alive "$hypr_pid" || {
		echo "nested Hyprland exited early" >&2
		tail -20 "$work/hyprland.out" >&2
		exit 1
	}
	sleep 0.1
done
[ -n "$sig" ] && [ -n "$nested" ] || {
	echo "nested Hyprland did not come up" >&2
	exit 1
}
for _ in $(seq 100); do
	[ "$(nhyprctl -j monitors 2>/dev/null | jq length 2>/dev/null || echo 0)" -ge 1 ] && break
	sleep 0.1
done
echo "instance $sig, socket $work/run/$nested (pid $hypr_pid)"

monitor=$(nhyprctl -j monitors | jq -c '.[0] | {name, x, y, width, height, scale}')
echo "monitor $monitor"
mon_w=$(jq -r '(.width / .scale) | floor' <<<"$monitor")
mon_h=$(jq -r '(.height / .scale) | floor' <<<"$monitor")

echo "layer rule: $(nhyprctl eval 'hl.layer_rule({ match = { namespace = "notif-macos" }, blur = true, ignore_alpha = 0.2, no_anim = true })' 2>&1)"

export MNOTIFICATIONS_CONFIG=$work/config.json
printf '{}\n' >"$MNOTIFICATIONS_CONFIG"
WAYLAND_DISPLAY=$nested HYPRLAND_INSTANCE_SIGNATURE=$sig QT_QPA_PLATFORM=wayland \
	MNOTIFICATIONS_DEBUG=1 "$pkg/bin/mnotifications" >"$work/daemon.log" 2>&1 &
daemon_pid=$!
for _ in $(seq 100); do
	busctl --user status org.freedesktop.Notifications >/dev/null 2>&1 && break
	sleep 0.1
done

# ----------------------------------------------------------------- helpers

failures=0
check() {
	local name=$1
	shift
	if "$@"; then
		echo "PASS $name"
	else
		echo "FAIL $name"
		failures=$((failures + 1))
	fi
}
equals() { [ "$1" = "$2" ]; }
logged() { grep -q -- "$1" "$work/daemon.log"; }
log_count() { grep -c -- "$1" "$work/daemon.log" || true; }
config() {
	printf '%s\n' "$1" >"$MNOTIFICATIONS_CONFIG"
	sleep 0.4
}

layer() {
	nhyprctl -j layers | jq -c '[.[] | .levels | to_entries[] | .key as $level | .value[]
		| select(.namespace == "notif-macos") | . + {level: $level}] | first'
}

# Latest layout line for a notification id: "x y w h" of the card and pill,
# in surface coordinates.
card_of() { grep "layout id=$1 " "$work/daemon.log" | tail -1 | sed 's/.* card=\([^ ]*\) .*/\1/' | tr , ' '; }
pill_of() { grep "layout id=$1 " "$work/daemon.log" | tail -1 | sed 's/.* pill=\([^ ]*\).*/\1/' | tr , ' '; }

surface_x=0
surface_y=0
# Global position of a point given in surface coordinates.
to_global() { awk -v x="$1" -v y="$2" -v sx="$surface_x" -v sy="$surface_y" 'BEGIN { printf "%d %d", sx + x, sy + y }'; }

cursor_to() {
	nhyprctl dispatch movecursor "$1" "$2" >/dev/null
	sleep 0.15
}
click() { WAYLAND_DISPLAY=$nested wlrctl pointer click left; }
click_at() {
	cursor_to "$1" "$2"
	click
}
card_center() {
	read -r x y w h <<<"$(card_of "$1")"
	to_global "$(awk -v x="$x" -v w="$w" 'BEGIN { print x + w / 2 }')" "$(awk -v y="$y" -v h="$h" 'BEGIN { print y + h / 2 }')"
}
pill_center() {
	read -r x y w h <<<"$(pill_of "$1")"
	to_global "$(awk -v x="$x" -v w="$w" 'BEGIN { print x + w / 2 }')" "$(awk -v y="$y" -v h="$h" 'BEGIN { print y + h / 2 }')"
}
close_center() {
	read -r x y _ _ <<<"$(card_of "$1")"
	to_global "$((${x%.*} + 5))" "$((${y%.*} + 5))"
}
# "x y" strings from the *_center helpers.
hover_on() {
	local x y
	read -r x y <<<"$1"
	cursor_to "$x" "$y"
}
click_on() {
	local x y
	read -r x y <<<"$1"
	click_at "$x" "$y"
}
# Centre of row <n> (from 0) of the menu hanging below banner <id>.
menu_row() {
	local x y w h
	read -r x y w h <<<"$(card_of "$1")"
	awk -v sx="$surface_x" -v sy="$surface_y" -v x="$x" -v y="$y" -v w="$w" -v h="$h" -v n="$2" \
		'BEGIN { printf "%d %d", sx + x + w + 10 - 60, sy + y + h - 6 + 5 + 26 * n + 13 }'
}
away() { cursor_to 40 "$((mon_h - 40))"; }

shot() { WAYLAND_DISPLAY=$nested grim "$out/$1-full.png"; }
# The top-right corner where the stack lives, like the reference crop.
crop() { WAYLAND_DISPLAY=$nested grim -g "$((mon_w - 520)),0 520 ${2:-460}" "$out/$1.png"; }

id_of_log() { grep "notify id=" "$work/daemon.log" | tail -1 | sed 's/.*notify id=\([0-9]*\).*/\1/'; }

# ---------------------------------------------------------------- scenarios

echo "== layer surface"
notify-send "Hello" "first banner maps the surface"
sleep 1
info=$(layer)
echo "layer $info"
check "layer surface with namespace notif-macos exists" test -n "$info"
check "it is on the overlay layer" equals "$(jq -r .level <<<"$info")" 3
surface_x=$(jq -r .x <<<"$info")
surface_y=$(jq -r .y <<<"$info")
check "it hugs the right edge" equals "$(jq -r '.x + .w' <<<"$info")" "$mon_w"
check "it is 404 px wide (card 360 + margins)" equals "$(jq -r .w <<<"$info")" 404
first=$(id_of_log)
click_on "$(card_center "$first")"
sleep 0.5
check "click on a banner without actions dismisses it" logged "closed id=$first reason=Dismissed"

echo "== reference look, dark"
notify-send -u critical -a Reminders -i x-office-calendar -A default=Open -A done="Mark as Completed" \
	-A hour="Remind Me in an Hour" -A afternoon="Remind Me This Afternoon" -A tomorrow="Remind Me Tomorrow" \
	"FaceTime Grandma" "Today, 9:41 AM" >"$work/reminder.out" &
sleep 0.15
reminder=$(id_of_log)
notify-send -i call-start "Wi-Fi Calling" "You can use your phone number to make and receive calls directly on this Mac using Wi-Fi."
sleep 0.1
notify-send -h string:desktop-entry:firefox -a Firefox "Download complete" "report.pdf has finished downloading."
sleep 0.1
notify-send -a Mail "Markup" '<b>Bold</b>, <i>italic</i>, <u>underline</u>, <a href="https://example.org">a link</a> &amp; <img src="x" alt="[image]"/>'
markup=$(id_of_log)
sleep 1
away
shot 01-dark
crop 01-dark

echo "== hover"
hover_on "$(card_center "$markup")"
sleep 0.4
check "hover pauses the banner under the pointer" logged "paused id=$markup true"
crop 02-hover-close-button
sleep 6.5
check "hovered normal banner outlives its 6 s timeout" bash -c "! grep -q 'closed id=$markup ' '$work/daemon.log'"
away
sleep 1
check "1 s after the pointer leaves it is still there (resume minimum 1.5 s)" bash -c "! grep -q 'closed id=$markup ' '$work/daemon.log'"
sleep 1.5
check "then it expires" logged "closed id=$markup reason=Expired"

echo "== Options menu"
click_on "$(pill_center "$reminder")"
sleep 0.4
check "pill click opens the menu" logged "menu open id=$reminder"
away
crop 03-menu-dark 520
shot 03-menu-dark
# Inside the surface's column but below every banner: this must fall through
# the input mask, land outside the surface and clear the focus grab.
read -r sx _ sw _ <<<"$(card_of "$reminder")"
click_at "$((surface_x + ${sx%.*} + ${sw%.*} / 2))" "$((mon_h - 60))"
sleep 0.4
check "click below the banners passes through and closes the menu" logged "menu closed"
click_on "$(pill_center "$reminder")"
sleep 0.4
click_on "$(menu_row "$reminder" 1)"
sleep 0.6
check "menu row click invokes its action (notify-send got 'hour')" grep -qx hour "$work/reminder.out"
check "the banner closes after the action" logged "closed id=$reminder "

echo "== close button and default action"
notify-send -u critical "Close me" "critical, closed with the x" &
sleep 0.4
closeme=$(id_of_log)
notify-send -A default=Open -A other=Other "Default action" "click the banner" >"$work/default.out" &
sleep 0.6
defid=$(id_of_log)
hover_on "$(card_center "$closeme")"
sleep 0.3
click_on "$(close_center "$closeme")"
sleep 0.5
check "close button dismisses" logged "closed id=$closeme reason=Dismissed"
click_on "$(card_center "$defid")"
sleep 0.5
check "banner click invokes the default action" grep -qx default "$work/default.out"
away
sleep 0.5

echo "== burst of 10, rapid dismiss"
before=$(log_count "reason=Dismissed")
for i in $(seq 1 10); do notify-send "Burst $i" "notification $i of 10" & done
for i in $(seq -w 1 8); do
	WAYLAND_DISPLAY=$nested grim -g "$((mon_w - 520)),0 520 330" "$out/04-burst-frame-$i.png"
done
sleep 1
crop 05-burst-settled 330
read -r tx _ <<<"$(card_center "$(grep 'layout id=' "$work/daemon.log" | tail -1 | sed 's/.*layout id=\([0-9]*\).*/\1/')")"
# Rapid clicks on the top slot: each dismisses whatever banner is there.
first_slot_y=$((surface_y + 10 + 32))
for _ in 1 2 3 4 5 6; do
	click_at "$tx" "$first_slot_y"
	sleep 0.08
done
for i in 1 2 3 4; do
	WAYLAND_DISPLAY=$nested grim -g "$((mon_w - 520)),0 520 330" "$out/06-rapid-dismiss-frame-$i.png"
done
sleep 1
after=$(log_count "reason=Dismissed")
check "rapid clicks dismissed at least 4 banners" test "$((after - before))" -ge 4
away
for _ in $(seq 20); do
	ids=$(grep -o 'shown id=[0-9]*' "$work/daemon.log" | sed 's/shown id=//' | while read -r n; do
		grep -q "closed id=$n " "$work/daemon.log" || echo "$n"
	done)
	[ -z "$ids" ] && break
	for n in $ids; do
		busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
			org.freedesktop.Notifications CloseNotification u "$n" >/dev/null 2>&1 || true
	done
	sleep 0.5
done
check "every burst notification was shown once" equals \
	"$(grep -o 'shown id=[0-9]*' "$work/daemon.log" | sort | uniq -d | wc -l)" 0

echo "== same-id replace"
rid=$(notify-send -p "Download" "10% complete")
sleep 1
notify-send -r "$rid" "Download" "60% complete, now with a second line of text that makes the banner taller than before"
for i in 1 2 3; do
	WAYLAND_DISPLAY=$nested grim -g "$((mon_w - 520)),0 520 200" "$out/07-replace-frame-$i.png"
done
check "replace updates in place (one shown line for the id)" equals "$(log_count "shown id=$rid queued")" 1
busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
	org.freedesktop.Notifications CloseNotification u "$rid" >/dev/null
sleep 0.5

echo "== reference look, light"
config '{"mode": "light"}'
notify-send -u critical -a Reminders -i x-office-calendar -A default=Open -A done="Mark as Completed" \
	-A hour="Remind Me in an Hour" -A afternoon="Remind Me This Afternoon" -A tomorrow="Remind Me Tomorrow" \
	"FaceTime Grandma" "Today, 9:41 AM" >/dev/null &
sleep 0.15
light=$(id_of_log)
notify-send -i call-start "Wi-Fi Calling" "You can use your phone number to make and receive calls directly on this Mac using Wi-Fi."
sleep 1
click_on "$(pill_center "$light")"
sleep 0.4
hover_on "$(menu_row "$light" 0)"
sleep 0.4
crop 08-light-menu-hover 520
shot 08-light-menu-hover
away

echo "== log"
errors=$(grep -E 'TypeError|ReferenceError|Unable to assign|Cannot read|is not a function| WARN| ERROR' "$work/daemon.log" || true)
check "no QML errors or warnings in the daemon log" test -z "$errors"
[ -n "$errors" ] && printf '%s\n' "$errors" | head -20

echo "failures: $failures"
[ "$failures" = 0 ]
