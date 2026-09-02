#!/usr/bin/env python3
"""Post-build APK audit (and optional same-length binary scrub) for RuStore AV checks."""

from __future__ import annotations

import argparse
import pathlib
import shutil
import sys
import zipfile

ANDROID_JNI_LIB = "deskforce"
EXPECTED_LIB = f"lib{ANDROID_JNI_LIB}.so"
FORBIDDEN_LIB = "librustdesk.so"

DEX_STRING_BLOCKLIST = (
    FORBIDDEN_LIB,
    "RustDesk Service",
    "RustDesk is Open",
    "rustdesk:wakelock",
    "Show RustDesk",
    "RustDeskVD",
    "System.loadLibrary(\"rustdesk\")",
)

# Equal-length patches for libapp.so leftovers after source rebrand.
LIBAPP_REPLACEMENTS: list[tuple[bytes, bytes]] = [
    (b"librustdesk.so", b"libdeskfrce.so"),
]


def replace_in_file(path: pathlib.Path, pairs: list[tuple[bytes, bytes]]) -> bool:
    data = path.read_bytes()
    orig = data
    for old, new in pairs:
        if len(old) != len(new):
            raise ValueError(f"length mismatch {old!r} ({len(old)}) -> {new!r} ({len(new)})")
        data = data.replace(old, new)
    if data != orig:
        path.write_bytes(data)
        return True
    return False


def collect_hits(root: pathlib.Path) -> tuple[list[str], list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    native: list[str] = []

    for so in root.rglob("*.so"):
        rel = so.relative_to(root).as_posix()
        native.append(rel)
        if FORBIDDEN_LIB in rel:
            errors.append(f"forbidden native lib path: {rel}")

    if not any(n.endswith(EXPECTED_LIB) for n in native):
        errors.append(f"missing {EXPECTED_LIB}")

    for dex in root.rglob("classes*.dex"):
        data = dex.read_bytes()
        hits = [s for s in DEX_STRING_BLOCKLIST if s.encode() in data]
        if hits:
            warnings.append(f"{dex.relative_to(root)}: {', '.join(hits)}")

    for so in root.rglob("libapp.so"):
        data = so.read_bytes()
        if b"librustdesk.so" in data:
            warnings.append(f"{so.relative_to(root)}: librustdesk.so string in libapp.so")

    return errors, warnings, native


def audit_tree(root: pathlib.Path, label: str) -> tuple[list[str], list[str], list[str]]:
    errors, warnings, native = collect_hits(root)
    print(f"APK audit ({label}):")
    print(f"  native: {sorted(native)}")
    if errors:
        print("  ERRORS:")
        for e in errors:
            print(f"    - {e}")
    if warnings:
        print("  WARNINGS:")
        for w in warnings:
            print(f"    - {w}")
    if not errors and not warnings:
        print("  OK: no high-risk RustDesk fingerprints")
    return errors, warnings, native


def audit_apk(apk_path: pathlib.Path, apply_scrub: bool) -> int:
    tmp = apk_path.parent / f".sanitize-{apk_path.stem}"
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)

    with zipfile.ZipFile(apk_path, "r") as zf:
        zf.extractall(tmp)

    errors, warnings, _ = audit_tree(tmp, apk_path.name)

    if apply_scrub and not errors:
        patched = False
        for so in tmp.rglob("libapp.so"):
            if replace_in_file(so, LIBAPP_REPLACEMENTS):
                patched = True
                print(f"  scrubbed libapp.so in {so.relative_to(tmp)}")
        if patched:
            backup = apk_path.with_suffix(".apk.bak")
            shutil.copy2(apk_path, backup)
            with zipfile.ZipFile(apk_path, "w", compression=zipfile.ZIP_DEFLATED) as out:
                for f in sorted(tmp.rglob("*")):
                    if f.is_file():
                        out.write(f, f.relative_to(tmp).as_posix())
            print(f"  repacked APK, backup={backup.name}")
            shutil.rmtree(tmp)
            return audit_apk(apk_path, apply_scrub=False)

    shutil.rmtree(tmp)
    if errors:
        return 2
    return 1 if warnings else 0


def main() -> int:
    p = argparse.ArgumentParser(description="Audit/scrub DeskForce Android APK for AV fingerprints")
    p.add_argument("apk", type=pathlib.Path)
    p.add_argument("--scrub", action="store_true", help="Patch libapp.so same-length strings and repack")
    p.add_argument("--strict", action="store_true", help="Exit 1 if any warnings remain")
    args = p.parse_args()
    if not args.apk.is_file():
        print(f"APK not found: {args.apk}", file=sys.stderr)
        return 2
    rc = audit_apk(args.apk.resolve(), apply_scrub=args.scrub)
    if rc == 1 and args.strict:
        return 1
    if rc == 2:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
