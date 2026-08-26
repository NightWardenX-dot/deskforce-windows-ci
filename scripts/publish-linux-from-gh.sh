#!/usr/bin/env bash
# Download DeskForce Linux .deb from a GH Actions run and publish.
# Usage: ./scripts/publish-linux-from-gh.sh [run_id]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${DOWNLOADS_DIR:-$ROOT/downloads}/linux"
REPO="${REPO:-NightWardenX-dot/deskforce-windows-ci}"
VER="${OEM_APP_VERSION:-1.2.0-beta.7}"
RUN_ID="${1:-}"

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(gh run list -R "$REPO" --workflow "oem-linux-flutter.yml" --limit 5 \
    --json databaseId,conclusion,status --jq '.[] | select(.conclusion=="success") | .databaseId' | head -1)"
fi
if [[ -z "$RUN_ID" ]]; then
  echo "No successful Linux run id." >&2
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
echo "Downloading artifact DeskForce-Linux-amd64..."
gh run download "$RUN_ID" -R "$REPO" -n DeskForce-Linux-amd64 -D "$TMP"

DEB="$(find "$TMP" -name 'DeskForce.deb' -type f | head -1)"
test -n "$DEB" && test -f "$DEB"
DEB_BYTES="$(wc -c < "$DEB")"
test "$DEB_BYTES" -gt 5000000

mkdir -p "$OUT"
if [[ -f "$OUT/DeskForce.deb" ]]; then
  mkdir -p "$OUT/archive"
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -f "$OUT/DeskForce.deb" "$OUT/archive/DeskForce.deb.$stamp" || true
fi

cp -f "$DEB" "$OUT/DeskForce.deb"
cp -f "$DEB" "$OUT/DeskForce-Linux-amd64.deb"
# Keep classic filename if present in artifact
ALT="$(find "$TMP" -name 'deskforce_1.0_amd64.deb' -type f | head -1)"
if [[ -n "$ALT" ]]; then
  cp -f "$ALT" "$OUT/deskforce_1.0_amd64.deb"
fi
chmod 644 "$OUT/DeskForce.deb" "$OUT/DeskForce-Linux-amd64.deb"

HEAD_SHA="$(gh run view "$RUN_ID" -R "$REPO" --json headSha --jq .headSha | cut -c1-7)"
NOW="$(date -Iseconds)"
python3 - <<PY
import json, pathlib
root = pathlib.Path("$ROOT/downloads")
path = root / "build-status-linux.json"
data = {}
if path.is_file():
    data = json.loads(path.read_text(encoding="utf-8"))
data.update({
    "platform": "linux",
    "version": "$VER",
    "client_version": "$VER",
    "building": False,
    "ready": True,
    "branded_published": True,
    "gh_run_id": "$RUN_ID",
    "head_sha": "$HEAD_SHA",
    "deb_bytes": $DEB_BYTES,
    "download": "https://deskforce.dr6ter.ru/downloads/linux/DeskForce.deb",
    "source": "$REPO artifact DeskForce-Linux-amd64 (run $RUN_ID)",
    "updated_at": "$NOW",
    "note": "Published Linux amd64 .deb $VER from $REPO run $RUN_ID.",
})
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

OEM_APP_VERSION_LINUX="$VER" "$ROOT/scripts/sync-client-update.sh" --publish

echo "Published Linux:"
ls -lh "$OUT/DeskForce.deb"
echo "Done. Run=$RUN_ID deb_bytes=$DEB_BYTES"
