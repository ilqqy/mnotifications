#!/usr/bin/env bash
# Offscreen behaviour and render test. No compositor is involved: the real
# Store, BannerStack and Banner run in an offscreen Quickshell window, fed by
# notify-send and busctl over a private D-Bus session bus (dbus-run-session),
# so a running notification daemon is never contacted. Screenshots land in
# tests/out/render-<time>/. Hover, real pointer input and the compositor's
# blur are out of reach here; tests/isolated.sh covers them.
#
# Usage: tests/render.sh [scenario...]   (default: all, see the end of file)
# Needs qs, notify-send, dbus-run-session, busctl and jq: run it inside
# `nix develop`.
set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [ "${1:-}" != --inner ]; then
	work=$(mktemp -d "${TMPDIR:-/tmp}/mnotif-render.XXXXXX")
	trap 'rm -rf -- "$work"' EXIT
	out=$repo/tests/out/render-$(date +%Y%m%d-%H%M%S)
	mkdir -p "$out"
	mkdir -m 700 "$work/run"
	mkdir "$work/root"
	# Quickshell imports only from the config root: a scratch root holds the
	# sources with the harness as its shell.qml.
	cp "$repo"/*.qml "$repo"/text.js "$work/root/"
	cp "$repo/tests/render.qml" "$work/root/shell.qml"
	status=0
	dbus-run-session -- "$0" --inner "$work" "$out" "$@" || status=$?
	echo "screenshots and log: $out"
	exit "$status"
fi

work=$2
out=$3
export XDG_RUNTIME_DIR=$work/run
export MNOTIF_RENDER_OUT=$out
export MNOTIFICATIONS_CONFIG=$work/config.json
export MNOTIFICATIONS_DEBUG=1
if [ -z "${QS_ICON_THEME:-}" ]; then
	theme=$(sed -n 's/^gtk-icon-theme-name *= *//p' "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null || true)
	[ -n "$theme" ] && export QS_ICON_THEME=$theme
fi

config() { printf '%s\n' "$1" >"$MNOTIFICATIONS_CONFIG"; sleep 0.3; }
config '{}'

QT_QPA_PLATFORM=offscreen qs --no-color -p "$work/root" >"$work/log" 2>&1 &
qs_pid=$!
cleanup() {
	kill "$qs_pid" 2>/dev/null || true
	wait "$qs_pid" 2>/dev/null || true
	cp "$work/log" "$out/daemon.log"
}
trap cleanup EXIT

for _ in $(seq 100); do
	busctl --user status org.freedesktop.Notifications >/dev/null 2>&1 && break
	sleep 0.1
done

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

ipc() { qs ipc --pid "$qs_pid" call test "$@"; }
state() { ipc state; }
q() { state | jq -r "$1"; }
visible() { q '[.banners[] | select(.leaving | not)] | length'; }
queued() { q '.queued'; }
present() { [ "$(q "[.banners[] | select(.title == \"$1\" and (.leaving | not))] | length")" = 1 ]; }
absent() { ! present "$1"; }
timeout_of() { q ".banners[] | select(.title == \"$1\") | .timeout"; }
id_of() { q ".banners[] | select(.title == \"$1\") | .id"; }
# Waits for the grab to be written; the log line carries its latency.
shot() {
	ipc shot "$1" >/dev/null
	for _ in $(seq 50); do
		grep -q "render: shot $1 " "$work/log" && break
		sleep 0.05
	done
	grep -o "render: shot $1 .*" "$work/log" | sed 's/^render: //'
}
logged() { grep -q -- "$1" "$work/log"; }
now_ms() { echo $(($(date +%s%N) / 1000000)); }
# Sleeps until <start_ms> + <offset_ms>.
sleep_until() {
	local left=$(($1 + $2 - $(now_ms)))
	if ((left > 0)); then sleep "$(printf '%d.%03d' $((left / 1000)) $((left % 1000)))"; fi
}
equals() { [ "$1" = "$2" ]; }

clear_all() {
	local id
	for _ in $(seq 40); do
		[ "$(visible)" = 0 ] && [ "$(queued)" = 0 ] && break
		for id in $(q '.banners[] | select(.leaving | not) | .id'); do ipc dismiss "$id" >/dev/null; done
		sleep 0.25
	done
	sleep 0.4
}

# Sends a notification carrying an image-data hint: a 24x24 RGBA disc.
notify_image() {
	local bytes=() x y dx dy r g b a
	for ((y = 0; y < 24; y++)); do
		for ((x = 0; x < 24; x++)); do
			dx=$((x - 12)) dy=$((y - 12))
			if ((dx * dx + dy * dy <= 144)); then
				r=$((60 + x * 8)) g=$((120 + y * 4)) b=230 a=255
			else
				r=0 g=0 b=0 a=0
			fi
			bytes+=("$r" "$g" "$b" "$a")
		done
	done
	busctl --user -- call org.freedesktop.Notifications /org/freedesktop/Notifications \
		org.freedesktop.Notifications Notify 'susssasa{sv}i' \
		"$1" 0 "" "$2" "$3" 0 1 image-data '(iiibiiay)' 24 24 96 true 8 4 2304 "${bytes[@]}" -1 >/dev/null
}

# Sends via busctl with an app_icon argument (notify-send puts -i into the
# image-path hint instead).
notify_app_icon() {
	busctl --user -- call org.freedesktop.Notifications /org/freedesktop/Notifications \
		org.freedesktop.Notifications Notify 'susssasa{sv}i' \
		"$1" 0 "$2" "$3" "$4" 0 0 -1 >/dev/null
}

scenario_capabilities() {
	echo "== capabilities"
	caps=$(busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications GetCapabilities)
	echo "$caps"
	check "capabilities advertise body-markup, body-hyperlinks, actions" \
		bash -c "grep -q body-markup <<<'$caps' && grep -q body-hyperlinks <<<'$caps' && grep -q '\"actions\"' <<<'$caps'"
}

scenario_timeouts() {
	echo "== urgencies and timeouts"
	config '{"maxVisible": 8}'
	notify-send -u low "Low" "low urgency, 4 s"
	notify-send -u normal "Normal" "normal urgency, 6 s"
	notify-send -u critical "Critical" "never expires"
	notify-send -t 2000 "App 2s" "sane app timeout"
	notify-send -t 500 "App 500ms" "too short, urgency default instead"
	notify-send -t 0 "Persistent" "expire_timeout 0"
	t0=$(now_ms)
	sleep 0.8
	shot 01-urgencies
	check "six banners visible with maxVisible 8" equals "$(visible)" 6
	check "low timeout 4000" equals "$(timeout_of Low)" 4000
	check "normal timeout 6000" equals "$(timeout_of Normal)" 6000
	check "critical never expires" equals "$(timeout_of Critical)" 0
	check "app timeout 2000 honoured" equals "$(timeout_of 'App 2s')" 2000
	check "app timeout 500 replaced by default" equals "$(timeout_of 'App 500ms')" 6000
	check "expire_timeout 0 kept" equals "$(timeout_of Persistent)" 0
	sleep_until "$t0" 3000
	check "2 s banner gone at 3 s" absent "App 2s"
	check "low still there at 3 s" present Low
	sleep_until "$t0" 5000
	check "low gone at 5 s" absent Low
	check "normal still there at 5 s" present Normal
	sleep_until "$t0" 7000
	check "normal gone at 7 s" absent Normal
	check "500 ms banner gone at 7 s" absent "App 500ms"
	sleep_until "$t0" 9000
	check "critical still there at 9 s" present Critical
	check "persistent still there at 9 s" present Persistent
	check "expiry reported as Expired" logged "reason=Expired"
	clear_all
}

scenario_reference() {
	echo "== reference look, dark and light"
	config '{}'
	notify-send -u critical -a Reminders -i x-office-calendar -A default=Open -A done="Mark as Completed" \
		-A hour="Remind Me in an Hour" -A afternoon="Remind Me This Afternoon" -A tomorrow="Remind Me Tomorrow" \
		"FaceTime Grandma" "Today, 9:41 AM" >"$work/reminder.out" &
	sleep 0.1
	notify-send -i call-start "Wi-Fi Calling" "You can use your phone number to make and receive calls directly on this Mac using Wi-Fi."
	sleep 0.1
	notify-send -h string:desktop-entry:firefox -a Firefox "Download complete" "report.pdf has finished downloading."
	sleep 0.1
	notify-send -a Mail "Markup" '<b>Bold</b>, <i>italic</i>, <u>underline</u>, <a href="https://example.org">a link</a> &amp; <img src="x" alt="[image]"/> <span>span</span><script>alert(1)</script>'
	sleep 1
	shot 02-dark
	config '{"mode": "light"}'
	shot 03-light
	reminder=$(id_of "FaceTime Grandma")
	check "close button and Options pill hidden without hover" equals "$(q ".banners[] | select(.id == $reminder) | .chrome")" false
	ipc toggleMenu "$reminder" >/dev/null
	sleep 0.4
	check "both shown while the banner's menu is open" equals "$(q ".banners[] | select(.id == $reminder) | .chrome")" true
	shot 04-menu-light
	check "menu lists the four non-default actions" equals \
		"$(q '.menuRows | join("|")')" "Mark as Completed|Remind Me in an Hour|Remind Me This Afternoon|Remind Me Tomorrow"
	config '{}'
	shot 05-menu-dark
	ipc choose 1 >/dev/null
	sleep 0.6
	check "menu row invokes its action (notify-send got 'hour')" grep -qx hour "$work/reminder.out"
	check "invoked banner closes" absent "FaceTime Grandma"
	check "menu closed after choosing" equals "$(q .menuOpen)" false
	clear_all
}

scenario_actions() {
	echo "== default action, plain click, app close"
	notify-send -p -A default=Open -A other=Other "Has default" "click opens" >"$work/default.out" &
	notify-send "No actions" "click dismisses"
	appclose=$(notify-send -p "Closed by app" "CloseNotification")
	sleep 0.8
	ipc activate "$(id_of 'Has default')" >/dev/null
	ipc activate "$(id_of 'No actions')" >/dev/null
	busctl --user -- call org.freedesktop.Notifications /org/freedesktop/Notifications \
		org.freedesktop.Notifications CloseNotification u "$appclose"
	sleep 0.6
	check "click invokes the default action" grep -qx default "$work/default.out"
	check "default-action banner closes" absent "Has default"
	check "click without default action dismisses" absent "No actions"
	check "dismiss reported as Dismissed" logged "reason=Dismissed"
	check "app close removes the banner" absent "Closed by app"
	check "app close reported as CloseRequested" logged "closed id=$appclose reason=CloseRequested"
	clear_all
}

scenario_icons() {
	echo "== icons"
	local icon_png
	icon_png=$(find /run/current-system/sw/share/icons/hicolor/48x48/apps -name '*.png' 2>/dev/null | head -1 || true)
	config '{"maxVisible": 8}'
	notify-send -i firefox "Theme icon (image-path name)" "image-path: firefox"
	sleep 0.1
	if [ -n "$icon_png" ]; then notify-send -i "$icon_png" "File icon (image-path)" "$(basename "$icon_png")"; fi
	sleep 0.1
	notify_image Messages "Image data hint" "24x24 RGBA from image-data"
	sleep 0.1
	notify_app_icon Discord discord "app_icon argument" "app_icon=discord"
	sleep 0.1
	notify-send -h string:desktop-entry:firefox "Desktop entry only" "desktop-entry=firefox"
	sleep 0.1
	notify-send -i does-not-exist-icon "Missing icon" "falls back to dialog-information"
	sleep 0.1
	notify-send "No icon at all" "appName notify-send, nothing else"
	sleep 1
	shot 06-icons
	state | jq -c '.banners[] | {title, image, appIcon}'
	check "seven icon banners shown" equals "$(visible)" 7
	clear_all
}

scenario_long() {
	echo "== long text"
	config '{}'
	notify-send "A very long title that keeps going well past the width of the banner so it has to be cut short" \
		"$(printf 'Body line %s with enough words to wrap across the banner several times over. ' 1 2 3 4 5 6)"
	notify-send -A default=Open -A x="Another action" "Long with Options" \
		"The Options pill takes its column on the right, so this body wraps narrower than the one above it does." >/dev/null &
	sleep 1
	shot 07-long-text
	clear_all
}

scenario_burst() {
	echo "== burst of 10 and rapid dismiss"
	first_burst=$(($(grep -c 'notify id=' "$work/log" || true) + 1))
	for i in $(seq 1 10); do notify-send "Burst $i" "notification $i of 10" & done
	sleep 0.15
	shot 08-burst-entering
	sleep 1.2
	check "burst: 4 visible" equals "$(visible)" 4
	check "burst: 6 queued" equals "$(queued)" 6
	shot 09-burst-settled
	pids=()
	for id in $(q '.banners[] | select(.leaving | not) | .id'); do
		ipc dismiss "$id" >/dev/null &
		pids+=($!)
	done
	wait "${pids[@]}"
	sleep 0.08
	shot 10-rapid-dismiss
	sleep 1.2
	check "after rapid dismiss: 4 visible again" equals "$(visible)" 4
	check "after rapid dismiss: 2 queued" equals "$(queued)" 2
	clear_all
	burst_shown=0
	for n in $(grep -o 'notify id=[0-9]*' "$work/log" | sed 's/notify id=//' | tail -n "+$first_burst" | head -10); do
		burst_shown=$((burst_shown + $(grep -c "shown id=$n queued" "$work/log" || true)))
	done
	check "each of the 10 burst notifications shown exactly once" equals "$burst_shown" 10
	check "empty after clearing" equals "$(visible)/$(queued)" "0/0"
}

scenario_replace() {
	echo "== same-id replace"
	rid=$(notify-send -p "Download" "10% complete")
	notify-send "Below it" "moves when the banner above changes height"
	sleep 1
	notify-send -r "$rid" "Download" "60% complete, now with a second line of text that makes the banner taller than before"
	sleep 0.05
	check "replace keeps the banner fully shown (no re-entrance)" equals "$(q ".banners[] | select(.id == $rid) | .presence")" 1
	sleep 0.4
	shot 11-replace
	check "replace was logged" logged "replace id=$rid state=shown"
	check "replaced banner shown only once" equals "$(grep -c "shown id=$rid queued" "$work/log")" 1
	check "still one Download banner" equals "$(q '[.banners[] | select(.title == "Download")] | length')" 1
	clear_all
}

scenario_restart() {
	echo "== replace restarts the countdown"
	rid=$(notify-send -p "Restart" "v1")
	t0=$(now_ms)
	sleep 4
	notify-send -r "$rid" "Restart" "v2"
	sleep_until "$t0" 7500
	check "replaced at 4 s, still shown at 7.5 s" present Restart
	sleep_until "$t0" 11000
	check "gone at 11 s" absent Restart
	clear_all
}

scenario_positions() {
	echo "== positions"
	notify-send "One" "first"
	notify-send -A default=Open -A x=Other "Two" "second" >/dev/null &
	sleep 0.8
	config '{"position": "bottom-right"}'
	sleep 0.5
	shot 12-bottom-right
	config '{"position": "top-left", "mode": "light"}'
	sleep 0.5
	shot 13-top-left-light
	config '{}'
	clear_all
}

# All scenarios by default; name some to run only those.
scenarios=("${@:4}")
[ ${#scenarios[@]} -gt 0 ] || scenarios=(capabilities timeouts reference actions icons long burst replace restart positions)
for s in "${scenarios[@]}"; do "scenario_$s"; done

echo "== log"
# The offscreen platform cannot apply input masks; that warning is expected.
errors=$(grep -E 'TypeError|ReferenceError|Unable to assign|Cannot read|is not a function| WARN| ERROR' "$work/log" |
	grep -v 'does not support setting window masks' || true)
check "no QML errors or warnings in the log" test -z "$errors"
[ -n "$errors" ] && printf '%s\n' "$errors" | head -20

echo "failures: $failures"
[ "$failures" = 0 ]
