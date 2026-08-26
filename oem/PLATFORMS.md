# DeskForce — клиенты по платформам

Для конкурента RuDesktop УД нужны **свои** установщики, не stock RustDesk с ручным TOML.

| Платформа | Артефакт | Сборка | Подпись / магазин | Статус пайплайна |
|-----------|----------|--------|-------------------|------------------|
| **Windows** | `DeskForce.exe` / portable ZIP | GitHub `windows-2022` | Authenticode (желательно) | `oem-windows-flutter.yml` |
| **macOS** | `DeskForce.dmg` (+ ZIP `.app`) | GitHub `macos-14` (arm64) | **не в CI** (unsigned OK) | `oem-macos-flutter.yml` |
| **Android** | `DeskForce.apk` / `.aab` | Ubuntu + Flutter | Play Console или sidecar APK | `oem-android-flutter.yml` |
| **iOS** | `DeskForce.ipa` | **только macOS** + Xcode | Apple Developer + TestFlight/Enterprise | Ручной/gated job |
| **Linux** | `.deb` amd64 | Ubuntu 22.04 | опционально | `oem-linux-flutter.yml` |

Зеркала workflow (документация / копипаст): `oem/ci/*.yml` → канон в `.github/workflows/`.

## Как запустить CI (self-build Flutter)

В GitHub → **Actions** → выбрать workflow → **Run workflow** (`workflow_dispatch`):

| Workflow | Файл | Артефакт |
|----------|------|----------|
| DeskForce Windows Flutter | `.github/workflows/oem-windows-flutter.yml` | `DeskForce-Windows-paper-brass` |
| DeskForce Linux Flutter | `.github/workflows/oem-linux-flutter.yml` | `DeskForce-Linux-amd64` |
| DeskForce macOS Flutter (unsigned) | `.github/workflows/oem-macos-flutter.yml` | `DeskForce-macOS` |
| DeskForce Android Flutter | `.github/workflows/oem-android-flutter.yml` | APK artifact |

Публикация: скачать артефакт → положить в `downloads/<os>/` → `OEM_APP_VERSION=… ./scripts/sync-client-update.sh --publish`.

### macOS — unsigned

Сборка **без** Apple Developer ID и **без** notarization. Gatekeeper предупредит при первом открытии:

1. Смонтировать `DeskForce.dmg`, перетащить в Applications.
2. ПКМ по приложению → **Открыть**, или `xattr -cr /Applications/DeskForce.app`.

Подпись/нотаризация — отдельный этап (секреты `MACOS_P12_*`), в текущем пайплайне **не требуются**.

Версия канала Mac: `OEM_APP_VERSION` в workflow (сейчас `1.2.0-beta.4`).

## Два рабочих пути

### A. Self-build (наш форк, AGPL)

1. Брендинг: имя, иконки в `oem/branding/`, ID/Relay/API/Key.
2. Сборка из исходников RustDesk `1.4.6+` (desktop) / Flutter (mobile).
3. Раздача с вашего сайта / админки (не через rustdesk.com).

Подходит для on-prem и контроля кода. Обязательно: оферта исходников по AGPL.

### B. Generator (быстрее к пилоту)

- RustDesk Server Pro Custom Client Generator (платный upstream), или
- community builders (rdgen и аналоги) — Windows / macOS / Android из UI.

Используйте для первых пилотов, параллельно поднимая self-build CI (путь A).

## iOS — отдельно

App Store / TestFlight требуют:

- Apple Developer Program (~$99/год)
- Bundle ID, сертификаты, provisioning
- macOS + Xcode build
- Политика удалённого доступа Apple (review может затянуться)

Для B2B часто достаточно: **Windows + Android + macOS** на старте; iOS — фаза 2 или MDM/enterprise.

## Что видит пользователь

1. Скачал `DeskForce` под свою ОС (не «RustDesk»).
2. Установил — серверы уже внутри (OEM).
3. Логин доменным/локальным паролем → работа.

Раздача: страница загрузок / раздел в админке **Система → Клиенты** (см. `client_downloads`).
