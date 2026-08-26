#!/usr/bin/env bash
# Sync downloads/update.json (and optionally bump branded version) with live artifacts.
# Usage:
#   ./scripts/sync-client-update.sh                 # rewrite update.json from current files/env
#   OEM_APP_VERSION=1.2.0-beta.2 ./scripts/sync-client-update.sh
#   ./scripts/sync-client-update.sh --publish        # also copy to /www/wwwroot/rustdesk-panel/downloads/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${DOWNLOADS_DIR:-$ROOT/downloads}"
LIVE="${LIVE_DOWNLOADS_DIR:-/www/wwwroot/rustdesk-panel/downloads}"
BASE_URL="${OEM_API_SERVER:-https://deskforce.dr6ter.ru}"
VER="${OEM_APP_VERSION:-1.2.0-beta.7}"
# Optional per-platform overrides (preserve other platforms when publishing one OS)
VER_WIN="${OEM_APP_VERSION_WINDOWS:-$VER}"
VER_AND="${OEM_APP_VERSION_ANDROID:-$VER}"
VER_LIN="${OEM_APP_VERSION_LINUX:-$VER}"
VER_MAC="${OEM_APP_VERSION_MACOS:-$VER}"
# If update.json already exists and an override env was NOT set, keep prior platform version
if [[ -f "$OUT/update.json" ]]; then
  _prev() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('platforms',{}).get(sys.argv[2],{}).get('version',''))" "$OUT/update.json" "$1" 2>/dev/null || true; }
  if [[ -z "${OEM_APP_VERSION_WINDOWS:-}" ]]; then
    _v="$(_prev windows)"; [[ -n "$_v" ]] && VER_WIN="$_v"
  fi
  if [[ -z "${OEM_APP_VERSION_ANDROID:-}" ]]; then
    _v="$(_prev android)"; [[ -n "$_v" ]] && VER_AND="$_v"
  fi
  if [[ -z "${OEM_APP_VERSION_LINUX:-}" ]]; then
    _v="$(_prev linux)"; [[ -n "$_v" ]] && VER_LIN="$_v"
  fi
  if [[ -z "${OEM_APP_VERSION_MACOS:-}" ]]; then
    _v="$(_prev macos)"; [[ -n "$_v" ]] && VER_MAC="$_v"
  fi
  # If OEM_APP_VERSION was explicitly set without per-OS overrides, bump all to VER
  if [[ -n "${OEM_APP_VERSION:-}" && -z "${OEM_APP_VERSION_WINDOWS:-}${OEM_APP_VERSION_ANDROID:-}${OEM_APP_VERSION_LINUX:-}${OEM_APP_VERSION_MACOS:-}" ]]; then
    VER_WIN="$VER"; VER_AND="$VER"; VER_LIN="$VER"; VER_MAC="$VER"
  fi
fi
NOTES_WIN="${UPDATE_NOTES_WIN:-Актуальная сборка DeskForce для Windows (тема paper/brass). Один файл DeskForce.exe — скачайте и запустите.}"
NOTES_AND="${UPDATE_NOTES_ANDROID:-Актуальная сборка DeskForce для Android.}"
NOTES_LIN="${UPDATE_NOTES_LINUX:-Актуальная сборка DeskForce для Linux (amd64 .deb).}"
NOTES_MAC="${UPDATE_NOTES_MACOS:-macOS-сборка DeskForce (unsigned DMG для Apple Silicon). Подпись Apple не включена — при первом запуске ПКМ → Открыть или xattr -cr.}"
PUBLISH=0
for a in "$@"; do
  case "$a" in
    --publish) PUBLISH=1 ;;
  esac
done

now="$(date -Iseconds)"
win_exe="${BASE_URL}/downloads/windows/DeskForce.exe"
win_zip="${BASE_URL}/downloads/windows/DeskForce-Windows-paper-brass.zip"
# Prefer paper-brass zip name if present; else x64 zip
if [[ -f "$OUT/windows/DeskForce-Windows-x64.zip" && ! -f "$OUT/windows/DeskForce-Windows-paper-brass.zip" ]]; then
  win_zip="${BASE_URL}/downloads/windows/DeskForce-Windows-x64.zip"
fi
apk_url="${BASE_URL}/downloads/android/DeskForce.apk"
apk_zip="${BASE_URL}/downloads/android/DeskForce-Android.zip"

linux_available=false
linux_url=""
linux_urls="{}"
if [[ -f "$OUT/linux/DeskForce.deb" ]]; then
  linux_available=true
  linux_url="${BASE_URL}/downloads/linux/DeskForce.deb"
  linux_urls=$(printf '{"deb":"%s"}' "$linux_url")
elif [[ -f "$OUT/linux/DeskForce.AppImage" ]]; then
  linux_available=true
  linux_url="${BASE_URL}/downloads/linux/DeskForce.AppImage"
  linux_urls=$(printf '{"appimage":"%s"}' "$linux_url")
fi

macos_available=false
macos_url=""
macos_urls="{}"
if [[ -f "$OUT/macos/DeskForce.dmg" ]]; then
  macos_available=true
  macos_url="${BASE_URL}/downloads/macos/DeskForce.dmg"
  if [[ -f "$OUT/macos/DeskForce-macOS.zip" ]]; then
    macos_urls=$(printf '{"dmg":"%s","zip":"%s"}' "$macos_url" "${BASE_URL}/downloads/macos/DeskForce-macOS.zip")
  else
    macos_urls=$(printf '{"dmg":"%s"}' "$macos_url")
  fi
elif [[ -f "$OUT/macos/DeskForce-macOS.zip" ]]; then
  macos_available=true
  macos_url="${BASE_URL}/downloads/macos/DeskForce-macOS.zip"
  macos_urls=$(printf '{"zip":"%s"}' "$macos_url")
fi

android_available=false
[[ -f "$OUT/android/DeskForce.apk" || -f "$LIVE/android/DeskForce.apk" ]] && android_available=true

win_available=false
[[ -f "$OUT/windows/DeskForce.exe" || -f "$LIVE/windows/DeskForce.exe" ]] && win_available=true

mkdir -p "$OUT"
cat > "$OUT/update.json" <<JSON
{
  "app": "DeskForce",
  "channel": "stable",
  "updated_at": "$now",
  "platforms": {
    "windows": {
      "platform": "windows",
      "version": "$VER_WIN",
      "mandatory": false,
      "download_url": "$win_exe",
      "download_urls": {
        "exe": "$win_exe"
      },
      "release_notes": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NOTES_WIN"),
      "available": $win_available
    },
    "android": {
      "platform": "android",
      "version": "$VER_AND",
      "mandatory": false,
      "download_url": "$apk_url",
      "download_urls": {
        "apk": "$apk_url",
        "zip": "$apk_zip"
      },
      "release_notes": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NOTES_AND"),
      "available": $android_available
    },
    "linux": {
      "platform": "linux",
      "version": "$VER_LIN",
      "mandatory": false,
      "download_url": "$linux_url",
      "download_urls": $linux_urls,
      "release_notes": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NOTES_LIN"),
      "available": $linux_available
    },
    "macos": {
      "platform": "macos",
      "version": "$VER_MAC",
      "mandatory": false,
      "download_url": "$macos_url",
      "download_urls": $macos_urls,
      "release_notes": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NOTES_MAC"),
      "available": $macos_available
    }
  }
}
JSON

# Keep branded client_version on sibling status files without rewriting whole documents blindly.
python3 - <<'PY' "$OUT" "$VER_WIN" "$VER_AND" "$VER_LIN" "$VER_MAC" "$now" "$win_exe" "$win_zip"
import json, sys, pathlib
out, ver_win, ver_and, ver_lin, ver_mac, now, win_exe, win_zip = sys.argv[1:9]
ver = ver_win  # manifest / windows build-status primary
root = pathlib.Path(out)

def patch(path, **fields):
    p = root / path
    if not p.is_file():
        return
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return
    data.update(fields)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Patched {p}")

patch(
    "manifest.json",
    client_version=ver,
    update_channel="update.json",
)
patch(
    "build-status.json",
    client_version=ver,
    update="https://deskforce.dr6ter.ru/downloads/update.json",
    download=win_exe,
    download_zip=win_zip,
)
patch(
    "build-status-android.json",
    client_version=ver,
    update="https://deskforce.dr6ter.ru/downloads/update.json",
)
print(f"Wrote {root / 'update.json'} win={ver_win} and={ver_and} lin={ver_lin} mac={ver_mac}")
PY

if [[ "$PUBLISH" -eq 1 ]]; then
  if [[ -d "$LIVE" ]]; then
    # LIVE may be a symlink to OUT — skip no-op copies
    live_real="$(readlink -f "$LIVE" 2>/dev/null || echo "$LIVE")"
    out_real="$(readlink -f "$OUT" 2>/dev/null || echo "$OUT")"
    if [[ "$live_real" != "$out_real" ]]; then
      cp -f "$OUT/update.json" "$LIVE/update.json"
      [[ -f "$OUT/manifest.json" ]] && cp -f "$OUT/manifest.json" "$LIVE/manifest.json"
      [[ -f "$OUT/build-status.json" ]] && cp -f "$OUT/build-status.json" "$LIVE/build-status.json"
      [[ -f "$OUT/build-status-android.json" ]] && cp -f "$OUT/build-status-android.json" "$LIVE/build-status-android.json"
      echo "Published update channel -> $LIVE"
    else
      echo "Live downloads dir is symlink to OUT; update.json already live at $OUT"
    fi
  else
    echo "WARN: live dir missing: $LIVE" >&2
  fi
fi
