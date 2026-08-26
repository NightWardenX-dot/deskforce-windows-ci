#!/usr/bin/env bash
# Download DeskForce Android APK from a GH Actions run and publish.
# Usage: ./scripts/publish-android-from-gh.sh [run_id]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${DOWNLOADS_DIR:-$ROOT/downloads}/android"
REPO="${REPO:-NightWardenX-dot/deskforce-windows-ci}"
VER="${OEM_APP_VERSION:-1.2.0-beta.7}"
RUN_ID="${1:-}"

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(gh run list -R "$REPO" --workflow "oem-android-flutter.yml" --limit 5 \
    --json databaseId,conclusion,status --jq '.[] | select(.conclusion=="success") | .databaseId' | head -1)"
fi
if [[ -z "$RUN_ID" ]]; then
  echo "No successful Android run id." >&2
  exit 1
fi

STATUS="$(gh run view "$RUN_ID" -R "$REPO" --json status,conclusion --jq '.status + "|" + (.conclusion//"")')"
echo "Run $RUN_ID ($REPO): $STATUS"
if [[ "$STATUS" != "completed|success" ]]; then
  echo "Run not successful yet." >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading artifact DeskForce-Android-arm64..."
gh run download "$RUN_ID" -R "$REPO" -n DeskForce-Android-arm64 -D "$TMP"

APK="$(find "$TMP" -name 'DeskForce.apk' -type f | head -1)"
if [[ -z "$APK" ]]; then
  APK="$(find "$TMP" -name '*.apk' -type f | head -1)"
fi
test -n "$APK" && test -f "$APK"
APK_BYTES="$(wc -c < "$APK")"
test "$APK_BYTES" -gt 1000000

mkdir -p "$OUT"
if [[ -f "$OUT/DeskForce.apk" ]]; then
  mkdir -p "$OUT/archive"
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -f "$OUT/DeskForce.apk" "$OUT/archive/DeskForce.apk.$stamp" || true
fi

cp -f "$APK" "$OUT/DeskForce.apk"
chmod 644 "$OUT/DeskForce.apk"
ZIP="$(find "$TMP" -name 'DeskForce-Android.zip' -type f | head -1)"
if [[ -n "$ZIP" && -f "$ZIP" ]]; then
  cp -f "$ZIP" "$OUT/DeskForce-Android.zip"
  chmod 644 "$OUT/DeskForce-Android.zip"
fi

HEAD_SHA="$(gh run view "$RUN_ID" -R "$REPO" --json headSha --jq .headSha | cut -c1-7)"
NOW="$(date -Iseconds)"
python3 - <<PY
import json, pathlib
root = pathlib.Path("$ROOT/downloads")
path = root / "build-status-android.json"
data = {}
if path.is_file():
    data = json.loads(path.read_text(encoding="utf-8"))
data.update({
    "platform": "android",
    "version": "$VER",
    "client_version": "$VER",
    "building": False,
    "ready": True,
    "branded_published": True,
    "gh_run_id": "$RUN_ID",
    "head_sha": "$HEAD_SHA",
    "apk_bytes": $APK_BYTES,
    "download": "https://deskforce.dr6ter.ru/downloads/android/DeskForce.apk",
    "source": "$REPO artifact DeskForce-Android-arm64 (run $RUN_ID)",
    "updated_at": "$NOW",
    "note": "Published Android $VER from $REPO run $RUN_ID.",
})
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

OEM_APP_VERSION_ANDROID="$VER" "$ROOT/scripts/sync-client-update.sh" --publish

echo "Published:"
ls -lh "$OUT/DeskForce.apk"
echo "Done. Run=$RUN_ID bytes apk=$APK_BYTES"
