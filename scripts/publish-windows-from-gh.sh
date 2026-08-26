#!/usr/bin/env bash
# Download DeskForce Windows paper/brass artifacts from a GH Actions run and publish.
# Usage:
#   ./scripts/publish-windows-from-gh.sh [run_id]
#   REPO=NightWardenX-dot/deskforce-windows-ci ./scripts/publish-windows-from-gh.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${DOWNLOADS_DIR:-$ROOT/downloads}/windows"
REPO="${REPO:-NightWardenX-dot/deskforce-windows-ci}"
VER="${OEM_APP_VERSION:-1.2.0-beta.7}"
RUN_ID="${1:-}"

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(gh run list -R "$REPO" --workflow "oem-windows-flutter.yml" --limit 1 \
    --json databaseId,conclusion,status --jq '.[] | select(.conclusion=="success") | .databaseId' | head -1)"
fi
if [[ -z "$RUN_ID" ]]; then
  echo "No successful run id. Pass run_id or wait for CI." >&2
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
echo "Downloading artifact DeskForce-Windows-paper-brass..."
gh run download "$RUN_ID" -R "$REPO" -n DeskForce-Windows-paper-brass -D "$TMP"

EXE="$(find "$TMP" -name 'DeskForce.exe' -type f | head -1)"
ZIP="$(find "$TMP" -name 'DeskForce-Windows-paper-brass.zip' -type f | head -1)"
test -n "$EXE" && test -f "$EXE"
test -n "$ZIP" && test -f "$ZIP"
EXE_BYTES="$(wc -c < "$EXE")"
ZIP_BYTES="$(wc -c < "$ZIP")"
test "$EXE_BYTES" -gt 10000000

mkdir -p "$OUT"
# Archive previous live EXE if present
if [[ -f "$OUT/DeskForce.exe" ]]; then
  mkdir -p "$OUT/archive"
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -f "$OUT/DeskForce.exe" "$OUT/archive/DeskForce.exe.$stamp" || true
  [[ -f "$OUT/DeskForce-Windows-paper-brass.zip" ]] && \
    cp -f "$OUT/DeskForce-Windows-paper-brass.zip" "$OUT/archive/DeskForce-Windows-paper-brass.zip.$stamp" || true
fi

cp -f "$EXE" "$OUT/DeskForce.exe"
cp -f "$ZIP" "$OUT/DeskForce-Windows-paper-brass.zip"
chmod 644 "$OUT/DeskForce.exe" "$OUT/DeskForce-Windows-paper-brass.zip"

HEAD_SHA="$(gh run view "$RUN_ID" -R "$REPO" --json headSha --jq .headSha | cut -c1-7)"
NOW="$(date -Iseconds)"
python3 - <<PY
import json, pathlib
root = pathlib.Path("$ROOT/downloads")
path = root / "build-status.json"
data = {}
if path.is_file():
    data = json.loads(path.read_text(encoding="utf-8"))
data.update({
    "platform": "windows",
    "version": "$VER",
    "client_version": "$VER",
    "building": False,
    "ready": True,
    "branded_published": True,
    "theme": "paper-brass-light",
    "blocked": None,
    "blocked_action": None,
    "gh_run_id": "$RUN_ID",
    "head_sha": "$HEAD_SHA",
    "exe_bytes": $EXE_BYTES,
    "zip_bytes": $ZIP_BYTES,
    "download": "https://deskforce.dr6ter.ru/downloads/windows/DeskForce.exe",
    "download_zip": "https://deskforce.dr6ter.ru/downloads/windows/DeskForce-Windows-paper-brass.zip",
    "update": "https://deskforce.dr6ter.ru/downloads/update.json",
    "source": "$REPO artifact DeskForce-Windows-paper-brass (run $RUN_ID)",
    "updated_at": "$NOW",
    "note": "Published Flutter paper/brass Windows $VER from public free CI mirror $REPO run $RUN_ID.",
    "next_action": None,
})
# drop nulls for cleaner JSON
data = {k: v for k, v in data.items() if v is not None}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

OEM_APP_VERSION_WINDOWS="$VER" "$ROOT/scripts/sync-client-update.sh" --publish

echo "Published:"
ls -lh "$OUT/DeskForce.exe" "$OUT/DeskForce-Windows-paper-brass.zip"
echo "Done. Run=$RUN_ID bytes exe=$EXE_BYTES zip=$ZIP_BYTES"
