#!/usr/bin/env python3
"""Apply DeskForce OEM branding into a RustDesk source tree (idempotent)."""

from __future__ import annotations

import os
import pathlib
import re
import shutil
import sys

OEM_BEGIN = "// DESKFORCE_OEM_BEGIN"
OEM_END = "// DESKFORCE_OEM_END"


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def copy_branding_fixed(src: pathlib.Path, branding: pathlib.Path) -> None:
    mapping = [
        (
            "app_icon.png",
            [
                "res/128x128.png",
                "res/icon.png",
                "flutter/assets/icon.png",
            ],
        ),
        ("app_logo.png", ["res/logo.png", "flutter/assets/logo.png"]),
        (
            "app_icon.ico",
            [
                "res/icon.ico",
                # Windows window/taskbar: Flutter runner embeds this via Runner.rc
                "flutter/windows/runner/resources/app_icon.ico",
                # Prefer custom icon over stock Runner icon (win32_window.cpp)
                "flutter/assets/icon.ico",
            ],
        ),
        ("tray-icon.ico", ["res/tray-icon.ico"]),
        ("app_icon.svg", ["flutter/assets/icon.svg"]),
        ("app_icon.icns", ["res/mac-icon.icns", "res/icon.icns"]),
    ]
    for name, dests in mapping:
        f = branding / name
        if not f.is_file():
            # tray fallback: reuse app icon ico if dedicated tray missing
            if name == "tray-icon.ico" and (branding / "app_icon.ico").is_file():
                f = branding / "app_icon.ico"
            else:
                continue
        for rel in dests:
            dest = src / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copy2(f, dest)
                print(f"Copied branding {name} -> {rel}")
            except OSError as e:
                print(f"skip {rel}: {e}")
    copy_android_launcher_icons(src, branding)


def copy_android_launcher_icons(src: pathlib.Path, branding: pathlib.Path) -> None:
    """Resize DeskForce D-mark into every Android mipmap / adaptive layer.

    Stock RustDesk keeps adaptive foregrounds per-density; copying only
    mipmap-xxxhdpi/ic_launcher.png leaves the launcher on the P-mark icon.
    """
    try:
        from PIL import Image
    except ImportError:
        print("WARN: Pillow missing — Android launcher icons not resized", file=sys.stderr)
        return

    master_path = branding / "adaptive_icon.png"
    if not master_path.is_file():
        master_path = branding / "app_icon.png"
    if not master_path.is_file():
        print("WARN: no adaptive/app icon for Android mipmaps", file=sys.stderr)
        return

    master = Image.open(master_path).convert("RGBA")
    # density -> (launcher, round, foreground, notification)
    sizes = {
        "mipmap-mdpi": (48, 48, 108, 24),
        "mipmap-hdpi": (72, 72, 162, 36),
        "mipmap-xhdpi": (96, 96, 216, 48),
        "mipmap-xxhdpi": (144, 144, 324, 72),
        "mipmap-xxxhdpi": (192, 192, 432, 96),
    }
    res = src / "flutter" / "android" / "app" / "src" / "main" / "res"
    written = 0
    for folder, (launcher, round_sz, fg, stat) in sizes.items():
        dest_dir = res / folder
        if not dest_dir.is_dir():
            dest_dir.mkdir(parents=True, exist_ok=True)
        for name, size in (
            ("ic_launcher.png", launcher),
            ("ic_launcher_round.png", round_sz),
            ("ic_launcher_foreground.png", fg),
            ("ic_stat_logo.png", stat),
        ):
            out = dest_dir / name
            master.resize((size, size), Image.Resampling.LANCZOS).save(out, format="PNG")
            written += 1
            print(f"Copied branding android {folder}/{name} ({size}x{size})")

    # Paper background behind adaptive icon (API 26+)
    bg_xml = res / "values" / "ic_launcher_background.xml"
    bg_xml.parent.mkdir(parents=True, exist_ok=True)
    bg_xml.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#f3efe6</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print(f"Patched: Android adaptive background #f3efe6 ({written} mipmap PNGs)")

def copy_ui_overrides(src: pathlib.Path, root: pathlib.Path) -> None:
    """Station-console Flutter pages (not stock RustDesk two-column home)."""
    overrides = root / "overrides"
    if not overrides.is_dir():
        print("WARN: oem/overrides missing — station UI not applied", file=sys.stderr)
        return
    for path in overrides.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(overrides)
        dest = src / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        print(f"Copied UI override -> {rel}")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if new in text:
            print(f"OK already: {label}")
            return text
        print(f"WARN missing pattern for {label}", file=sys.stderr)
        return text
    print(f"Patched: {label}")
    return text.replace(old, new, 1)


def upsert_block(text: str, begin: str, end: str, block: str) -> str:
    body = f"{begin}\n{block.rstrip()}\n{end}"
    if begin in text and end in text:
        start = text.index(begin)
        stop = text.index(end) + len(end)
        return text[:start] + body + text[stop:]
    return text.rstrip() + "\n\n" + body + "\n"


def patch_config_rs(src: pathlib.Path, app_name: str, id_server: str, key_pub: str) -> None:
    path = src / "libs" / "hbb_common" / "src" / "config.rs"
    if not path.is_file():
        print("WARN: hbb_common/config.rs missing — run git submodule update --init", file=sys.stderr)
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    text = replace_once(
        text,
        'pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new("".to_owned());',
        f'pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new("{id_server}".to_owned());',
        "PROD_RENDEZVOUS_SERVER",
    )
    # already DeskForce?
    text = replace_once(
        text,
        'pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());',
        f'pub static ref APP_NAME: RwLock<String> = RwLock::new("{app_name}".to_owned());',
        "APP_NAME",
    )
    if f'RwLock::new("{app_name}".to_owned())' not in text and "APP_NAME" in text:
        text = re.sub(
            r'pub static ref APP_NAME: RwLock<String> = RwLock::new\("[^"]*"\.to_owned\(\)\);',
            f'pub static ref APP_NAME: RwLock<String> = RwLock::new("{app_name}".to_owned());',
            text,
            count=1,
        )
        print("Patched: APP_NAME (regex)")
    text = re.sub(
        r'pub const RS_PUB_KEY: &str = "[^"]*";',
        f'pub const RS_PUB_KEY: &str = "{key_pub}";',
        text,
        count=1,
    )
    print("Patched: RS_PUB_KEY")
    # Never fall back to rs-ny.rustdesk.com
    text2 = re.sub(
        r'pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[[^\]]*\];',
        f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{id_server}"];',
        text,
        count=1,
    )
    if text2 != text:
        text = text2
        print("Patched: RENDEZVOUS_SERVERS -> DeskForce")
    else:
        print("WARN: RENDEZVOUS_SERVERS pattern miss", file=sys.stderr)
    # Docs links -> DeskForce guide
    text = text.replace(
        'pub const LINK_DOCS_HOME: &str = "https://rustdesk.com/docs/en/";',
        'pub const LINK_DOCS_HOME: &str = "https://deskforce.dr6ter.ru/guide";',
    )
    text = text.replace(
        'pub const LINK_DOCS_X11_REQUIRED: &str = "https://rustdesk.com/docs/en/manual/linux/#x11-required";',
        'pub const LINK_DOCS_X11_REQUIRED: &str = "https://deskforce.dr6ter.ru/guide";',
    )
    path.write_text(text, encoding="utf-8")


def patch_common_rs(
    src: pathlib.Path,
    app_name: str,
    id_server: str,
    relay: str,
    api: str,
    key_pub: str,
) -> None:
    path = src / "src" / "common.rs"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    block = f"""// OEM defaults injected by DeskForce apply_branding.py
pub const DESKFORCE_ID_SERVER: &str = "{id_server}";
pub const DESKFORCE_RELAY_SERVER: &str = "{relay}";
pub const DESKFORCE_API_SERVER: &str = "{api}";
pub const DESKFORCE_KEY: &str = "{key_pub}";

/// Seed overwrite/builtin maps so servers and UI cuts are locked in the binary.
pub fn apply_deskforce_oem() {{
    use hbb_common::config::{{
        APP_NAME, BUILTIN_SETTINGS, DEFAULT_LOCAL_SETTINGS, DEFAULT_SETTINGS, HARD_SETTINGS,
        OVERWRITE_LOCAL_SETTINGS, OVERWRITE_SETTINGS, PROD_RENDEZVOUS_SERVER,
    }};
    *APP_NAME.write().unwrap() = "{app_name}".to_owned();
    *PROD_RENDEZVOUS_SERVER.write().unwrap() = DESKFORCE_ID_SERVER.to_owned();

    let mut ow = OVERWRITE_SETTINGS.write().unwrap();
    ow.insert("custom-rendezvous-server".into(), DESKFORCE_ID_SERVER.into());
    ow.insert("relay-server".into(), DESKFORCE_RELAY_SERVER.into());
    ow.insert("api-server".into(), DESKFORCE_API_SERVER.into());
    ow.insert("key".into(), DESKFORCE_KEY.into());
    // Lock update-check off — stock Flutter still queries api.rustdesk.com otherwise.
    ow.insert("enable-check-update".into(), "N".into());
    drop(ow);

    let mut def = DEFAULT_SETTINGS.write().unwrap();
    def.insert("custom-rendezvous-server".into(), DESKFORCE_ID_SERVER.into());
    def.insert("relay-server".into(), DESKFORCE_RELAY_SERVER.into());
    def.insert("api-server".into(), DESKFORCE_API_SERVER.into());
    def.insert("key".into(), DESKFORCE_KEY.into());
    drop(def);

    let mut bi = BUILTIN_SETTINGS.write().unwrap();
    bi.insert("hide-network-settings".into(), "Y".into());
    bi.insert("hide-server-settings".into(), "Y".into());
    bi.insert("hide-proxy-settings".into(), "Y".into());
    bi.insert("hide-websocket-settings".into(), "Y".into());
    bi.insert("allow-remote-config-modification".into(), "N".into());
    bi.insert("hide-powered-by-me".into(), "Y".into());
    bi.insert("enable-check-update".into(), "N".into());
    // DeskForce: never show stock RustDesk pink/gray help/install cards.
    bi.insert("hide-help-cards".into(), "Y".into());
    drop(bi);

    let mut hard = HARD_SETTINGS.write().unwrap();
    hard.insert("disable-ab".into(), "Y".into());
    hard.insert("disable-account".into(), "Y".into());
    // Portable EXE: skip stock "Install" tip when service not registered.
    hard.insert("disable-installation".into(), "Y".into());
    // Keep servers locked — UI cannot point client at RustDesk public cloud.
    hard.insert("custom-rendezvous-server".into(), DESKFORCE_ID_SERVER.into());
    hard.insert("relay-server".into(), DESKFORCE_RELAY_SERVER.into());
    hard.insert("api-server".into(), DESKFORCE_API_SERVER.into());
    hard.insert("key".into(), DESKFORCE_KEY.into());
    hard.insert("enable-check-update".into(), "N".into());
    drop(hard);

    let mut loc = DEFAULT_LOCAL_SETTINGS.write().unwrap();
    loc.insert("disable-discovery-panel".into(), "Y".into());
    loc.insert("disable-group-panel".into(), "Y".into());
    loc.insert("theme".into(), "light".into());
    loc.insert("enable-check-update".into(), "N".into());
    // Default: expand window on launch (user can turn off in settings).
    loc.insert("df-start-fullscreen".into(), "Y".into());
    drop(loc);

    let mut oloc = OVERWRITE_LOCAL_SETTINGS.write().unwrap();
    oloc.insert("theme".into(), "light".into());
    oloc.insert("disable-discovery-panel".into(), "Y".into());
    oloc.insert("enable-check-update".into(), "N".into());
    drop(oloc);
}}
"""
    text = upsert_block(text, OEM_BEGIN, OEM_END, block)
    # Never fall back to https://admin.rustdesk.com
    text2 = text.replace(
        '"https://admin.rustdesk.com".to_owned()',
        f'DESKFORCE_API_SERVER.to_owned()',
    )
    if text2 == text:
        text2 = re.sub(
            r'return\s+"https://admin\.rustdesk\.com"\.to_owned\(\);',
            'return DESKFORCE_API_SERVER.to_owned();',
            text,
            count=1,
        )
    if text2 != text:
        text = text2
        print("Patched: get_api_server_ fallback -> DeskForce API")
    # using_public_server: with locked custom server this is false; still harden empty-check
    path.write_text(text, encoding="utf-8")
    print(f"Wrote OEM block in {path}")


def patch_flutter_ffi(src: pathlib.Path) -> None:
    path = src / "src" / "flutter_ffi.rs"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    needle = """    if custom_client_config.is_empty() {
        crate::load_custom_client();
    } else {
        crate::read_custom_client(custom_client_config);
    }
"""
    insert = needle + "    crate::common::apply_deskforce_oem();\n"
    if "apply_deskforce_oem" in text:
        print("OK already: flutter_ffi apply_deskforce_oem")
        return
    if needle not in text:
        print("WARN: flutter_ffi initialize hook not found", file=sys.stderr)
        return
    path.write_text(text.replace(needle, insert, 1), encoding="utf-8")
    print("Patched: flutter_ffi initialize -> apply_deskforce_oem")


def patch_platform_names(src: pathlib.Path, app_name: str) -> None:
    replacements = [
        (
            src / "flutter" / "android" / "app" / "src" / "main" / "res" / "values" / "strings.xml",
            [
                ('<string name="app_name">RustDesk</string>', f'<string name="app_name">{app_name}</string>'),
                (
                    "when RustDesk screen sharing is established",
                    f"when {app_name} screen sharing is established",
                ),
            ],
        ),
        (
            src / "flutter" / "android" / "app" / "src" / "main" / "AndroidManifest.xml",
            [
                ('android:label="RustDesk"', f'android:label="{app_name}"'),
                ('android:label="RustDesk Input"', f'android:label="{app_name} Input"'),
            ],
        ),
        (
            src / "flutter" / "windows" / "runner" / "Runner.rc",
            [
                ('VALUE "CompanyName", "Purslane Ltd"', f'VALUE "CompanyName", "{app_name}"'),
                ('VALUE "FileDescription", "RustDesk Remote Desktop"', f'VALUE "FileDescription", "{app_name} Remote Desktop"'),
                ('VALUE "ProductName", "RustDesk"', f'VALUE "ProductName", "{app_name}"'),
                ('VALUE "InternalName", "rustdesk"', f'VALUE "InternalName", "{app_name}"'),
                ('VALUE "InternalName", "RustDesk"', f'VALUE "InternalName", "{app_name}"'),
                (
                    'VALUE "LegalCopyright", "Copyright © 2025 Purslane Ltd. All rights reserved."',
                    f'VALUE "LegalCopyright", "Copyright © 2026 {app_name}. All rights reserved."',
                ),
                ('VALUE "OriginalFilename", "rustdesk.exe"', f'VALUE "OriginalFilename", "{app_name}.exe"'),
                ('VALUE "OriginalFilename", "RustDesk.exe"', f'VALUE "OriginalFilename", "{app_name}.exe"'),
            ],
        ),
    ]
    for path, pairs in replacements:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for old, new in pairs:
            if old in text:
                text = text.replace(old, new)
                print(f"Patched name in {path.name}")
            elif new in text:
                print(f"OK already name in {path.name}")
        # Catch leftover Purslane / RustDesk product strings
        text2 = re.sub(
            r'VALUE "CompanyName", "[^"]*"',
            f'VALUE "CompanyName", "{app_name}"',
            text,
            count=1,
        )
        text2 = re.sub(
            r'VALUE "LegalCopyright", "[^"]*"',
            f'VALUE "LegalCopyright", "Copyright © 2026 {app_name}. All rights reserved."',
            text2,
            count=1,
        )
        if text2 != text:
            text = text2
            print(f"Patched CompanyName/LegalCopyright in {path.name}")
        path.write_text(text, encoding="utf-8")

    pubspec = src / "flutter" / "pubspec.yaml"
    if pubspec.is_file():
        text = pubspec.read_text(encoding="utf-8", errors="ignore")
        lines = []
        for line in text.splitlines():
            if line.startswith("description:"):
                lines.append(f'description: "{app_name} remote desktop"')
            else:
                lines.append(line)
        pubspec.write_text("\n".join(lines) + "\n", encoding="utf-8")

    portable = src / "libs" / "portable" / "Cargo.toml"
    if portable.is_file():
        text = portable.read_text(encoding="utf-8", errors="ignore")
        pairs = [
            ('description = "RustDesk Remote Desktop"', f'description = "{app_name} Remote Desktop"'),
            ('ProductName = "RustDesk"', f'ProductName = "{app_name}"'),
            ('FileDescription = "RustDesk Remote Desktop"', f'FileDescription = "{app_name} Remote Desktop"'),
            ('OriginalFilename = "rustdesk.exe"', f'OriginalFilename = "{app_name}.exe"'),
            (
                'LegalCopyright = "Copyright © 2025 Purslane Ltd. All rights reserved."',
                f'LegalCopyright = "Copyright © 2026 {app_name}. All rights reserved."',
            ),
        ]
        for old, new in pairs:
            if old in text:
                text = text.replace(old, new)
                print(f"Patched portable Cargo.toml: {old.split('=')[0].strip()}")
        text = re.sub(
            r'LegalCopyright = "[^"]*"',
            f'LegalCopyright = "Copyright © 2026 {app_name}. All rights reserved."',
            text,
            count=1,
        )
        portable.write_text(text, encoding="utf-8")

    patch_android_application_id(src)
    patch_android_stock_blues(src)
    patch_mobile_branding(src, app_name)
    patch_mobile_connection_page(src, app_name)


def patch_android_application_id(src: pathlib.Path) -> None:
    """Sideload package id — not com.carriez.flutter_hbb / RustDesk Play listing."""
    gradle = src / "flutter" / "android" / "app" / "build.gradle"
    if not gradle.is_file():
        return
    text = gradle.read_text(encoding="utf-8", errors="ignore")
    text2 = re.sub(
        r'applicationId\s+"[^"]+"',
        'applicationId "ru.deskforce.ud"',
        text,
        count=1,
    )
    if text2 != text:
        gradle.write_text(text2, encoding="utf-8")
        print("Patched: applicationId ru.deskforce.ud")
    elif 'applicationId "ru.deskforce.ud"' in text:
        print("OK already: applicationId ru.deskforce.ud")
    else:
        print("WARN: applicationId pattern miss", file=sys.stderr)


def patch_android_stock_blues(src: pathlib.Path) -> None:
    """Replace hardcoded Material blue on mobile pages with DeskForce brass."""
    targets = [
        src / "flutter" / "lib" / "mobile" / "pages" / "server_page.dart",
        src / "flutter" / "lib" / "mobile" / "pages" / "settings_page.dart",
        src / "flutter" / "lib" / "mobile" / "pages" / "home_page.dart",
    ]
    for path in targets:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        text2 = text.replace("Colors.blueAccent", "MyTheme.accent")
        text2 = text2.replace("Colors.blue,", "MyTheme.accent,")
        text2 = text2.replace("backgroundColor: Colors.blue", "backgroundColor: MyTheme.accent")
        if text2 != text:
            path.write_text(text2, encoding="utf-8")
            print(f"Patched stock blues in {path.name}")


def patch_disable_stock_update_check(src: pathlib.Path) -> None:
    """Never hit api.rustdesk.com / pink Play-style update banners.

    DeskForce uses deskforce_update.dart against deskforce.dr6ter.ru instead.
    """
    common = src / "flutter" / "lib" / "common.dart"
    if common.is_file():
        text = common.read_text(encoding="utf-8", errors="ignore")
        if "DeskForce: never stock RustDesk update check" in text:
            print("OK already: checkUpdate disabled")
        else:
            new = """void checkUpdate() {
  // DeskForce: never stock RustDesk update check (api.rustdesk.com / Play).
  // Mobile/desktop use deskforce_update.dart → deskforce.dr6ter.ru/update.json.
  return;
}"""
            text2, n = re.subn(
                r"void checkUpdate\(\) \{[\s\S]*?\n\}",
                new.rstrip(),
                text,
                count=1,
            )
            if n:
                common.write_text(text2, encoding="utf-8")
                print("Patched: checkUpdate no-op")
            else:
                print("WARN: checkUpdate not patched", file=sys.stderr)

    for rel in (
        "flutter/lib/mobile/pages/settings_page.dart",
        "flutter/lib/desktop/pages/desktop_setting_page.dart",
    ):
        path = src / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if "rustdesk.com" in text.lower():
            text2 = re.sub(
                r"https?://([a-z0-9.-]*\.)?rustdesk\.com[^'\"\s]*",
                "https://deskforce.dr6ter.ru/downloads/",
                text,
                flags=re.I,
            )
            if text2 != text:
                path.write_text(text2, encoding="utf-8")
                print(f"Patched rustdesk.com links in {path.name}")


def patch_peer_tabs(src: pathlib.Path) -> None:
    path = src / "flutter" / "lib" / "models" / "peer_tab_model.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    new_enabled = """  List<bool> isEnabled = List.from([
    false, // recent — DeskForce simplified UI
    false, // favorites
    false, // discovered / LAN
    false, // address book
    false, // accessible devices / group
  ]);"""
    text2 = re.sub(
        r"  List<bool> isEnabled = List\.from\(\[[\s\S]*?\]\);",
        new_enabled,
        text,
        count=1,
    )
    if text2 == text:
        print("WARN: peer_tab isEnabled not patched", file=sys.stderr)
    else:
        print("Patched: peer_tab_model isEnabled (all hidden)")
        path.write_text(text2, encoding="utf-8")


def patch_about_dialog(src: pathlib.Path, app_name: str, api: str) -> None:
    """DeskForce-only About: no RustDesk.com / Purslane / stock slogan chrome."""
    path = src / "flutter" / "lib" / "desktop" / "pages" / "desktop_setting_page.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    base = api.rstrip("/")
    year = "2026"

    # Title
    text = text.replace(
        "child: _Card(title: translate('About RustDesk'), children: [",
        f"child: _Card(title: 'О {app_name} УД', children: [",
    )
    text = text.replace(
        "child: _Card(title: 'О DeskForce УД', children: [",
        f"child: _Card(title: 'О {app_name} УД', children: [",
    )

    # Links → DeskForce cabinet / site (replace any leftover hosts)
    for old_host in (
        "https://rustdesk.com/privacy.html",
        "https://rustdesk.com",
        "https://rustdesk.dr6ter.ru/cabinet/?embed=1",
        "https://rustdesk.dr6ter.ru/cabinet/billing?embed=1",
        "https://rustdesk.dr6ter.ru/pilot",
        f"{base}/cabinet/?embed=1",
        f"{base}/cabinet/billing?embed=1",
        f"{base}/pilot",
    ):
        pass  # normalized below via block rewrite

    about_links = f"""InkWell(
                  onTap: () {{
                    openDeskForceCabinet(
                      url: '{base}/cabinet/?embed=1',
                      title: 'Личный кабинет',
                    );
                  }},
                  child: Text(
                    'Личный кабинет',
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),
              InkWell(
                  onTap: () {{
                    openDeskForceCabinet(
                      url: '{base}/cabinet/billing?embed=1',
                      title: 'Тарифы',
                    );
                  }},
                  child: Text(
                    'Тарифы и оплата',
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),
              InkWell(
                  onTap: () {{
                    launchUrlString('{base}/guide');
                  }},
                  child: Text(
                    'Инструкция',
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),"""

    # Replace Privacy + Website (+ optional third) InkWell cluster before yellow box
    text2 = re.sub(
        r"InkWell\(\s*onTap: \(\) \{\s*launchUrlString\('[^']+'\);\s*\},\s*child: Text\(\s*(?:translate\('Privacy Statement'\)|'Личный кабинет'),"
        r"[\s\S]*?\)\.marginSymmetric\(vertical: 4\.0\)\),\s*"
        r"(?:InkWell\([\s\S]*?\)\.marginSymmetric\(vertical: 4\.0\)\),\s*){1,3}"
        r"Container\(\s*decoration: const BoxDecoration\(color: Color\(0xFF(?:2c8cff|F5C518)\)\)",
        about_links + "\n              Container(\n                decoration: const BoxDecoration(color: Color(0xFFF5C518))",
        text,
        count=1,
    )
    if text2 == text:
        # Fallback: force host + label replacements
        text2 = text
        text2 = text2.replace("https://rustdesk.com/privacy.html", f"{base}/cabinet/?embed=1")
        text2 = text2.replace("https://rustdesk.com", f"{base}/")
        text2 = text2.replace("https://rustdesk.dr6ter.ru", base)
        text2 = text2.replace("translate('Privacy Statement')", "'Личный кабинет'")
        text2 = text2.replace("translate('Website')", "'Тарифы и оплата'")
        print("WARN: About link cluster regex miss — applied host/label fallback", file=sys.stderr)
    else:
        print("Patched: About dialog links")

    # Copyright + slogan (no Purslane / stock heart slogan).
    # Use a lambda replacement so re.sub does not turn \n into a real newline
    # (which would break the Dart string literal).
    copyright_repl = f"'Copyright © {year} {app_name} УД\\nDeskForce remote access'"
    text2 = re.sub(
        r"'Copyright © \$\{DateTime\.now\(\)\.toString\(\)\.substring\(0, 4\)\} [^']*\\n\$license'",
        lambda _m: copyright_repl,
        text2,
        count=1,
    )
    text2 = text2.replace(
        "translate('Slogan_tip')",
        f"'{app_name} — удалённый доступ для вашей команды'",
    )
    # Readable slogan on brass banner
    text2 = text2.replace(
        """Text(
                            translate('Slogan_tip'),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          )""",
        f"""Text(
                            '{app_name} — удалённый доступ для вашей команды',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111111)),
                          )""",
    )
    text2 = re.sub(
        r"Text\(\s*'[^']*удалённый доступ для вашей команды',\s*style: TextStyle\(\s*fontWeight: FontWeight\.w800,\s*color: Colors\.white\),?\s*\)",
        f"Text(\n                            '{app_name} — удалённый доступ для вашей команды',\n"
        "                            style: const TextStyle(\n"
        "                                fontWeight: FontWeight.w800,\n"
        "                                color: Color(0xFF111111)),\n                          )",
        text2,
        count=1,
    )

    # Banner color if still stock blue
    text2 = text2.replace(
        "decoration: const BoxDecoration(color: Color(0xFF2c8cff))",
        "decoration: const BoxDecoration(color: Color(0xFFF5C518))",
    )
    text2 = text2.replace(
        "style: const TextStyle(color: Colors.white),\n                          ),\n                          Text(",
        "style: const TextStyle(color: Color(0xFF111111)),\n                          ),\n                          Text(",
    )

    if "Purslane" in text2 or "rustdesk.com" in text2.lower():
        text2 = text2.replace("Purslane Ltd.", app_name)
        text2 = text2.replace("Purslane Ltd", app_name)
        text2 = re.sub(r"https?://(?:www\.)?rustdesk\.com[^\s'\"]*", f"{base}/", text2)
        print("Patched: stripped residual Purslane/rustdesk.com from About")

    # Native cabinet opener — never launchUrlString for кабинет.
    if "cabinet_webview_page.dart" not in text2:
        text2 = (
            "import 'package:flutter_hbb/desktop/pages/cabinet_webview_page.dart';\n"
            + text2
        )
    # Strip any residual cabinet launchUrlString that fallback host-replace left behind.
    text2 = re.sub(
        r"launchUrlString\('https://[^']*/cabinet[^']*'\);",
        "openDeskForceCabinet();",
        text2,
    )
    path.write_text(text2, encoding="utf-8")
    print("Patched: About dialog DeskForce-only")


def patch_lang_branding(src: pathlib.Path, app_name: str) -> None:
    """User-visible About / powered-by strings in en + ru."""
    replacements = {
        "en.rs": [
            ('("Slogan_tip", "Made with heart in this chaotic world!")',
             f'("Slogan_tip", "{app_name} remote access")'),
            ('("powered_by_me", "Powered by RustDesk")',
             f'("powered_by_me", "{app_name}")'),
            ('("About RustDesk", "")',
             f'("About RustDesk", "About {app_name}")'),
        ],
        "ru.rs": [
            ('("Slogan_tip", "Сделано с душой в этом безумном мире!")',
             f'("Slogan_tip", "{app_name} — удалённый доступ")'),
            ('("powered_by_me", "Основано на RustDesk")',
             f'("powered_by_me", "{app_name}")'),
            ('("About RustDesk", "О RustDesk")',
             f'("About RustDesk", "О {app_name}")'),
        ],
    }
    lang_dir = src / "src" / "lang"
    for fname, pairs in replacements.items():
        path = lang_dir / fname
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for old, new in pairs:
            if old in text:
                text = text.replace(old, new)
                label = old.split(",", 1)[0].strip()[:48]
                print(f"Patched lang {fname}: {label}")
            elif new in text:
                print(f"OK already lang {fname}")
        path.write_text(text, encoding="utf-8")


def patch_powered_link(src: pathlib.Path, api: str) -> None:
    path = src / "flutter" / "lib" / "common.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    base = api.rstrip("/")
    text2 = text.replace(
        "launchUrl(Uri.parse('https://rustdesk.com'));",
        f"launchUrl(Uri.parse('{base}/'));",
    )
    if text2 != text:
        path.write_text(text2, encoding="utf-8")
        print("Patched: powered-by link -> DeskForce site")
    else:
        print("OK already: powered-by link")


def patch_home_cabinet_links(src: pathlib.Path, api: str) -> None:
    path = src / "flutter" / "lib" / "desktop" / "pages" / "desktop_home_page.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    base = api.rstrip("/")
    text = text.replace("https://rustdesk.dr6ter.ru", base)
    text = text.replace("https://example.com", base)
    text = re.sub(
        r"const borderColor = Color\(0x[0-9A-Fa-f]+\);",
        "const borderColor = Color(0xFF2DD4BF);",
        text,
        count=1,
    )
    path.write_text(text, encoding="utf-8")
    print("Patched: desktop_home_page cabinet URLs + borderColor")


def patch_titlebar(src: pathlib.Path) -> None:
    path = src / "flutter" / "lib" / "desktop" / "widgets" / "titlebar_widget.dart"
    if not path.is_file():
        return
    path.write_text(
        """import 'package:flutter/material.dart';

// DeskForce slate/teal title bar (site tokens)
const sidebarColor = Color(0xFF0C1422);
const backgroundStartColor = Color(0xFF070B14);
const backgroundEndColor = Color(0xFF0C1422);

class DesktopTitleBar extends StatelessWidget {
  final Widget? child;

  const DesktopTitleBar({Key? key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundStartColor, backgroundEndColor],
            stops: [0.0, 1.0]),
      ),
      child: Row(
        children: [
          Expanded(
            child: child ?? Offstage(),
          )
        ],
      ),
    );
  }
}
""",
        encoding="utf-8",
    )
    print("Patched: titlebar_widget slate/teal")


def patch_theme_force_light(src: pathlib.Path) -> None:
    path = src / "flutter" / "lib" / "common.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    old = """  static ThemeMode getThemeModePreference() {
    return themeModeFromString(bind.mainGetLocalOption(key: kCommConfKeyTheme));
  }"""
    new = """  static ThemeMode getThemeModePreference() {
    // DeskForce: site slate/teal chrome (MyTheme paints dark paper)
    return ThemeMode.light;
  }"""
    if "DeskForce: site slate/teal chrome" in text or "DeskForce: product UI is paper/brass light" in text:
        if "DeskForce: site slate/teal chrome" not in text and old in text:
            path.write_text(text.replace(old, new, 1), encoding="utf-8")
            print("Patched: force ThemeMode.light (slate/teal)")
            return
        print("OK already: force light theme")
        return
    if old in text:
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        print("Patched: force ThemeMode.light")
    else:
        print("WARN: getThemeModePreference not found", file=sys.stderr)


def patch_mytheme_paper_brass(src: pathlib.Path) -> None:
    """Replace stock RustDesk blue MyTheme + ColorThemeExtension with slate/teal.

    Anchored to `class MyTheme` / ColorThemeExtension.light so re-runs cannot
    corrupt ColorThemeExtension (older regex spanned DeskForce comments).
    """
    path = src / "flutter" / "lib" / "common.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")

    ext_light = """  static final light = ColorThemeExtension(
    border: Color(0x338BA0B8),
    border2: Color(0xFF2DD4BF),
    border3: Color(0x228BA0B8),
    highlight: Color(0xFF0C1422),
    drag_indicator: Color(0xFF8BA0B8),
    shadow: Color(0xFF000000),
    errorBannerBg: Color(0xFF3F1D2E),
    me: Color(0xFF34D399),
    toastBg: Color(0xCC070B14),
    toastText: Color(0xFFE8F4FF),
    divider: Color(0x338BA0B8),
  );"""
    text2, n_ext = re.subn(
        r"  static final light = ColorThemeExtension\([\s\S]*?\n  \);",
        ext_light,
        text,
        count=1,
    )
    if n_ext:
        print("Patched: ColorThemeExtension.light slate/teal")
    else:
        print("WARN: ColorThemeExtension.light not patched", file=sys.stderr)

    colors = """  // DeskForce slate/teal/ink (site/tokens.css)
  static const Color grayBg = Color(0xFF0C1422);
  static const Color accent = Color(0xFF2DD4BF);
  static const Color accent50 = Color(0x772DD4BF);
  static const Color accent80 = Color(0xAA2DD4BF);
  static const Color canvasColor = Color(0xFF070B14);
  static const Color border = Color(0x338BA0B8);
  static const Color idColor = Color(0xFF5EEAD4);
  static const Color darkGray = Color(0xFF8BA0B8);
  static const Color cmIdColor = Color(0xFF34D399);
  static const Color dark = Color(0xFFE8F4FF);
  static const Color button = Color(0xFF2DD4BF);
  static const Color hoverBorder = Color(0xFF2DD4BF);"""

    m = re.search(r"class MyTheme \{", text2)
    if not m:
        # Recover from prior corrupt branding runs that swallowed `class MyTheme`.
        if "static const Color grayBg" in text2 and "class MyTheme" not in text2:
            print("WARN: class MyTheme missing (corrupt tree) — skip MyTheme recolor", file=sys.stderr)
        else:
            print("WARN: class MyTheme not found", file=sys.stderr)
        path.write_text(text2, encoding="utf-8")
        return

    start = m.start()
    # MyTheme ends at next top-level class / extension at column 0-ish; use lightTheme marker window
    end_m = re.search(r"\n  static ThemeData lightTheme", text2[start:])
    if not end_m:
        print("WARN: MyTheme.lightTheme not found", file=sys.stderr)
        path.write_text(text2, encoding="utf-8")
        return
    head = text2[:start]
    mytheme = text2[start : start + end_m.start()]
    tail = text2[start + end_m.start() :]

    mytheme2, n_colors = re.subn(
        r"(?:  // DeskForce[^\n]*\n)?"
        r"  static const Color grayBg = [^;]+;\n"
        r"  static const Color accent = [^;]+;\n"
        r"  static const Color accent50 = [^;]+;\n"
        r"  static const Color accent80 = [^;]+;\n"
        r"  static const Color canvasColor = [^;]+;\n"
        r"  static const Color border = [^;]+;\n"
        r"  static const Color idColor = [^;]+;\n"
        r"  static const Color darkGray = [^;]+;\n"
        r"  static const Color cmIdColor = [^;]+;\n"
        r"  static const Color dark = [^;]+;\n"
        r"  static const Color button = [^;]+;\n"
        r"  static const Color hoverBorder = [^;]+;",
        colors,
        mytheme,
        count=1,
    )
    if n_colors:
        print("Patched: MyTheme color constants slate/teal")
    else:
        print("WARN: MyTheme color constants not patched", file=sys.stderr)

    text2 = head + mytheme2 + tail

    # lightTheme: stock RustDesk 1.4.6 still hardcodes Colors.blue as ColorScheme.primary
    # (accent alone is not enough — Material AppBar / FAB / switches follow primary).
    light_reps = [
        (
            "scaffoldBackgroundColor: Colors.white,",
            "scaffoldBackgroundColor: Color(0xFF070B14),",
        ),
        (
            "dialogBackgroundColor: Colors.white,",
            "dialogBackgroundColor: Color(0xFF0C1422),",
        ),
        (
            "hoverColor: Color.fromARGB(255, 224, 224, 224),",
            "hoverColor: Color(0xFF111827),",
        ),
        (
            "hintColor: Color(0xFFAAAAAA),",
            "hintColor: Color(0xFF8BA0B8),",
        ),
        (
            "MenuStyle(backgroundColor: MaterialStatePropertyAll(Colors.white))),",
            "MenuStyle(backgroundColor: MaterialStatePropertyAll(Color(0xFF0C1422)))),",
        ),
        (
            "colorScheme: ColorScheme.light(\n        primary: Colors.blue, secondary: accent, background: grayBg),",
            "colorScheme: ColorScheme.light(\n        primary: accent, secondary: accent, background: Color(0xFF0C1422), onPrimary: Color(0xFF041016), onBackground: Color(0xFFE8F4FF), onSurface: Color(0xFFE8F4FF)),",
        ),
        (
            "popupMenuTheme: PopupMenuThemeData(\n        color: Colors.white,",
            "popupMenuTheme: PopupMenuThemeData(\n        color: Color(0xFF0C1422),",
        ),
        # Idempotent / prior DeskForce dark-as-light leftovers:
        (
            "brightness: Brightness.dark,\n    hoverColor: Color.fromARGB(255, 40, 40, 40),\n    scaffoldBackgroundColor: Color(0xFF121212),\n    dialogBackgroundColor: Color(0xFF141414),",
            "brightness: Brightness.light,\n    hoverColor: Color(0xFF111827),\n    scaffoldBackgroundColor: Color(0xFF070B14),\n    dialogBackgroundColor: Color(0xFF0C1422),",
        ),
        (
            "cardColor: Color(0xFF1C1C1C),\n    hintColor: Color(0xFF9A9A9A),",
            "cardColor: Color(0xFF0C1422),\n    hintColor: Color(0xFF8BA0B8),",
        ),
        ("labelColor: Color(0xFFF5C518),", "labelColor: Color(0xFF2DD4BF),"),
        (
            "colorScheme: ColorScheme.dark(\n        primary: accent, secondary: accent, background: Color(0xFF1C1C1C)),",
            "colorScheme: ColorScheme.light(\n        primary: accent, secondary: accent, background: Color(0xFF0C1422), onPrimary: Color(0xFF041016), onBackground: Color(0xFFE8F4FF), onSurface: Color(0xFFE8F4FF)),",
        ),
        (
            "MenuStyle(backgroundColor: MaterialStatePropertyAll(Color(0xFF121212)))),",
            "MenuStyle(backgroundColor: MaterialStatePropertyAll(Color(0xFF0C1422)))),",
        ),
    ]
    for old, new in light_reps:
        if old in text2:
            text2 = text2.replace(old, new, 1)
            print("Patched lightTheme chunk")

    # Kill leftover stock RustDesk blue literals anywhere in common.dart.
    for old, new in (
        ("Color(0xFF0071FF)", "Color(0xFF2DD4BF)"),
        ("Color(0x770071FF)", "Color(0x772DD4BF)"),
        ("Color(0xAA0071FF)", "Color(0xAA2DD4BF)"),
        ("Color(0xFF2C8CFF)", "Color(0xFF2DD4BF)"),
        ("Color(0xFF00B6F0)", "Color(0xFF2DD4BF)"),
        ("primary: Colors.blue,", "primary: accent,"),
    ):
        if old in text2:
            text2 = text2.replace(old, new)
            print(f"Patched leftover {old} -> brass")

    path.write_text(text2, encoding="utf-8")
    
    # Ensure body/title text is light ink on dark paper canvas
    text2 = text2.replace(
        "color: MyTheme.dark)",
        "color: Color(0xFFE8F4FF))",
    )
    # Avoid double-replacing accent usages incorrectly — only in textTheme blocks is hard;
    # MyTheme.dark const itself is already Color(0xFFE8F4FF), so Theme text using MyTheme.dark is fine.
    # Force ColorScheme surface/onSurface if still stock:
    text2 = text2.replace(
        "background: grayBg)",
        "background: Color(0xFF0C1422), onPrimary: Color(0xFF041016), onBackground: Color(0xFFE8F4FF), onSurface: Color(0xFFE8F4FF))",
    )

    print("Patched: MyTheme slate/teal colors")


def write_overlay_toml(
    src: pathlib.Path, app_name: str, id_server: str, relay: str, api: str, key_pub: str
) -> None:
    overlay = src / "oem-deskforce.toml"
    overlay.write_text(
        f"""# Generated by DeskForce OEM pipeline — do not edit by hand
rendezvous_server = '{id_server}'
relay_server = '{relay}'
api_server = '{api}'
key = '{key_pub}'
app_name = '{app_name}'
""",
        encoding="utf-8",
    )
    print(f"Wrote {overlay}")


def patch_tabbar(src: pathlib.Path) -> None:
    path = src / "flutter" / "lib" / "desktop" / "widgets" / "tabbar_widget.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    old = """  static const light = TabbarTheme(
      selectedTabIconColor: MyTheme.accent,
      unSelectedTabIconColor: Color.fromARGB(255, 162, 203, 241),
      selectedTextColor: Colors.black,
      unSelectedTextColor: Color.fromARGB(255, 112, 112, 112),
      selectedIconColor: Color.fromARGB(255, 26, 26, 26),
      unSelectedIconColor: Color.fromARGB(255, 96, 96, 96),
      dividerColor: Color.fromARGB(255, 238, 238, 238),
      hoverColor: Colors.white54,
      closeHoverColor: Colors.white,
      selectedTabBackgroundColor: Colors.white54);"""
    new = """  static const light = TabbarTheme(
      selectedTabIconColor: MyTheme.accent,
      unSelectedTabIconColor: Color(0xFF8BA0B8),
      selectedTextColor: Color(0xFFE8F4FF),
      unSelectedTextColor: Color(0xFF8BA0B8),
      selectedIconColor: Color(0xFF041016),
      unSelectedIconColor: Color(0xFF8BA0B8),
      dividerColor: Color(0x338BA0B8),
      hoverColor: Color(0x332DD4BF),
      closeHoverColor: Color(0xFF0C1422),
      selectedTabBackgroundColor: Color(0x332DD4BF));"""
    if "0xFF4A5563" in text and "selectedTabBackgroundColor: Color(0x332DD4BF)" in text:
        print("OK already: tabbar light brass")
        return
    if old in text:
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        print("Patched: tabbar_widget light theme")
    else:
        print("WARN: tabbar light block not found", file=sys.stderr)




def patch_linux_packaging(src: pathlib.Path, app_name: str, api: str) -> None:
    """Desktop entry + deb control branding (paths stay rustdesk for postinst)."""
    for rel in ("res/rustdesk.desktop", "res/rustdesk-link.desktop"):
        path = src / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        text2 = text
        text2 = re.sub(r"(?m)^Name=RustDesk\b.*$", f"Name={app_name}", text2)
        text2 = re.sub(r"(?m)^GenericName=.*$", "GenericName=Remote Desktop", text2)
        text2 = re.sub(r"(?m)^Comment=.*$", f"Comment={app_name} Remote Desktop", text2, count=1)
        if text2 != text:
            path.write_text(text2, encoding="utf-8")
            print(f"Patched: {rel} Name={app_name}")
        else:
            print(f"OK/WARN: {rel} (no Name=RustDesk)")

    # Patch build.py generate_control_file metadata for .deb
    build_py = src / "build.py"
    if build_py.is_file():
        text = build_py.read_text(encoding="utf-8", errors="ignore")
        text2 = text
        text2 = text2.replace("Package: rustdesk\n", f"Package: deskforce\n", 1)
        text2 = text2.replace(
            "Maintainer: rustdesk <info@rustdesk.com>\n",
            f"Maintainer: {app_name} <support@deskforce.dr6ter.ru>\n",
            1,
        )
        text2 = text2.replace(
            "Homepage: https://rustdesk.com\n",
            f"Homepage: {api}\n",
            1,
        )
        text2 = text2.replace(
            "Description: A remote control software.\n",
            f"Description: {app_name} remote desktop client.\n",
            1,
        )
        # Provide old package name for upgrades
        if "Package: deskforce\n" in text2 and "Provides: rustdesk\n" not in text2:
            text2 = text2.replace(
                "Package: deskforce\n",
                "Package: deskforce\nProvides: rustdesk\nReplaces: rustdesk\n",
                1,
            )
        if text2 != text:
            build_py.write_text(text2, encoding="utf-8")
            print("Patched: build.py deb control metadata -> deskforce")


def normalize_semver(version: str) -> str:
    """Cargo/Flutter require major.minor.patch with optional -prerelease (e.g. 1.2.0-beta.1)."""
    raw = version.strip()
    # Split core vs prerelease/build: 1.2.0-beta.1+5 → core=1.2.0, rest=-beta.1+5
    core, sep, suffix = raw.partition("-")
    if "+" in core and not sep:
        core, _, build = core.partition("+")
        suffix = "+" + build
        sep = ""
    parts = [p for p in core.split(".") if p != ""]
    while len(parts) < 3:
        parts.append("0")
    core_norm = ".".join(parts[:3])
    if sep:
        return f"{core_norm}-{suffix}"
    if suffix.startswith("+"):
        return f"{core_norm}{suffix}"
    return core_norm


def windows_file_version_numeric(version: str) -> str:
    """Map semver to FILEVERSION tuple (prerelease is not numeric on Windows)."""
    core = normalize_semver(version).split("-")[0].split("+")[0]
    nums: list[int] = []
    for part in core.split("."):
        m = re.match(r"(\d+)", part)
        nums.append(int(m.group(1)) if m else 0)
    while len(nums) < 4:
        nums.append(0)
    return ",".join(str(n) for n in nums[:4])


def windows_file_version_dotted(version: str) -> str:
    return windows_file_version_numeric(version).replace(",", ".")


def patch_runner_rc_version(src: pathlib.Path, semver: str) -> None:
    """Windows Explorer reads Runner.rc VERSIONINFO (inner Flutter runner)."""
    runner_rc = src / "flutter" / "windows" / "runner" / "Runner.rc"
    if not runner_rc.is_file():
        return
    text = runner_rc.read_text(encoding="utf-8", errors="ignore")
    file_num = windows_file_version_numeric(semver)
    oem_block = f"""// DESKFORCE_OEM_VERSION_BEGIN
#undef VERSION_AS_NUMBER
#undef VERSION_AS_STRING
#define VERSION_AS_NUMBER {file_num}
#define VERSION_AS_STRING "{semver}"
// DESKFORCE_OEM_VERSION_END
"""
    if "DESKFORCE_OEM_VERSION_BEGIN" in text:
        text = re.sub(
            r"// DESKFORCE_OEM_VERSION_BEGIN[\s\S]*?// DESKFORCE_OEM_VERSION_END\n",
            oem_block,
            text,
            count=1,
        )
        print(f"Patched: Runner.rc OEM version={semver}")
    elif "VS_VERSION_INFO VERSIONINFO" in text:
        text = text.replace(
            "VS_VERSION_INFO VERSIONINFO",
            oem_block + "VS_VERSION_INFO VERSIONINFO",
            1,
        )
        print(f"Patched: Runner.rc OEM version={semver}")
    else:
        print("WARN: Runner.rc VERSIONINFO anchor missing", file=sys.stderr)
        return
    runner_rc.write_text(text, encoding="utf-8")


def patch_portable_packer_version(src: pathlib.Path, semver: str) -> None:
    """Final DeskForce.exe is rustdesk-portable-packer — its winres sets Explorer metadata."""
    portable = src / "libs" / "portable" / "Cargo.toml"
    if not portable.is_file():
        return
    text = portable.read_text(encoding="utf-8", errors="ignore")
    text2 = re.sub(r'(?m)^version = "[^"]*"', f'version = "{semver}"', text, count=1)
    file_ver = windows_file_version_dotted(semver)
    text2 = text2.replace('#ProductVersion = ""', f'ProductVersion = "{semver}"')
    text2 = text2.replace('#FileVersion = ""', f'FileVersion = "{file_ver}"')
    for key, val in (
        ("ProductVersion", semver),
        ("FileVersion", file_ver),
    ):
        pat = rf'(?m)^{key} = "[^"]*"'
        if re.search(pat, text2):
            text2 = re.sub(pat, f'{key} = "{val}"', text2, count=1)
        elif "[package.metadata.winres]" in text2:
            text2 = text2.replace(
                "[package.metadata.winres]\n",
                f'[package.metadata.winres]\n{key} = "{val}"\n',
                1,
            )
    if text2 != text:
        portable.write_text(text2, encoding="utf-8")
        print(f"Patched: portable Cargo.toml version={semver} winres ProductVersion/FileVersion")


def patch_version(src: pathlib.Path, version: str = "1.0") -> None:
    """Branded app version for About / update checks / Windows VERSIONINFO."""
    semver = normalize_semver(version)
    cargo = src / "Cargo.toml"
    if cargo.is_file():
        text = cargo.read_text(encoding="utf-8", errors="ignore")
        text2 = re.sub(r'(?m)^version = "[^"]*"', f'version = "{semver}"', text, count=1)
        text2 = re.sub(
            r'(?m)^authors = \[[^\]]*\]',
            'authors = ["DeskForce <support@deskforce.dr6ter.ru>"]',
            text2,
            count=1,
        )
        text2 = re.sub(
            r'(?m)^description = "[^"]*"',
            'description = "DeskForce Remote Desktop"',
            text2,
            count=1,
        )
        if text2 != text:
            cargo.write_text(text2, encoding="utf-8")
            print(f"Patched: Cargo.toml version={semver}")
    pubspec = src / "flutter" / "pubspec.yaml"
    if pubspec.is_file():
        text = pubspec.read_text(encoding="utf-8", errors="ignore")
        text2 = re.sub(r'(?m)^version: .*', f'version: {semver}+1', text, count=1)
        if text2 != text:
            pubspec.write_text(text2, encoding="utf-8")
            print(f"Patched: pubspec.yaml version={semver}+1")
    # Ensure generated version.rs if present (build will regenerate)
    ver_rs = src / "src" / "version.rs"
    if ver_rs.is_file():
        ver_rs.write_text(
            f'pub const VERSION: &str = "{semver}";\n'
            '#[allow(dead_code)]\n'
            'pub const BUILD_DATE: &str = "DeskForce";\n',
            encoding="utf-8",
        )
        print(f"Patched: src/version.rs VERSION={semver}")
    patch_runner_rc_version(src, semver)
    patch_portable_packer_version(src, semver)



def ensure_cabinet_sound_asset(src: pathlib.Path, root: pathlib.Path) -> None:
    """Ensure DeskForce UI click wav is present under flutter/assets/sounds (copied via overrides)."""
    wav = src / "flutter" / "assets" / "sounds" / "ui_click.wav"
    if wav.is_file() and wav.stat().st_size > 100:
        print(f"OK: cabinet click sound {wav.relative_to(src)}")
        return
    ov = root / "overrides" / "flutter" / "assets" / "sounds" / "ui_click.wav"
    if ov.is_file():
        wav.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ov, wav)
        print(f"Copied: {wav.relative_to(src)}")
        return
    print("WARN: missing flutter/assets/sounds/ui_click.wav — click sound disabled at runtime", file=sys.stderr)



def ensure_crypto_dependency(src: pathlib.Path) -> None:
    """cabinet_api PoW needs package:crypto (not always a direct dep upstream)."""
    pubspec = src / "flutter" / "pubspec.yaml"
    if not pubspec.is_file():
        return
    text = pubspec.read_text(encoding="utf-8", errors="ignore")
    if re.search(r"^\s*crypto\s*:", text, flags=re.M):
        print("OK: pubspec already has crypto")
        return
    m = re.search(r"(^dependencies:\s*\n)", text, flags=re.M)
    if not m:
        print("WARN: no dependencies block for crypto", file=sys.stderr)
        return
    insert_at = m.end()
    hm = re.search(r"^(\s*http\s*:.*\n)", text, flags=re.M)
    if hm:
        insert_at = hm.end()
    text2 = text[:insert_at] + "  crypto: ^3.0.3\n" + text[insert_at:]
    pubspec.write_text(text2, encoding="utf-8")
    print("Patched: pubspec crypto dependency")

def patch_pubspec_cabinet_note(src: pathlib.Path) -> None:
    """Cabinet is native Flutter; webview_windows kept only if already required elsewhere."""
    # assets/ already covers assets/sounds/ — nothing required beyond copy_ui_overrides.
    pubspec = src / "flutter" / "pubspec.yaml"
    if not pubspec.is_file():
        return
    text = pubspec.read_text(encoding="utf-8", errors="ignore")
    if "assets/sounds/" in text or "- assets/" in text:
        print("OK: pubspec assets/ covers sounds/")
    # Leave webview_windows if present (CI may still grep); native cabinet does not import it.


def patch_pubspec_webview(src: pathlib.Path) -> None:
    pubspec = src / "flutter" / "pubspec.yaml"
    if not pubspec.is_file():
        return
    text = pubspec.read_text(encoding="utf-8", errors="ignore")
    if "webview_windows:" in text:
        print("OK already: webview_windows")
        return
    # Insert after url_launcher block
    needle = "  url_launcher: ^6.3.1\n"
    insert = needle + "  webview_windows: ^0.4.0\n"
    if needle in text:
        pubspec.write_text(text.replace(needle, insert, 1), encoding="utf-8")
        print("Patched: pubspec webview_windows")
    else:
        # fallback: after dependencies:
        text2 = re.sub(
            r"(dependencies:\n)",
            r"\1  webview_windows: ^0.4.0\n",
            text,
            count=1,
        )
        if text2 != text:
            pubspec.write_text(text2, encoding="utf-8")
            print("Patched: pubspec webview_windows (fallback)")
        else:
            print("WARN: could not add webview_windows", file=sys.stderr)


def patch_strip_rustdesk_urls(src: pathlib.Path, api: str) -> None:
    """Replace user-facing RustDesk website / GitHub release links with DeskForce."""
    base = api.rstrip("/")
    mapping = [
        ("https://rustdesk.com/download", f"{base}/downloads/windows/DeskForce.exe"),
        ("https://rustdesk.com/privacy.html", f"{base}/terms"),
        ("https://rustdesk.com/pricing", f"{base}/pricing"),
        ("https://www.rustdesk.com/pricing", f"{base}/pricing"),
        ("https://rustdesk.com/docs/en/client/mac/#enable-permissions", f"{base}/guide"),
        ("https://rustdesk.com/docs/en/client/linux/#x11-required", f"{base}/guide"),
        ("https://rustdesk.com/docs/en/manual/linux/#x11-required", f"{base}/guide"),
        ("https://rustdesk.com/docs/en/client/linux/#permissions-issue", f"{base}/guide"),
        ("https://rustdesk.com/docs/en/client/linux/#login-screen", f"{base}/guide"),
        ("https://rustdesk.com/docs/en/", f"{base}/guide"),
        ("https://rustdesk.com/", f"{base}/"),
        ("https://www.rustdesk.com/", f"{base}/"),
        ("https://admin.rustdesk.com", base),
        ("https://api.rustdesk.com", base),
        ("'https://rustdesk.com'", f"'{base}/'"),
        ('"https://rustdesk.com"', f'"{base}/"'),
        ("'rustdesk.com'", f"'{base.replace('https://','')}'"),
        ("https://github.com/rustdesk/rustdesk/releases", f"{base}/guide"),
    ]
    roots = [
        src / "flutter" / "lib",
        src / "src" / "lang",
    ]
    changed_files = 0
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix.lower() not in {".dart", ".rs"}:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            orig = text
            for old, new in mapping:
                text = text.replace(old, new)
            # generic docs / github release tag URLs still pointing at rustdesk
            text = re.sub(
                r"https://github\.com/rustdesk/rustdesk/releases/tag/[^'\"\s]+",
                f"{base}/guide",
                text,
            )
            text = re.sub(
                r"https://rustdesk\.com/docs/[^'\"\s]+",
                f"{base}/guide",
                text,
            )
            if text != orig:
                path.write_text(text, encoding="utf-8")
                changed_files += 1
                print(f"Stripped RustDesk URLs in {path.relative_to(src)}")
    print(f"URL strip done, files changed={changed_files}")


def apply_git_patches(src: pathlib.Path, patches_dir: pathlib.Path) -> None:
    """Optional fallback patches (idempotent-ish via git apply --check)."""
    import subprocess

    for name in ("deskforce-hbb-common.patch", "deskforce-ui.patch"):
        patch = patches_dir / name
        if not patch.is_file():
            continue
        # hbb_common patch applies inside submodule
        cwd = src / "libs" / "hbb_common" if "hbb-common" in name else src
        check = subprocess.run(
            ["git", "apply", "--check", str(patch)],
            cwd=cwd,
            capture_output=True,
            text=True,
        )
        if check.returncode != 0:
            print(f"Skip patch {name} (already applied or mismatch)")
            continue
        subprocess.run(["git", "apply", str(patch)], cwd=cwd, check=False)
        print(f"Applied patch {name}")



def patch_portable_extract_dir(src: pathlib.Path, app_name: str = "DeskForce") -> None:
    """Avoid colliding with stock RustDesk %LOCALAPPDATA%/rustdesk extract cache."""
    path = src / "libs" / "portable" / "src" / "main.rs"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    folder = "deskforce"
    text2 = text.replace(
        'const APP_PREFIX: &str = "rustdesk";',
        f'const APP_PREFIX: &str = "{folder}";',
    )
    # Keep identifier in data.bin as rustdesk (packer format); only extract dir changes.
    if text2 != text:
        path.write_text(text2, encoding="utf-8")
        print(f"Patched: portable APP_PREFIX -> {folder}")
    else:
        if f'APP_PREFIX: &str = "{folder}"' in text:
            print("OK already: portable APP_PREFIX deskforce")
        else:
            print("WARN: portable APP_PREFIX pattern miss", file=sys.stderr)


def patch_main_window_startup(src: pathlib.Path) -> None:
    """Larger centered main window; honor DeskForce startup options."""
    path = src / "flutter" / "lib" / "main.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    if "deskforce_startup.dart" not in text:
        text = text.replace(
            "import 'package:window_manager/window_manager.dart';\n",
            "import 'package:window_manager/window_manager.dart';\n"
            "import 'package:flutter_hbb/common/deskforce_startup.dart';\n",
        )
    needle = "WindowOptions windowOptions = getHiddenTitleBarWindowOptions(\n      isMainWindow: true, alwaysOnTop: alwaysOnTop);"
    repl = (
        "WindowOptions windowOptions = getHiddenTitleBarWindowOptions(\n"
        "      isMainWindow: true,\n"
        "      alwaysOnTop: alwaysOnTop,\n"
        "      size: const Size(960, 860),\n"
        "      center: true);"
    )
    if needle in text:
        text = text.replace(needle, repl)
        print("Patched: main WindowOptions size/center")
    # Replace restore+show block body markers
    if "dfApplyStartupWindowBehavior" not in text:
        text2 = text.replace(
            "    // Restore the location of the main window before window hide or show.\n"
            "    await restoreWindowPosition(WindowType.Main);\n",
            "    // DeskForce: min size only; maximize/size handled in dfApplyStartupWindowBehavior.\n"
            "    try {\n"
            "      await windowManager.setMinimumSize(const Size(720, 640));\n"
            "    } catch (_) {\n"
            "      await restoreWindowPosition(WindowType.Main);\n"
            "    }\n",
        )
        text2 = text2.replace(
            "      windowManager.show();\n"
            "      windowManager.focus();\n"
            "      // Move registration of active main window here to prevent from async visible check.\n"
            "      rustDeskWinManager.registerActiveWindow(kWindowMainId);\n",
            "      rustDeskWinManager.registerActiveWindow(kWindowMainId);\n"
            "      await dfApplyStartupWindowBehavior();\n",
        )
        if text2 != text:
            text = text2
            print("Patched: main.dart startup behavior")
        else:
            print("WARN: main.dart show/restore replace miss", file=sys.stderr)
    else:
        print("OK already: main startup behavior")
    # Fixup older DeskForce builds that setSize/center before maximize.
    old_size = (
        "    // DeskForce: large centered window (skip tiny stock restore).\n"
        "    try {\n"
        "      await windowManager.setMinimumSize(const Size(720, 640));\n"
        "      await windowManager.setSize(const Size(960, 860));\n"
        "      await windowManager.setAlignment(Alignment.center);\n"
        "    } catch (_) {\n"
        "      await restoreWindowPosition(WindowType.Main);\n"
        "    }\n"
    )
    new_size = (
        "    // DeskForce: min size only; maximize/size handled in dfApplyStartupWindowBehavior.\n"
        "    try {\n"
        "      await windowManager.setMinimumSize(const Size(720, 640));\n"
        "    } catch (_) {\n"
        "      await restoreWindowPosition(WindowType.Main);\n"
        "    }\n"
    )
    if old_size in text:
        text = text.replace(old_size, new_size)
        print("Patched: main.dart drop setSize-before-maximize")
    # Remove obsolete comment line if left
    text = text.replace(
        "    // Do not use `windowManager.setResizable()` here.\n    setResizable(!bind.isIncomingOnly());",
        "    setResizable(!bind.isIncomingOnly());",
    )
    path.write_text(text, encoding="utf-8")


def patch_fullscreen_toggle(src: pathlib.Path) -> None:
    path = src / "flutter" / "lib" / "desktop" / "widgets" / "tabbar_widget.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    if "DeskForce: clean enter/exit fullscreen" in text:
        print("OK already: toggleMaximize")
        return
    old = (
        "Future<bool> toggleMaximize(bool isMainWindow) async {\n"
        "  if (isMainWindow) {\n"
        "    if (await windowManager.isMaximized()) {\n"
        "      windowManager.unmaximize();\n"
        "      return false;\n"
        "    } else {\n"
        "      windowManager.maximize();\n"
        "      return true;\n"
        "    }\n"
        "  } else {\n"
        "    final wc = WindowController.fromWindowId(kWindowId!);\n"
        "    if (await wc.isMaximized()) {\n"
        "      wc.unmaximize();\n"
        "      return false;\n"
        "    } else {\n"
        "      wc.maximize();\n"
        "      return true;\n"
        "    }\n"
        "  }\n"
        "}"
    )
    new = (
        "Future<bool> toggleMaximize(bool isMainWindow) async {\n"
        "  // DeskForce: clean enter/exit fullscreen + maximize on Windows.\n"
        "  if (isMainWindow) {\n"
        "    try {\n"
        "      if (await windowManager.isFullScreen()) {\n"
        "        await windowManager.setFullScreen(false);\n"
        "        stateGlobal.setMaximized(false);\n"
        "        return false;\n"
        "      }\n"
        "    } catch (_) {}\n"
        "    if (await windowManager.isMaximized()) {\n"
        "      await windowManager.unmaximize();\n"
        "      stateGlobal.setMaximized(false);\n"
        "      return false;\n"
        "    } else {\n"
        "      await windowManager.maximize();\n"
        "      stateGlobal.setMaximized(true);\n"
        "      return true;\n"
        "    }\n"
        "  } else {\n"
        "    final wc = WindowController.fromWindowId(kWindowId!);\n"
        "    if (await wc.isMaximized()) {\n"
        "      await wc.unmaximize();\n"
        "      stateGlobal.setMaximized(false);\n"
        "      return false;\n"
        "    } else {\n"
        "      await wc.maximize();\n"
        "      stateGlobal.setMaximized(true);\n"
        "      return true;\n"
        "    }\n"
        "  }\n"
        "}"
    )
    if old in text:
        path.write_text(text.replace(old, new), encoding="utf-8")
        print("Patched: toggleMaximize fullscreen-safe")
    else:
        print("WARN: toggleMaximize block miss", file=sys.stderr)


def patch_disable_maximize_gate(src: pathlib.Path) -> None:
    path = src / "flutter" / "lib" / "desktop" / "widgets" / "tabbar_widget.dart"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    text2 = text.replace(
        "onTap: bind.isIncomingOnly() && isInHomePage()\n                          ? null\n                          : _toggleMaximize,",
        "onTap: _toggleMaximize,",
    )
    text2 = text2.replace(
        "onTap: bind.isIncomingOnly() && isInHomePage() ? null : _toggleMaximize,",
        "onTap: _toggleMaximize,",
    )
    if text2 != text:
        path.write_text(text2, encoding="utf-8")
        print("Patched: maximize always enabled")
    else:
        print("OK/WARN maximize gate")


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent
    src = pathlib.Path(env("RUSTDESK_SRC", str(root / "rustdesk-src"))).resolve()
    branding = root / "branding"
    if not src.is_dir():
        print(f"RUSTDESK_SRC not found: {src}", file=sys.stderr)
        return 1

    app_name = env("OEM_APP_NAME", "DeskForce")
    id_server = env("OEM_ID_SERVER", "78.29.49.98")
    relay = env("OEM_RELAY_SERVER", id_server)
    key_pub = env("OEM_KEY_PUB", "")
    api = env("OEM_API_SERVER", "https://deskforce.dr6ter.ru")

    if not key_pub:
        print("OEM_KEY_PUB is required", file=sys.stderr)
        return 1

    write_overlay_toml(src, app_name, id_server, relay, api, key_pub)
    copy_branding_fixed(src, branding)
    copy_ui_overrides(src, root)
    patch_config_rs(src, app_name, id_server, key_pub)
    patch_common_rs(src, app_name, id_server, relay, api, key_pub)
    patch_flutter_ffi(src)
    patch_platform_names(src, app_name)
    patch_disable_stock_update_check(src)
    patch_linux_packaging(src, app_name, api)
    patch_version(src, env("OEM_APP_VERSION", "1.0"))
    ensure_cabinet_sound_asset(src, root)
    ensure_crypto_dependency(src)
    patch_pubspec_cabinet_note(src)
    patch_pubspec_webview(src)
    patch_peer_tabs(src)
    patch_home_cabinet_links(src, api)
    patch_about_dialog(src, app_name, api)
    patch_lang_branding(src, app_name)
    patch_powered_link(src, api)
    patch_strip_rustdesk_urls(src, api)
    patch_titlebar(src)
    patch_mytheme_paper_brass(src)
    patch_theme_force_light(src)
    patch_tabbar(src)
    # Fix lightTheme extensions if still pointing at dark
    common = src / "flutter" / "lib" / "common.dart"
    if common.is_file():
        t = common.read_text(encoding="utf-8", errors="ignore")
        t2 = t.replace(
            "extensions: <ThemeExtension<dynamic>>[\n      ColorThemeExtension.dark,\n      TabbarTheme.dark,\n    ],\n  );\n  static ThemeData darkTheme",
            "extensions: <ThemeExtension<dynamic>>[\n      ColorThemeExtension.light,\n      TabbarTheme.light,\n    ],\n  );\n  static ThemeData darkTheme",
            1,
        )
        if t2 != t:
            common.write_text(t2, encoding="utf-8")
            print("Patched: lightTheme uses ColorThemeExtension.light")

    patch_portable_extract_dir(src, app_name)
    patch_main_window_startup(src)
    patch_fullscreen_toggle(src)
    patch_disable_maximize_gate(src)
    print(f"Branding applied: app={app_name} id={id_server} api={api}")
    return 0



def patch_mobile_branding(src: pathlib.Path, app_name: str) -> None:
    for rel in (
        "flutter/lib/mobile/widgets/floating_mouse.dart",
        "flutter/lib/mobile/widgets/floating_mouse_widgets.dart",
    ):
        path = src / rel
        if not path.is_file():
            continue
        t = path.read_text(encoding="utf-8", errors="ignore")
        t = t.replace("Colors.blue.withOpacity(0.7)", "MyTheme.accent.withOpacity(0.7)")
        t = t.replace("..color = Colors.blue", "..color = MyTheme.accent")
        if t != path.read_text(encoding="utf-8", errors="ignore"):
            path.write_text(t, encoding="utf-8")
            print(f"Patched mobile mouse blues in {path.name}")

    common = src / "flutter" / "lib" / "common.dart"
    if common.is_file():
        t = common.read_text(encoding="utf-8", errors="ignore")
        t = t.replace("color: Colors.blue,", "color: MyTheme.accent,")
        t = t.replace('debugPrint("Start closing RustDesk...");', f'debugPrint("Start closing {app_name}...");')
        if t != common.read_text(encoding="utf-8", errors="ignore"):
            common.write_text(t, encoding="utf-8")
            print("Patched common.dart link color + app name logs")

    manifest = src / "flutter" / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if manifest.is_file():
        t = manifest.read_text(encoding="utf-8", errors="ignore")
        t = t.replace('android:scheme="rustdesk"', 'android:scheme="deskforce"')
        if t != manifest.read_text(encoding="utf-8", errors="ignore"):
            manifest.write_text(t, encoding="utf-8")
            print("Patched AndroidManifest deep link scheme")

    kotlin_files = [
        src / "flutter" / "android" / "app" / "src" / "main" / "kotlin" / "com.carriez.flutter_hbb" / "MainService.kt",
        src / "flutter" / "android" / "app" / "src" / "main" / "kotlin" / "com.carriez.flutter_hbb" / "FloatingWindowService.kt",
        src / "flutter" / "android" / "app" / "src" / "main" / "kotlin" / "com.carriez.flutter_hbb" / "BootReceiver.kt",
    ]
    for path in kotlin_files:
        if not path.is_file():
            continue
        t = path.read_text(encoding="utf-8", errors="ignore")
        t = t.replace('"Show RustDesk"', f'"Show {app_name}"')
        t = t.replace('DEFAULT_NOTIFY_TITLE = "RustDesk"', f'DEFAULT_NOTIFY_TITLE = "{app_name}"')
        t = t.replace('"RustDesk Service"', f'"{app_name} Service"')
        t = t.replace('"RustDesk Service Channel"', f'"{app_name} Service Channel"')
        t = t.replace('"RustDeskVD"', f'"{app_name}VD"')
        t = t.replace('"RustDesk is Open"', f'"{app_name} is Open"')
        if t != path.read_text(encoding="utf-8", errors="ignore"):
            path.write_text(t, encoding="utf-8")
            print(f"Patched Kotlin branding in {path.name}")

    mobile_dart = [
        src / "flutter" / "lib" / "mobile" / "pages" / "settings_page.dart",
        src / "flutter" / "lib" / "mobile" / "pages" / "home_page.dart",
    ]
    for path in mobile_dart:
        if not path.is_file():
            continue
        t = path.read_text(encoding="utf-8", errors="ignore")
        t = t.replace("Keep RustDesk background service", f"Keep {app_name} background service")
        t = t.replace("About RustDesk", f"About {app_name}")
        t = t.replace("rustdesk://", "deskforce://")
        if t != path.read_text(encoding="utf-8", errors="ignore"):
            path.write_text(t, encoding="utf-8")
            print(f"Patched mobile Dart strings in {path.name}")


def patch_mobile_connection_page(src: pathlib.Path, app_name: str) -> None:
    """Replace stock mobile connection page with DeskForce full override.

    Surgical RawAutocomplete half-edits break Dart on RustDesk 1.4.6+; always
    overwrite from oem/overrides (same approach as desktop connection_page).
    """
    path = src / "flutter" / "lib" / "mobile" / "pages" / "connection_page.dart"
    if not path.is_file():
        return
    content = path.read_text(encoding="utf-8", errors="ignore")
    stockish = (
        "RawAutocomplete<" in content
        or "_allPeersLoader" in content
        or "widgets/autocomplete.dart" in content
    )
    deskforce_ok = (
        "DeskForce mobile connect" in content
        and "НЕДАВНИЕ" in content
        and "RawAutocomplete<" not in content
        and "_allPeersLoader" not in content
        and "PeerTabPage" not in content
        and "SliverFillRemaining" not in content
    )
    if deskforce_ok and not stockish:
        print("OK already: mobile connection_page.dart")
        return

    root = pathlib.Path(__file__).resolve().parent
    override = (
        root
        / "overrides"
        / "flutter"
        / "lib"
        / "mobile"
        / "pages"
        / "connection_page.dart"
    )
    if not override.is_file():
        print(
            "ERROR: missing oem/overrides/.../mobile/pages/connection_page.dart "
            "(refusing surgical RawAutocomplete edits)",
            file=sys.stderr,
        )
        raise SystemExit(1)

    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(override, path)
    text = path.read_text(encoding="utf-8", errors="ignore")
    if (
        "RawAutocomplete<" in text
        or "_allPeersLoader" in text
        or "PeerTabPage" in text
        or "SliverFillRemaining" in text
    ):
        print(
            "ERROR: mobile connection_page override still has autocomplete/PeerTab fill",
            file=sys.stderr,
        )
        raise SystemExit(1)
    print("Patched mobile connection_page.dart (full UI override)")

if __name__ == "__main__":
    raise SystemExit(main())
