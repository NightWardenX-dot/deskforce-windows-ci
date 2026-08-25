# Брендинг DeskForce (иконки / лого)

Положите сюда файлы перед сборкой:

| Файл | Назначение | Рекомендуемый размер |
|------|------------|----------------------|
| `app_icon.png` | Иконка приложения (квадрат) | 1024×1024 |
| `app_logo.png` | Лого в UI | 512×512 или шире |
| `app_icon.ico` | Windows | multi-size ico |
| `app_icon.icns` | macOS | icns |
| `adaptive_icon.png` | Android | 512×512 |

Скрипт `apply_branding.py` копирует их в дерево RustDesk (`res/`, Flutter assets) при наличии.
