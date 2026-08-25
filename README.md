# DeskForce Windows CI (public mirror)

Public build-only mirror for **DeskForce Windows Flutter (paper/brass)** OEM client.

- Clones [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) at tag `1.4.6`
- Applies DeskForce branding via `oem/apply_branding.py`
- Builds on GitHub-hosted `windows-2022` (free for public repos)
- Uploads artifacts: `DeskForce.exe` + `DeskForce-Windows-paper-brass.zip`

**No private keys, API tokens, or server secrets.**  
Baked config uses the already-public hbbs **public** key, ID/relay IP, and API URL from the DeskForce site.

Trigger: **Actions → DeskForce Windows Flutter (paper/brass) → Run workflow**

Private product sources stay in `NightWardenX-dot/deskforce-ud` (private).
