# DeskForce OEM — брендированные клиенты

Нужны **свои** приложения: Windows `.exe`, macOS `.dmg`, Android `.apk`, iOS `.ipa` — не stock RustDesk.

Основной путь: **форк** в `rustdesk-src/` + [`apply_branding.py`](apply_branding.py) (имя DeskForce, серверы/ключ вшиты, тема paper/brass как на сайте, упрощённый UI без LAN/избранного/АБ и без сетевых настроек).

Матрица платформ и требования к подписи: [`PLATFORMS.md`](PLATFORMS.md).

## Быстрый старт (self-build)

```bash
cp oem.env.example oem.env
# OEM_ID_SERVER / OEM_KEY_PUB / OEM_API_SERVER=https://deskforce.dr6ter.ru
# иконки в branding/

git -C rustdesk-src submodule update --init libs/hbb_common
set -a; source oem.env; set +a
python3 apply_branding.py   # идемпотентно

chmod +x build.sh build-all.sh
./build-all.sh config     # TOML для пилота
./build-all.sh windows    # на Windows / windows-latest (+ Flutter)
./build-all.sh linux      # Linux binary (скриншоты / проверка UI)
./build-all.sh android    # APK
./build-all.sh macos
./build-all.sh ios
```

Артефакты: `oem/dist/<platform>/`. Публикация: `../downloads/`.

## CI

Основные Flutter-сборки (`workflow_dispatch`):

| Workflow | Файл |
|----------|------|
| Windows | [`.github/workflows/oem-windows-flutter.yml`](../.github/workflows/oem-windows-flutter.yml) |
| Linux | [`.github/workflows/oem-linux-flutter.yml`](../.github/workflows/oem-linux-flutter.yml) |
| macOS (unsigned) | [`.github/workflows/oem-macos-flutter.yml`](../.github/workflows/oem-macos-flutter.yml) |
| Android | [`.github/workflows/oem-android-flutter.yml`](../.github/workflows/oem-android-flutter.yml) |

Зеркала: `oem/ci/`. Матрица платформ: [`PLATFORMS.md`](PLATFORMS.md).

Legacy matrix: [`.github/workflows/oem-client.yml`](../.github/workflows/oem-client.yml) (`config` / stubs).

macOS CI **не** подписывает и **не** нотаризует пакет (Apple certs не нужны).

## Раздача пользователям

1. Собрать артефакты CI → выложить на `https://<ваш-домен>/downloads/`
2. В админке дать ссылки (раздел клиент-конфига / внутренняя wiki)
3. Для Windows-парка: Intune/GPO + тихая установка

## OEM без bat/txt (рекомендуется)

Нужен **один файл** (`DeskForce.exe` / `DeskForce.apk`) с ID/Relay/API/Key внутри — без README, bat и toml у пользователя.

```bash
# конфиг: oem/rdgen/deskforce.json + oem.env
chmod +x generate-rdgen.sh
./generate-rdgen.sh windows   # ~30–45 мин (публичный RDGen)
./generate-rdgen.sh android
# артефакты → ../downloads/windows|android (только exe/apk + zip из одного файла)
```

Админка: **Система → Клиенты** — кнопки скачивания одного файла.

## Пилотный обходной путь

`package-clients.sh` кладёт **переименованный** stock RustDesk без sidecar-файлов в ZIP.
Сервер в бинарник **не** вшит — для продакшена используйте `generate-rdgen.sh` или self-build.

Для продаж «как RuDesktop» подписанные OEM-билды обязательны.

## AGPL

Клиент на базе RustDesk — AGPL-3.0. Заказчику on-prem нужны исходники модификаций.

## Клиентские обновления

Канал обновлений DeskForce (только `deskforce.dr6ter.ru`, не rustdesk.com):

- `https://deskforce.dr6ter.ru/downloads/update.json`
- `https://deskforce.dr6ter.ru/api/client/update?platform=windows`

Клиент (Windows Flutter OEM) при старте и из **Настройки → Обновления** сравнивает локальную версию (`OEM_APP_VERSION`, сейчас `1.2.0-beta.1`) с `platforms.<os>.version`. Если удалённая новее — диалог «Доступно обновление».

Синхронизация статусов при публикации:

```bash
OEM_APP_VERSION=1.2.0-beta.1 ./scripts/sync-client-update.sh --publish
```

Как выпустить новую версию:

1. Поднять `OEM_APP_VERSION` в `.github/workflows/oem-windows-flutter.yml` (и `oem/ci/…`), например `1.2.0-beta.2` или `1.2.0`
   (`apply_branding.py` нормализует до `X.Y.Z` или `X.Y.Z-prerelease` для Cargo/Flutter)
2. Собрать/опубликовать артефакты
3. Прогнать `sync-client-update.sh --publish` (обновит `update.json`, `manifest.json`, `build-status*.json`)
