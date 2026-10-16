#!/bin/bash
# DropStopNShop – turns a Raspberry Pi into a shop display that shows whatever is in a folder.
# https://github.com/Falor/DropStopNShop · MIT License
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Falor/DropStopNShop/main/setup.sh | sudo bash
#   sudo bash setup.sh                  set up the Pi (safe to run again, e.g. to change the share)
#                                       installs to ./dropstopnshop (asks; remembers the folder)
#   sudo bash setup.sh --check          show what the display finds: sources, files, current state
#   sudo bash setup.sh --uninstall      remove it again and undo the system changes
#   sudo bash setup.sh --desktop        boot to the desktop again instead of the display
#   bash setup.sh --preview [FOLDER]    preview the slideshow on a Linux desktop
#   bash setup.sh --files-only DIR      only write the program files (for development)
#
# How it works on the Pi:
#   1. A sync job (systemd timer, every 3 minutes) collects the files from the display folder:
#      a USB stick with that folder wins, otherwise the network share (SMB). If neither is
#      reachable, the last state stays on screen. PDF pages become images; everything ends up in
#      <install folder>/data/state-…
#   2. After power-on, dropstopnshop-kiosk.service starts Chromium in kiosk mode (inside cage) on
#      tty1, showing <install folder>/index.html as a slideshow.
#   Power is expected to be cut hard (smart plug), so the Pi writes almost nothing to the SD card
#   while running: logs and browser profile live in RAM and there are no automatic updates.
#
# The whole script runs inside main(), so a download cut short by `curl | bash` does nothing.
set -euo pipefail

REPO_RAW=https://raw.githubusercontent.com/Falor/DropStopNShop/main
CONF_DIR=/etc/dropstopnshop  # share credentials and the install location (root only)
SELF=${BASH_SOURCE[0]:-}

write_files() {
	local target=$1
	mkdir -p "$target"

	# ---------------------------------------------------------------- slideshow
	cat >"$target/index.html" <<'EOF'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>DropStopNShop</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; cursor: none; }
  .slide { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain;
           opacity: 0; transition: opacity .8s ease; }
  .slide.visible { opacity: 1; }
  #hint { display: none; position: absolute; inset: 0; align-items: center; justify-content: center;
          flex-direction: column; color: #ddd; font: 2.2vw/1.5 sans-serif; text-align: center; }
  #hint p { max-width: 70vw; margin: 0 0 1em; }
  #hint h1 { font-size: 3.5vw; margin: 0 0 1em; color: #fff; }
</style>
</head>
<body>
<div id="hint"><h1 id="hint-title"></h1><p id="hint-files"></p><p id="hint-note"></p></div>
<script>
// The sync job writes the slide list to data/current/playlist.js (window.SLIDESHOW).
// It is reloaded after every round, so new content appears without a restart.
const DATA = 'data/';
const TEXT = {
  de: { title: 'Keine Inhalte gefunden', folder: 'Bildschirm',
        files: ['PDF-Dateien, Bilder (JPG, PNG) oder Videos (MP4) in den Ordner „', '“ legen.'],
        note: 'Die Anzeige holt sie sich innerhalb weniger Minuten von selbst.' },
  en: { title: 'No content found', folder: 'Display',
        files: ['Put PDF files, images (JPG, PNG) or videos (MP4) into the folder “', '”.'],
        note: 'The display picks them up within a few minutes.' },
};
let show = null, index = -1, current = null, timer = null;

function loadPlaylist() {
  return new Promise(done => {
    const s = document.createElement('script');
    s.src = DATA + 'current/playlist.js?' + Date.now();
    s.onload = s.onerror = () => { s.remove(); done(window.SLIDESHOW || null); };
    document.head.appendChild(s);
  });
}

function hint(on) {
  if (on) {
    const lang = show?.lang || (navigator.language.startsWith('de') ? 'de' : 'en');
    const t = TEXT[lang] || TEXT.en;
    const folder = document.createElement('b');
    folder.textContent = show?.folder || t.folder;
    document.getElementById('hint-title').textContent = t.title;
    document.getElementById('hint-files').replaceChildren(t.files[0], folder, t.files[1]);
    document.getElementById('hint-note').textContent = t.note;
  }
  document.getElementById('hint').style.display = on ? 'flex' : 'none';
}

async function next() {
  clearTimeout(timer);
  index++;
  if (!show || index >= show.slides.length) {
    show = await loadPlaylist() || show;
    index = 0;
  }
  if (!show || show.slides.length === 0) {
    if (current) { current.remove(); current = null; }
    hint(true);
    timer = setTimeout(next, 30000);
    return;
  }
  hint(false);

  const slide = show.slides[index];
  const video = slide.t === 'video';
  const el = document.createElement(video ? 'video' : 'img');
  el.className = 'slide';
  let handled = false;
  el.addEventListener(video ? 'canplay' : 'load', () => {
    if (!handled) { handled = true; fadeIn(el, video); }
  });
  el.addEventListener('error', () => {
    if (!handled) { handled = true; el.remove(); timer = setTimeout(next, 1000); }
  });
  if (video) { el.muted = true; el.playsInline = true; }
  el.src = DATA + show.state + '/' + slide.f;
  document.body.appendChild(el);
}

function fadeIn(el, video) {
  const old = current;
  current = el;
  void el.offsetWidth;  // commit the start state so the transition runs
  el.classList.add('visible');
  // fade the old slide out too, so it never peeks out next to a slide of another aspect ratio
  if (old) { old.classList.remove('visible'); setTimeout(() => old.remove(), 1000); }
  if (video) {
    el.addEventListener('ended', () => { if (current === el) next(); });
    el.play().catch(() => {});
    // safety net in case a video stalls
    timer = setTimeout(next, Math.max((el.duration || 0) * 1000 + 5000, 10000));
  } else {
    timer = setTimeout(next, show.seconds * 1000);
  }
}

next();
</script>
</body>
</html>
EOF

	# ---------------------------------------------------------------- sync job
	cat >"$target/dropstopnshop-sync" <<'EOF'
#!/bin/bash
# DropStopNShop sync: collects the display files and prepares them for the slideshow.
# Sources, in this order: USB stick with the display folder > network share > last state.
# Runs every 3 minutes via systemd timer. Log: journalctl -u dropstopnshop-sync
#
# Folder rules:
#   - order = file name (01_…, 02_…); subfolders are ignored (e.g. "Archive")
#   - PDF: every page becomes a slide; images: jpg, png, webp, gif; videos: mp4, webm, m4v
#   - "until 2026-11-30", "bis 30.11.2026" in the file name: hidden from the next day on
#
# --check: only report what it finds (USB stick, network share, files, current state), change nothing.
#
# Testing on a PC: SOURCE=folder DATA_DIR=out RUN_DIR=tmp CONFIG=/dev/null ./dropstopnshop-sync
set -uo pipefail

CHECK=false
[ "${1:-}" = --check ] && CHECK=true

HERE=$(dirname "$(realpath "$0")")
CONFIG=${CONFIG:-$HERE/config}
[ -r "$CONFIG" ] && . "$CONFIG"
UI_LANG=${UI_LANG:-en}
DATA_DIR=${DATA_DIR:-$HERE/data}
RUN_DIR=${RUN_DIR:-/run/dropstopnshop}
FOLDER=${FOLDER:-$([ "$UI_LANG" = de ] && echo Bildschirm || echo Display)}
SLIDE_SECONDS=${SLIDE_SECONDS:-12}
RENDER_WIDTH=${RENDER_WIDTH:-1920}
SHARE=${SHARE:-}
SHARE_CREDENTIALS=${SHARE_CREDENTIALS:-/etc/dropstopnshop/share-credentials}

t() { if [ "$UI_LANG" = de ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

mkdir -p "$DATA_DIR" "$RUN_DIR"
exec 9>"$RUN_DIR/lock"
if $CHECK; then
	flock -w 120 9 || exit 1  # wait for a running sync
else
	flock -n 9 || exit 0
fi

cleanup() {
	local m
	for m in "$RUN_DIR/usb" "$RUN_DIR/share"; do
		mountpoint -q "$m" 2>/dev/null && umount -l "$m"
	done
	rm -rf "$DATA_DIR/.new"
}
trap cleanup EXIT

# The configured folder name, but the default names in both languages work on any stick too.
find_usb() {
	local dev dir name
	mkdir -p "$RUN_DIR/usb"
	for dev in $(readlink -f /dev/disk/by-id/usb-* 2>/dev/null | sort -u); do
		findmnt -rn -S "$dev" >/dev/null && continue  # e.g. a USB SSD the Pi boots from
		mount -o ro "$dev" "$RUN_DIR/usb" 2>/dev/null || continue
		for name in "$FOLDER" Bildschirm Display; do
			dir=$(find "$RUN_DIR/usb" -mindepth 1 -maxdepth 1 -type d -iname "$name" -print -quit)
			if [ -n "$dir" ]; then
				echo "$dir"
				return 0
			fi
		done
		umount "$RUN_DIR/usb"
	done
	return 1
}

mount_share() {
	local err
	[ -n "$SHARE" ] || return 1
	mkdir -p "$RUN_DIR/share"
	if ! err=$(timeout 40 mount -t cifs "$SHARE" "$RUN_DIR/share" \
		-o "ro,credentials=$SHARE_CREDENTIALS,iocharset=utf8,soft,noserverino" 2>&1); then
		echo "$(t "Netzwerkordner nicht erreichbar" "Network share not reachable") ($SHARE): $err"
		return 1
	fi
}

type_of() {
	case "${1,,}" in
	*.pdf) echo pdf ;;
	*.jpg | *.jpeg | *.png | *.webp | *.gif) echo image ;;
	*.mp4 | *.webm | *.m4v) echo video ;;
	esac
}

today=$(date +%F)
expired() {
	local re_iso='(bis|until)[ _-]*([0-9]{4})-([0-9]{2})-([0-9]{2})'
	local re_dmy='(bis|until)[ _-]*([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4})'
	local date
	shopt -s nocasematch
	if [[ $1 =~ $re_iso ]]; then
		date="${BASH_REMATCH[2]}-${BASH_REMATCH[3]}-${BASH_REMATCH[4]}"
	elif [[ $1 =~ $re_dmy ]]; then
		date=$(printf '%s-%02d-%02d' "${BASH_REMATCH[4]}" "$((10#${BASH_REMATCH[3]}))" "$((10#${BASH_REMATCH[2]}))")
	else
		return 1
	fi
	[[ $date < $today ]]
}

json_str() {
	local s=${1//\\/\\\\}
	printf '"%s"' "${s//\"/\\\"}"
}

# --- pick the source
if $CHECK; then
	# look at both sources, then report on the one the sync would use
	src="" origin=""
	if [ -n "${SOURCE:-}" ]; then
		src=$SOURCE origin=$(t Testordner "test folder")
	elif usb=$(find_usb); then
		echo "$(t USB-Stick "USB stick"): $(t "Ordner gefunden – hat Vorrang vor dem Netzwerkordner" "folder found – takes priority over the network share")"
		src=$usb origin=$(t USB-Stick "USB stick")
	else
		echo "$(t USB-Stick "USB stick"): $(t "keiner mit Ordner „$FOLDER“" "none with folder \"$FOLDER\"")"
	fi
	if [ -n "${SOURCE:-}" ]; then
		:
	elif [ -z "$SHARE" ]; then
		echo "$(t Netzwerkordner "Network share"): $(t "nicht eingestellt" "not configured")"
	elif mount_share; then
		echo "$(t Netzwerkordner "Network share"): $(t erreichbar reachable) ($SHARE)"
		[ -n "$src" ] || src="$RUN_DIR/share" origin=$(t Netzwerkordner "network share")
	fi
	if [ -z "$src" ]; then
		t "Keine Quelle erreichbar – die Anzeige zeigt den letzten Stand." "No source reachable – the display shows the last state."
		echo
	fi
elif [ -n "${SOURCE:-}" ]; then
	src=$SOURCE origin=$(t Testordner "test folder")
elif src=$(find_usb); then
	origin=$(t USB-Stick "USB stick")
elif mount_share; then
	src="$RUN_DIR/share" origin=$(t Netzwerkordner "network share")
else
	t "Keine Quelle erreichbar – die Anzeige zeigt weiter den letzten Stand." \
		"No source reachable – the display keeps showing the last state."
	echo
	exit 0
fi

# --- list the files; on read errors keep the old state rather than showing an empty screen
if [ -z "$src" ]; then
	: # --check without a source: only the current state below
elif ! find "$src" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -print0 >"$RUN_DIR/list"; then
	echo "$(t "Ordner nicht lesbar" "Folder not readable") ($origin) – $(t "die Anzeige zeigt weiter den letzten Stand." "the display keeps showing the last state.")"
	exit 0
fi
all=()
[ -n "$src" ] && mapfile -d '' all < <(LC_ALL=C sort -z -f "$RUN_DIR/list")

active=() notes=()
for f in "${all[@]}"; do
	name=${f##*/}
	if [ -z "$(type_of "$name")" ]; then
		notes+=("$(t "übersprungen (unbekannter Dateityp)" "skipped (unknown file type)"): $name")
	elif expired "$name"; then
		notes+=("$(t abgelaufen expired): $name")
	else
		active+=("$f")
	fi
done

fingerprint=$({
	echo "$SLIDE_SECONDS $RENDER_WIDTH $UI_LANG $FOLDER"
	for f in "${active[@]}"; do stat -c '%s %Y' "$f"; echo "${f##*/}"; done
} | sha1sum | cut -c1-12)
current=$(cat "$DATA_DIR/current/fingerprint" 2>/dev/null)

if $CHECK; then
	if [ -n "$src" ]; then
		echo
		echo "$(t "Dateien" "Files") ($origin):"
		[ ${#all[@]} -eq 0 ] && echo "  $(t "(Ordner ist leer)" "(folder is empty)")"
		for f in "${active[@]}"; do echo "  $(t "wird gezeigt" "shown"): ${f##*/}"; done
		[ ${#notes[@]} -gt 0 ] && printf '  %s\n' "${notes[@]}"
	fi
	echo
	if [ -z "$current" ]; then
		echo "$(t "Auf dem Bildschirm" "On screen"): $(t "noch nichts aufbereitet" "nothing prepared yet")"
	else
		echo "$(t "Auf dem Bildschirm" "On screen"): $(grep -c '"t":' "$DATA_DIR/current/playlist.js") $(t Folien slides), $(t "Stand vom" "prepared") $(date -r "$DATA_DIR/current/playlist.js" '+%d.%m.%Y %H:%M')"
		if [ -n "$src" ] && [ "$current" != "$fingerprint" ]; then
			t "Der Ordner hat sich geändert – der nächste Abgleich (spätestens in 3 Minuten) übernimmt das." \
				"The folder has changed – the next sync (within 3 minutes) picks that up."
			echo
		fi
	fi
	exit 0
fi

if [ "$current" = "$fingerprint" ]; then
	echo "$(t Unverändert Unchanged): $origin, ${#active[@]} $(t Dateien files)"
	exit 0
fi

# --- build the new state
echo "$(t "Neue Inhalte von" "New content from") $origin:"
[ ${#notes[@]} -gt 0 ] && printf '  %s\n' "${notes[@]}"
new="$DATA_DIR/.new"
rm -rf "$new"
mkdir -p "$new"
n=0 slides=()
for f in "${active[@]}"; do
	name=${f##*/}
	kind=$(type_of "$name")
	case $kind in
	pdf)
		mkdir "$new/pdf"
		if timeout 300 pdftoppm -png -scale-to "$RENDER_WIDTH" "$f" "$new/pdf/p" 2>/dev/null; then
			for p in "$new"/pdf/p-*.png; do
				n=$((n + 1))
				out=$(printf '%04d.png' "$n")
				mv "$p" "$new/$out"
				slides+=("{\"t\": \"image\", \"f\": \"$out\"}")
			done
			echo "  PDF: $name"
		else
			echo "  $(t "FEHLER, PDF nicht lesbar" "ERROR, cannot read PDF"): $name"
		fi
		rm -rf "$new/pdf"
		;;
	image | video)
		ext=${name##*.}
		n=$((n + 1))
		out=$(printf '%04d.%s' "$n" "${ext,,}")
		if cp "$f" "$new/$out"; then
			slides+=("{\"t\": \"$kind\", \"f\": \"$out\"}")
			echo "  $(t "$([ "$kind" = image ] && echo Bild || echo Video)" "${kind^}"): $name"
		else
			echo "  $(t "FEHLER, nicht kopierbar" "ERROR, cannot copy"): $name"
		fi
		;;
	esac
done

state="state-$(date +%Y%m%d-%H%M%S)-$fingerprint"
{
	printf 'window.SLIDESHOW = {"lang": "%s", "folder": %s, "state": "%s", "seconds": %d, "slides": [\n' \
		"$UI_LANG" "$(json_str "$FOLDER")" "$state" "$SLIDE_SECONDS"
	(IFS=$'\n'; printf '%s\n' "${slides[*]}" | sed '$!s/$/,/')
	printf ']};\n'
} >"$new/playlist.js"
echo "$fingerprint" >"$new/fingerprint"

# Write everything to the card first, then switch over: a power cut at any point
# always leaves a complete state behind.
sync
old=$(readlink "$DATA_DIR/current" 2>/dev/null || true)
mv "$new" "$DATA_DIR/$state"
ln -sfn "$state" "$DATA_DIR/current.new"
mv -T "$DATA_DIR/current.new" "$DATA_DIR/current"
sync

# Delete old states; the previous one stays until the slideshow has finished its round.
for s in "$DATA_DIR"/state-*; do
	[ "${s##*/}" = "$state" ] || [ "${s##*/}" = "$old" ] || rm -rf "$s"
done
echo "$(t Fertig Done): ${#slides[@]} $(t Folien slides)."
EOF

	# ---------------------------------------------------------------- kiosk start
	cat >"$target/kiosk.sh" <<'EOF'
#!/bin/bash
# Starts Chromium full screen inside cage. Run by dropstopnshop-kiosk.service on tty1,
# which also restarts it if it ever exits. Log: journalctl -u dropstopnshop-kiosk
HERE=$(dirname "$(realpath "$0")")
BROWSER=$(command -v chromium || command -v chromium-browser)
PROFILE="${XDG_RUNTIME_DIR:-/tmp}/kiosk-profile"  # in RAM, created fresh on every start

export WLR_LIBINPUT_NO_DEVICES=1  # start even without mouse and keyboard
# use the graphics device that has the HDMI ports (the Pi 5 has two DRM devices)
for c in /sys/class/drm/card*-HDMI-A-*; do
	[ -e "$c" ] || continue
	k=${c##*/}
	export WLR_DRM_DEVICES=/dev/dri/${k%%-*}
	break
done

# Invisible mouse pointer: cage draws its default pointer in the middle of the screen until the
# mouse moves into the page, so hand it a cursor theme whose pointers are a single transparent
# pixel (Xcursor format). Lives in RAM next to the profile.
CURSORS="${XDG_RUNTIME_DIR:-/tmp}/kiosk-cursors"
mkdir -p "$CURSORS/none/cursors"
printf 'Xcur\x10\0\0\0\0\0\x01\0\x01\0\0\0\x02\0\xfd\xff\x18\0\0\0\x1c\0\0\0\x24\0\0\0\x02\0\xfd\xff\x18\0\0\0\x01\0\0\0\x01\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0' \
	>"$CURSORS/none/cursors/default"
for name in left_ptr arrow pointer hand1 hand2 text xterm wait watch progress crosshair \
	not-allowed grab grabbing move all-scroll; do
	ln -sf default "$CURSORS/none/cursors/$name"
done
export XCURSOR_PATH="$CURSORS" XCURSOR_THEME=none

rm -rf "$PROFILE"
exec cage -s -- "$BROWSER" --kiosk --ozone-platform=wayland \
	--noerrdialogs --disable-infobars --no-first-run --no-default-browser-check \
	--disable-session-crashed-bubble --disable-features=Translate,MediaRouter \
	--autoplay-policy=no-user-gesture-required --password-store=basic \
	--check-for-update-interval=31536000 --user-data-dir="$PROFILE" \
	"$HERE/index.html"
EOF
	chmod +x "$target/dropstopnshop-sync" "$target/kiosk.sh"
}

# ==================================================================== helpers

# German if the locale or the keyboard layout (set in the Raspberry Pi Imager) says so
detect_lang() {
	case "${LANG:-}" in de*) echo de && return ;; esac
	if grep -qsE '^XKBLAYOUT="?(de|at|ch)' /etc/default/keyboard; then echo de; else echo en; fi
}
t() { if [ "$UI_LANG" = de ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ask VAR "question" default – reads from the terminal, also when the script comes via a pipe
ask() {
	local _reply=""
	read -r -p "$2 [$3]: " _reply </dev/tty || true
	printf -v "$1" '%s' "${_reply:-$3}"
}

# confirm "question" y|n
confirm() {
	local answer="" hint
	if [ "$2" = y ]; then hint=$(t "[J/n]" "[Y/n]"); else hint=$(t "[j/N]" "[y/N]"); fi
	read -r -p "$1 $hint " answer </dev/tty || true
	answer=${answer:-$2}
	[[ ${answer,,} == [yj]* ]]
}

# ==================================================================== preview on a desktop PC

preview() {
	local src tmp
	UI_LANG=$(detect_lang)
	src=$(realpath "${1:-.}")
	[ -d "$src" ] || { echo "$(t "Ordner nicht gefunden" "Folder not found"): $src"; exit 1; }
	command -v pdftoppm >/dev/null || {
		t "pdftoppm fehlt (Arch: sudo pacman -S poppler, Debian/Ubuntu: sudo apt install poppler-utils)" \
			"pdftoppm is missing (Arch: sudo pacman -S poppler, Debian/Ubuntu: sudo apt install poppler-utils)"
		echo
		exit 1
	}
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	write_files "$tmp/app"
	ln -s ../data "$tmp/app/data"
	sync_preview() {
		SOURCE="$src" DATA_DIR="$tmp/data" RUN_DIR="$tmp/run" CONFIG=/dev/null UI_LANG=$UI_LANG \
			"$tmp/app/dropstopnshop-sync"
	}
	sync_preview
	xdg-open "file://$tmp/app/index.html" >/dev/null 2>&1 &
	t "Vorschau für $src läuft – Änderungen im Ordner erscheinen nach dem nächsten Durchlauf. Ende mit Strg+C." \
		"Previewing $src – changes in the folder show up after the next round. Stop with Ctrl+C."
	echo
	while sleep 5; do sync_preview; done
}

# ==================================================================== setup on the Pi

need_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo "Bitte mit sudo starten / Please run with sudo: sudo bash setup.sh $*"
		exit 1
	fi
}

# The install folder of an existing installation, if any
installed_app() { cat "$CONF_DIR/location" 2>/dev/null || true; }

# Remember a setting as it was before the first install, so --uninstall can restore it
remember() { # remember KEY value
	grep -qs "^$1=" "$CONF_DIR/before-install" || echo "$1=$2" >>"$CONF_DIR/before-install"
}

has_desktop() { systemctl cat display-manager.service >/dev/null 2>&1; }

# choose VAR "title" default item… – numbered list, stores the chosen number (1-based) in VAR
choose() {
	local _var=$1 _title=$2 _default=$3 _i=1 _item _reply
	shift 3
	echo "$_title"
	for _item in "$@"; do
		printf '  %2d) %s\n' "$_i" "$_item"
		_i=$((_i + 1))
	done
	while true; do
		read -r -p "$(t Auswahl Choice) [$_default]: " _reply </dev/tty || true
		_reply=${_reply:-$_default}
		if [[ $_reply =~ ^[0-9]+$ ]] && ((_reply >= 1 && _reply <= $#)); then
			printf -v "$_var" '%s' "$_reply"
			return
		fi
		t "Bitte eine Nummer aus der Liste eingeben." "Please enter a number from the list."
		echo
	done
}

# ------------------------------------------------------------------ network

# plain HTTP: a fresh Pi has no clock battery, so its date (and HTTPS) may be off until NTP ran
internet_ok() { curl -sS --max-time 8 -o /dev/null http://archive.raspberrypi.com/ 2>/dev/null; }

setup_network() {
	local online=false ssid
	internet_ok && online=true
	if ! command -v nmcli >/dev/null || ! nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
		: # no NetworkManager or no Wi-Fi chip: nothing to offer
	else
		ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -n 1)
		if [ -n "$ssid" ]; then
			echo "$(t "WLAN verbunden" "Wi-Fi connected"): $ssid"
		else
			if $online; then
				t "Internet über Netzwerkkabel ist da, WLAN ist nicht eingerichtet." \
					"Internet via network cable works, Wi-Fi is not set up."
			else
				t "Keine Internetverbindung und kein WLAN eingerichtet." "No internet connection and no Wi-Fi set up."
			fi
			echo
			if confirm "$(t "WLAN jetzt einrichten?" "Set up Wi-Fi now?")" "$($online && echo n || echo y)"; then
				setup_wifi || true
			fi
		fi
	fi
	if ! internet_ok; then
		t "Keine Internetverbindung. Bitte Netzwerkkabel einstecken oder WLAN einrichten und das Setup erneut starten." \
			"No internet connection. Please plug in a network cable or set up Wi-Fi and run the setup again."
		echo
		exit 1
	fi
}

setup_wifi() {
	local country n count signal security ssid pass hidden
	local -a ssids secs labels
	local -A seen
	# Wi-Fi stays blocked on a Raspberry Pi until a country is set
	if command -v raspi-config >/dev/null && [ -z "$(raspi-config nonint get_wifi_country 2>/dev/null || true)" ]; then
		ask country "$(t "Land für das WLAN (z. B. DE, AT, CH)" "Country for Wi-Fi (e.g. GB, US, DE)")" "$(t DE GB)"
		raspi-config nonint do_wifi_country "${country^^}" || true
	fi
	rfkill unblock wifi 2>/dev/null || true
	nmcli radio wifi on 2>/dev/null || true

	while true; do
		t "Suche WLAN-Netze …" "Scanning for Wi-Fi networks …"
		echo
		ssids=() secs=() labels=() seen=()
		while IFS=: read -r signal security ssid; do
			[ -n "$ssid" ] && [ -z "${seen[$ssid]:-}" ] || continue
			seen[$ssid]=1
			ssids+=("$ssid")
			secs+=("$security")
			if [ -z "$security" ] || [ "$security" = -- ]; then
				labels+=("$ssid  ($signal %, $(t offen open))")
			else
				labels+=("$ssid  ($signal %)")
			fi
		done < <(nmcli -t --escape no -f SIGNAL,SECURITY,SSID dev wifi list --rescan yes 2>/dev/null | sort -t: -k1,1nr)
		count=${#ssids[@]}
		labels+=("$(t "Netz nicht dabei – erneut suchen" "Network not listed – scan again")"
			"$(t "Verstecktes Netz – Namen eingeben" "Hidden network – enter its name")"
			"$(t "Abbrechen" "Cancel")")
		choose n "$(t "WLAN-Netze in der Nähe:" "Wi-Fi networks nearby:")" 1 "${labels[@]}"
		hidden=no
		if ((n <= count)); then
			ssid=${ssids[n - 1]} security=${secs[n - 1]}
		elif ((n == count + 1)); then
			continue
		elif ((n == count + 2)); then
			ask ssid "$(t "Name des WLANs" "Wi-Fi name")" ""
			security=unknown hidden=yes
		else
			return 1
		fi
		pass=""
		if [ -n "$security" ] && [ "$security" != -- ]; then
			read -r -s -p "$(t "WLAN-Passwort" "Wi-Fi password"): " pass </dev/tty || true
			echo
		fi
		if nmcli dev wifi connect "$ssid" ${pass:+password "$pass"} hidden "$hidden"; then
			echo "$(t "WLAN verbunden" "Wi-Fi connected"): $ssid"
			return 0
		fi
		nmcli connection delete id "$ssid" >/dev/null 2>&1 || true
		t "Verbindung fehlgeschlagen – ist das Passwort richtig?" "Connection failed – is the password correct?"
		echo
	done
}

# ------------------------------------------------------------------ network folder (SMB)

ask_credentials() {
	local user pass
	t "Benutzer mit Zugriff auf den Netzwerkordner (am besten nur Leserecht)." \
		"A user with access to the network folder (read-only is best)."
	echo
	ask user "$(t Benutzername Username)" ""
	read -r -s -p "$(t Passwort Password): " pass </dev/tty || true
	echo
	mkdir -p "$CONF_DIR"
	(umask 077; printf 'username=%s\npassword=%s\n' "$user" "$pass" >"$CONF_DIR/share-credentials")
}

# share_mount SHARE DIR – read-only, like the sync job does it
share_mount() {
	mkdir -p "$2"
	timeout 40 mount -t cifs "$1" "$2" \
		-o "ro,credentials=$CONF_DIR/share-credentials,iocharset=utf8,soft,noserverino"
}

# Sets SHARE (empty = USB stick only)
setup_share() {
	local n options=() fritz=false
	if [ -n "$SHARE" ]; then
		echo "$(t "Eingestellt" "Current setting"): $SHARE"
		confirm "$(t "Diesen Netzwerkordner behalten?" "Keep this network folder?")" y && return
	fi
	getent hosts fritz.box >/dev/null && fritz=true
	$fritz && options+=("$(t "Ordner auf der FRITZ!Box (Assistent)" "Folder on the FRITZ!Box (assistant)")")
	options+=("$(t "Pfad selbst eingeben (NAS, Windows-PC, …)" "Enter a path (NAS, Windows PC, …)")"
		"$(t "Kein Netzwerkordner – nur USB-Stick" "No network folder – USB stick only")")
	choose n "$(t "Woher kommen die Inhalte?" "Where does the content come from?")" 1 "${options[@]}"
	$fritz || n=$((n + 1))
	case $n in
	1) fritz_share || SHARE="" ;;
	2) manual_share || SHARE="" ;;
	3) SHARE="" ;;
	esac
}

fritz_share() {
	local mnt disk n reply
	local -a disks
	# The setup only reads; it never writes to the FRITZ!Box.
	t "Für den Pi am besten einen eigenen FRITZ!Box-Benutzer anlegen (System → FRITZ!Box-Benutzer) mit „Zugang zu NAS-Inhalten“, nur Leserecht." \
		"Best create a FRITZ!Box user just for the Pi (System → FRITZ!Box Users) with \"access to NAS contents\", read-only."
	echo
	[ -s "$CONF_DIR/share-credentials" ] &&
		confirm "$(t "Gespeicherte Zugangsdaten verwenden?" "Use the saved credentials?")" y || ask_credentials
	mnt=$(mktemp -d)
	until share_mount //fritz.box/FRITZ.NAS "$mnt"; do
		t "Anmeldung an der FRITZ!Box fehlgeschlagen. Ist der Speicher (NAS) unter Heimnetz → USB / Speicher aktiviert?" \
			"Could not sign in to the FRITZ!Box. Is storage (NAS) enabled under Home Network → USB / Storage?"
		echo
		if ! confirm "$(t "Zugangsdaten neu eingeben und erneut versuchen?" "Enter the credentials again and retry?")" y; then
			rmdir "$mnt"
			return 1
		fi
		ask_credentials
	done
	mapfile -t disks < <(find "$mnt" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
	if [ ${#disks[@]} -eq 0 ]; then
		t "An der FRITZ!Box ist kein Speicher angeschlossen." "No storage is connected to the FRITZ!Box."
		echo
		umount "$mnt"; rmdir "$mnt"
		return 1
	elif [ ${#disks[@]} -eq 1 ]; then
		disk=${disks[0]}
	else
		choose n "$(t "Auf welchem Speicher liegt der Ordner?" "Which storage holds the folder?")" 1 "${disks[@]}"
		disk=${disks[n - 1]}
	fi
	until [ -d "$mnt/$disk/$FOLDER" ]; do
		echo
		t "Auf „$disk“ gibt es noch keinen Ordner „$FOLDER“. Lege ihn am PC an:" \
			"There is no folder \"$FOLDER\" on \"$disk\" yet. Create it on the PC:"
		echo
		echo "  \\\\fritz.box\\FRITZ.NAS\\$disk\\$FOLDER"
		ask reply "$(t "Danach Enter drücken („-“ = ohne Netzwerkordner weiter)" "Then press Enter (\"-\" = continue without network folder)")" ""
		umount "$mnt"
		if [ "$reply" = - ]; then
			rmdir "$mnt"
			return 1
		fi
		share_mount //fritz.box/FRITZ.NAS "$mnt" || { rmdir "$mnt"; return 1; }  # fresh view of the folder
	done
	umount "$mnt"; rmdir "$mnt"
	SHARE="//fritz.box/FRITZ.NAS/$disk/$FOLDER"
	echo "$(t "Gefunden" "Found"): $SHARE"
	t "Am Windows-PC als Netzlaufwerk verbinden: siehe docs/netzlaufwerk.md im Repository." \
		"To map it as a network drive on the Windows PC: see docs/network-drive.md in the repository."
	echo
}

manual_share() {
	local mnt path=$SHARE
	echo
	t "Beispiele:" "Examples:"
	echo
	echo "  \\\\nas\\$(t Freigabe share)\\$FOLDER      //192.168.1.10/$(t Freigabe share)/$FOLDER"
	while true; do
		ask path "$(t "Pfad zum Ordner" "Path to the folder")" "$path"
		path=${path//\\//}
		[ -s "$CONF_DIR/share-credentials" ] &&
			confirm "$(t "Gespeicherte Zugangsdaten verwenden?" "Use the saved credentials?")" y || ask_credentials
		mnt=$(mktemp -d)
		if share_mount "$path" "$mnt"; then
			umount "$mnt"; rmdir "$mnt"
			SHARE=$path
			echo "$(t "Ordner erreichbar" "Folder reachable"): $SHARE"
			return 0
		fi
		rmdir "$mnt"
		t "Der Ordner ist so nicht erreichbar (Pfad, Benutzer oder Passwort falsch?)." \
			"The folder can't be reached like this (wrong path, username or password?)."
		echo
		confirm "$(t "Nochmal versuchen?" "Try again?")" y || return 1
	done
}

# ------------------------------------------------------------------ install

install_pi() {
	need_root
	local user home answer app setup_tailscale=false
	user=${SUDO_USER:-$(getent passwd 1000 | cut -d: -f1)}
	if [ -z "$user" ] || [ "$user" = root ]; then
		echo "No regular user found (the Raspberry Pi Imager creates one)."
		exit 1
	fi
	home=$(getent passwd "$user" | cut -d: -f6)

	# Install folder: where it was installed last time, otherwise ./dropstopnshop
	# (in the user's home if we were started from / or root's home, which the browser can't read)
	app=$(installed_app)
	if [ -z "$app" ]; then
		case "$PWD" in
		/ | /root*) app=$home/dropstopnshop ;;
		*) app=$PWD/dropstopnshop ;;
		esac
	fi
	UI_LANG="" FOLDER="" SHARE="" SLIDE_SECONDS=12 RENDER_WIDTH=1920
	[ -r "$app/config" ] && . "$app/config"
	UI_LANG=${UI_LANG:-$(detect_lang)}

	step "DropStopNShop"
	ask answer "Sprache / Language (de/en)" "$UI_LANG"
	[[ ${answer,,} == de* ]] && UI_LANG=de || UI_LANG=en

	echo
	t "Das Setup richtet diesen Pi als Ladenanzeige ein. Es wird:" \
		"This setup turns this Pi into a shop display. It will:"
	echo
	t "  - das System aktualisieren und cage, Chromium, poppler-utils und cifs-utils installieren
  - den Installationsordner anlegen (Programm, Einstellungen, aufbereitete Folien)
  - zwei Dienste einrichten: Abgleich alle 3 Minuten und die Vollbild-Anzeige beim Einschalten
  - beim Start die Konsole statt eines Desktops starten (falls einer installiert ist)
  - die SD-Karte schonen: Logs nur im RAM, keine automatischen Updates, kein Swap
  - die Textmeldungen beim Start ausblenden" \
		"  - update the system and install cage, Chromium, poppler-utils and cifs-utils
  - create the install folder (program, settings, prepared slides)
  - set up two services: a sync every 3 minutes and the full-screen display at power-on
  - boot to the console instead of a desktop (if one is installed)
  - spare the SD card: logs in RAM only, no automatic updates, no swap
  - hide the text messages during boot"
	echo
	echo
	t "Rückgängig machen: sudo bash setup.sh --uninstall   Desktop zurück: sudo bash setup.sh --desktop" \
		"Undo: sudo bash setup.sh --uninstall   Desktop back: sudo bash setup.sh --desktop"
	echo
	confirm "$(t "Fortfahren?" "Continue?")" y || exit 0

	step "$(t Netzwerk Network)"
	setup_network

	step "$(t Einstellungen Settings)"
	ask app "$(t "Installationsordner" "Install folder")" "$app"
	app=$(realpath -m "${app/#\~/$home}")
	ask FOLDER "$(t "Name des Ordners mit den Inhalten" "Name of the folder with the content")" \
		"${FOLDER:-$(t Bildschirm Display)}"
	ask SLIDE_SECONDS "$(t "Sekunden pro Folie" "Seconds per slide")" "$SLIDE_SECONDS"
	[[ $SLIDE_SECONDS =~ ^[0-9]+$ ]] || SLIDE_SECONDS=12
	if ! command -v tailscale >/dev/null; then
		confirm "$(t "Tailscale für Fernwartung per SSH installieren?" "Install Tailscale for remote SSH maintenance?")" n &&
			setup_tailscale=true
	fi

	step "$(t Netzwerkordner "Network folder")"
	mkdir -p "$CONF_DIR"
	if ! command -v mount.cifs >/dev/null; then
		t "Installiere cifs-utils, um den Ordner prüfen zu können …" "Installing cifs-utils to check the folder …"
		echo
		apt-get -qq update && apt-get -qq -y install cifs-utils >/dev/null
	fi
	setup_share

	# ------------------------------------------------ packages
	step "$(t "System aktualisieren und Pakete installieren (dauert eine Weile)" "Updating the system and installing packages (takes a while)")"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get -y full-upgrade
	apt-get -y install cage poppler-utils cifs-utils
	apt-get -y install chromium || apt-get -y install chromium-browser

	# ------------------------------------------------ program
	step "$(t "Programm nach $app installieren" "Installing the program to $app")"
	write_files "$app"
	cat >"$app/config" <<EOF
# DropStopNShop settings – take effect with the next sync (within 3 minutes).
# Run "sudo bash $app/setup.sh" to change them interactively.
UI_LANG=$UI_LANG
# folder with the content (on the network share and on USB sticks)
FOLDER=$(printf '%q' "$FOLDER")
# network folder (SMB); empty = USB stick only. Credentials: $CONF_DIR/share-credentials
SHARE=$(printf '%q' "$SHARE")
# seconds per image or PDF page
SLIDE_SECONDS=$SLIDE_SECONDS
# width in pixels that PDF pages are rendered at (match the monitor)
RENDER_WIDTH=$RENDER_WIDTH
EOF
	# keep a copy so the setup can be run again later
	if [ -f "$SELF" ]; then
		[ "$(realpath "$SELF")" = "$app/setup.sh" ] || cp "$SELF" "$app/setup.sh"
	else
		curl -fsSL "$REPO_RAW/setup.sh" -o "$app/setup.sh" || true
	fi
	chown -R "$user:" "$app"
	mkdir -p "$app/data"  # written by the sync job as root
	echo "$app" >"$CONF_DIR/location"

	cat >/etc/systemd/system/dropstopnshop-sync.service <<EOF
[Unit]
Description=DropStopNShop: collect display content

[Service]
Type=oneshot
ExecStart="$app/dropstopnshop-sync"
TimeoutStartSec=20min
Nice=10
EOF
	cat >/etc/systemd/system/dropstopnshop-sync.timer <<EOF
[Unit]
Description=DropStopNShop: collect display content regularly

[Timer]
OnBootSec=20s
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target
EOF

	# ------------------------------------------------ start the display automatically
	step "$(t "Vollbild-Anzeige beim Einschalten starten" "Starting the full-screen display at power-on")"
	# Runs cage on tty1 in a real login session (that is what gives it access to screen and
	# input), as recommended by the cage project. Restarts it if it ever exits.
	cat >/etc/systemd/system/dropstopnshop-kiosk.service <<EOF
[Unit]
Description=DropStopNShop: full-screen slideshow
After=systemd-user-sessions.service plymouth-quit-wait.service
Wants=dbus.socket systemd-logind.service
After=dbus.socket systemd-logind.service
Conflicts=getty@tty1.service
After=getty@tty1.service

[Service]
User=$user
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
ExecStart="$app/kiosk.sh"
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable dropstopnshop-sync.timer dropstopnshop-kiosk.service
	# A desktop would take the screen instead; boot to the console (--desktop switches back)
	remember DEFAULT_TARGET "$(systemctl get-default)"
	if [ "$(systemctl get-default)" != multi-user.target ]; then
		systemctl set-default multi-user.target
	fi

	# ------------------------------------------------ spare the SD card (power is cut hard)
	step "$(t "Schreibzugriffe auf die SD-Karte minimieren" "Minimising writes to the SD card")"
	mkdir -p /etc/systemd/journald.conf.d
	cat >/etc/systemd/journald.conf.d/dropstopnshop.conf <<EOF
[Journal]
Storage=volatile
RuntimeMaxUse=30M
EOF
	# Updates by hand only (sudo apt update && sudo apt full-upgrade): a power cut in the
	# middle of an automatic update can break the system.
	systemctl disable --now apt-daily.timer apt-daily-upgrade.timer man-db.timer 2>/dev/null || true
	if systemctl is-enabled dphys-swapfile.service >/dev/null 2>&1; then
		remember SWAPFILE enabled
		systemctl disable --now dphys-swapfile.service || true
	fi

	# ------------------------------------------------ quiet boot without text output
	local cmdline=/boot/firmware/cmdline.txt config_txt=/boot/firmware/config.txt
	if [ -f "$cmdline" ] && ! grep -q logo.nologo "$cmdline"; then
		sed -i "1 s/\$/$QUIET_BOOT/" "$cmdline"
	fi
	if [ -f "$config_txt" ] && ! grep -q '^# dropstopnshop' "$config_txt"; then
		printf '# dropstopnshop\n[all]\ndisable_splash=1\n' >>"$config_txt"
	fi

	# ------------------------------------------------ remote maintenance
	if $setup_tailscale; then
		step "Tailscale"
		curl -fsSL https://tailscale.com/install.sh | sh
		tailscale up --ssh --hostname "$(hostname)"
	fi

	# ------------------------------------------------ first sync
	step "$(t "Erster Abgleich" "First sync")"
	"$app/dropstopnshop-sync" || true

	step "$(t Fertig Done)"
	t "Nach dem Neustart erscheint die Anzeige automatisch." "After the reboot the display starts automatically."
	echo
	echo "$(t Programm Program): $app"
	echo "$(t "Protokolle" "Logs"):  journalctl -u dropstopnshop-sync   journalctl -u dropstopnshop-kiosk"
	if confirm "$(t "Jetzt neu starten?" "Reboot now?")" y; then
		reboot
	fi
}

QUIET_BOOT=" quiet loglevel=3 logo.nologo vt.global_cursor_default=0"

# ------------------------------------------------------------------ desktop / uninstall

load_lang() {
	local app
	app=$(installed_app)
	UI_LANG=""
	[ -n "$app" ] && [ -r "$app/config" ] && UI_LANG=$(. "$app/config" && echo "${UI_LANG:-}")
	UI_LANG=${UI_LANG:-$(detect_lang)}
}

restore_desktop() {
	need_root --desktop
	load_lang
	if ! has_desktop; then
		t "Auf diesem Pi ist kein Desktop installiert (Raspberry Pi OS Lite)." \
			"There is no desktop installed on this Pi (Raspberry Pi OS Lite)."
		echo
		exit 1
	fi
	systemctl disable dropstopnshop-kiosk.service 2>/dev/null || true
	systemctl set-default graphical.target
	t "Nach dem Neustart startet wieder der Desktop. Der Abgleich läuft weiter.
Zurück zur Anzeige: das Setup erneut ausführen." \
		"After the reboot the desktop starts again. The sync keeps running.
Back to the display: run the setup again."
	echo
	confirm "$(t "Jetzt neu starten?" "Reboot now?")" y && reboot
	return 0
}

uninstall() {
	need_root --uninstall
	load_lang
	local app target swap
	app=$(installed_app)
	target=$(sed -n 's/^DEFAULT_TARGET=//p' "$CONF_DIR/before-install" 2>/dev/null)
	swap=$(sed -n 's/^SWAPFILE=//p' "$CONF_DIR/before-install" 2>/dev/null)

	step "$(t "DropStopNShop entfernen" "Removing DropStopNShop")"
	t "Entfernt die Dienste und macht die Systemänderungen rückgängig. Die Inhalte im Netzwerkordner und auf USB-Sticks bleiben unberührt." \
		"Removes the services and undoes the system changes. The content in the network folder and on USB sticks stays untouched."
	echo
	confirm "$(t "Fortfahren?" "Continue?")" n || exit 0

	systemctl disable --now dropstopnshop-kiosk.service dropstopnshop-sync.timer 2>/dev/null || true
	rm -f /etc/systemd/system/dropstopnshop-kiosk.service \
		/etc/systemd/system/dropstopnshop-sync.service /etc/systemd/system/dropstopnshop-sync.timer \
		/etc/systemd/journald.conf.d/dropstopnshop.conf
	systemctl daemon-reload
	systemctl enable apt-daily.timer apt-daily-upgrade.timer man-db.timer 2>/dev/null || true
	[ "$swap" = enabled ] && systemctl enable dphys-swapfile.service 2>/dev/null
	if [ -n "$target" ]; then
		systemctl set-default "$target"
	elif has_desktop; then
		systemctl set-default graphical.target
	fi
	[ -f /boot/firmware/cmdline.txt ] && sed -i "s/$QUIET_BOOT//" /boot/firmware/cmdline.txt
	[ -f /boot/firmware/config.txt ] && sed -i '/^# dropstopnshop$/,+2d' /boot/firmware/config.txt
	rm -rf "$CONF_DIR"
	echo "$(t "Dienste und Einstellungen entfernt." "Services and settings removed.")"

	if [ -n "$app" ] && [ -d "$app" ] &&
		confirm "$(t "Installationsordner $app löschen?" "Delete the install folder $app?")" n; then
		rm -rf "$app"
	fi
	if confirm "$(t "Das Paket cage wieder entfernen?" "Remove the cage package again?")" n; then
		apt-get -y remove cage
	fi
	command -v tailscale >/dev/null &&
		t "Tailscale bleibt installiert (entfernen: sudo apt remove tailscale)." \
			"Tailscale stays installed (remove it with: sudo apt remove tailscale)." && echo
	confirm "$(t "Jetzt neu starten?" "Reboot now?")" y && reboot
	return 0
}

check_status() {
	need_root --check
	load_lang
	local app ssid
	app=$(installed_app)
	if [ -z "$app" ] || ! grep -qs -- '--check' "$app/dropstopnshop-sync"; then
		t "DropStopNShop ist nicht (oder in einer älteren Version) installiert. Bitte das Setup ausführen." \
			"DropStopNShop is not installed (or an older version). Please run the setup."
		echo
		exit 1
	fi
	step "DropStopNShop – $(t Prüfung Check)"
	echo "$(t Installationsordner "Install folder"): $app"
	echo "$(t "Anzeige-Dienst" "Display service"): $(systemctl is-active dropstopnshop-kiosk.service)"
	echo "$(t "Abgleich alle 3 Minuten" "Sync every 3 minutes"): $(systemctl is-active dropstopnshop-sync.timer)"
	ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -n 1)
	[ -n "$ssid" ] && echo "WLAN: $ssid"
	echo "Internet: $(internet_ok && t ja yes || t nein no)"
	echo
	"$app/dropstopnshop-sync" --check
}

main() {
	case "${1:-}" in
	--check) check_status ;;
	--files-only)
		write_files "${2:?target directory missing}"
		echo "Files written to $2"
		;;
	--preview) preview "${2:-}" ;;
	--desktop) restore_desktop ;;
	--uninstall) uninstall ;;
	"") install_pi ;;
	*)
		sed -n '5,12p' "$SELF" 2>/dev/null || echo "Usage: sudo bash setup.sh [--uninstall | --desktop | --preview FOLDER]"
		exit 1
		;;
	esac
}

main "$@"
exit
