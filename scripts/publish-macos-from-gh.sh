#!/usr/bin/env bash
# Download DeskForce macOS artifacts from a GH Actions run and publish.
# Usage: ./scripts/publish-macos-from-gh.sh [run_id]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${DOWNLOADS_DIR:-$ROOT/downloads}/macos"
REPO="${REPO:-NightWardenX-dot/deskforce-windows-ci}"
VER="${OEM_APP_VERSION:-1.2.0-beta.7}"
RUN_ID="${1:-}"

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(gh run list -R "$REPO" --workflow "oem-macos-flutter.yml" --limit 5 \
    --json databaseId,conclusion,status --jq '.[] | select(.conclusion=="success") | .databaseId' | head -1)"
fi
if [[ -z "$RUN_ID" ]]; then
  echo "No successful macOS run id." >&2
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
echo "Downloading artifact DeskForce-macOS..."
gh run download "$RUN_ID" -R "$REPO" -n DeskForce-macOS -D "$TMP"

DMG="$(find "$TMP" -name 'DeskForce.dmg' -type f | head -1)"
ZIP="$(find "$TMP" -name 'DeskForce-macOS.zip' -type f | head -1)"
test -n "$DMG" && test -f "$DMG"
DMG_BYTES="$(wc -c < "$DMG")"
test "$DMG_BYTES" -gt 10000000

mkdir -p "$OUT"
if [[ -f "$OUT/DeskForce.dmg" ]]; then
  mkdir -p "$OUT/archive"
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -f "$OUT/DeskForce.dmg" "$OUT/archive/DeskForce.dmg.$stamp" || true
  [[ -f "$OUT/DeskForce-macOS.zip" ]] && cp -f "$OUT/DeskForce-macOS.zip" "$OUT/archive/DeskForce-macOS.zip.$stamp" || true
fi

cp -f "$DMG" "$OUT/DeskForce.dmg"
chmod 644 "$OUT/DeskForce.dmg"
if [[ -n "$ZIP" && -f "$ZIP" ]]; then
  cp -f "$ZIP" "$OUT/DeskForce-macOS.zip"
  chmod 644 "$OUT/DeskForce-macOS.zip"
fi

HEAD_SHA="$(gh run view "$RUN_ID" -R "$REPO" --json headSha --jq .headSha | cut -c1-7)"
NOW="$(date -Iseconds)"
python3 - <<PY
import json, pathlib
root = pathlib.Path("$ROOT/downloads")
path = root / "build-status-macos.json"
data = {}
if path.is_file():
    data = json.loads(path.read_text(encoding="utf-8"))
data.update({
    "platform": "macos",
    "version": "$VER",
    "client_version": "$VER",
    "building": False,
    "ready": True,
    "branded_published": True,
    "unsigned": True,
    "gh_run_id": "$RUN_ID",
    "head_sha": "$HEAD_SHA",
    "dmg_bytes": $DMG_BYTES,
    "download": "https://deskforce.dr6ter.ru/downloads/macos/DeskForce.dmg",
    "download_zip": "https://deskforce.dr6ter.ru/downloads/macos/DeskForce-macOS.zip",
    "source": "$REPO artifact DeskForce-macOS (run $RUN_ID)",
    "updated_at": "$NOW",
    "note": "Published unsigned macOS $VER from $REPO run $RUN_ID.",
})
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

# Refresh update.json preserving other platform versions where possible
OEM_APP_VERSION_MACOS="$VER" "$ROOT/scripts/sync-client-update.sh" --publish

echo "Published macOS:"
ls -lh "$OUT/DeskForce.dmg" ${ZIP:+"$OUT/DeskForce-macOS.zip"} 2>/dev/null || ls -lh "$OUT/DeskForce.dmg"
echo "Done. Run=$RUN_ID dmg_bytes=$DMG_BYTES"
