# DeskForce Windows (paper/brass)

Нужен Windows с Git, Rust 1.75, Flutter 3.24.5, VS 2022 C++, vcpkg.

```powershell
git clone --depth 1 --branch 1.4.6 --recurse-submodules https://github.com/rustdesk/rustdesk.git
# скопировать oem/apply_branding.py, oem/branding, задать env из oem.env
$env:RUSTDESK_SRC="...\rustdesk"
$env:OEM_APP_NAME="DeskForce"
$env:OEM_ID_SERVER="78.29.49.98"
$env:OEM_RELAY_SERVER="78.29.49.98"
$env:OEM_API_SERVER="https://deskforce.dr6ter.ru"
$env:OEM_KEY_PUB="ERushCbh73QS5YNPuOvqK5M3Yx9v9z+8Ft5O+iAQevg="
python oem\apply_branding.py
cd rustdesk
python build.py --portable --hwcodec --flutter --vram
```

Либо: `gh auth refresh -h github.com -s repo,workflow` и запушить `.github/workflows/oem-windows-flutter.yml`.
