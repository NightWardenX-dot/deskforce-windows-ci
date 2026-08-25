import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:window_manager/window_manager.dart';

const kDfAutostart = 'df-autostart';
const kDfStartInTray = 'df-start-in-tray';
const kDfStartFullscreen = 'df-start-fullscreen';

bool dfLocalBool(String key) =>
    bind.mainGetLocalOption(key: key) == 'Y';

/// True when option is Y, or unset (DeskForce default ON for fullscreen).
bool dfLocalBoolDefaultOn(String key) {
  final v = bind.mainGetLocalOption(key: key);
  if (v.isEmpty) return true;
  return v == 'Y';
}

Future<void> dfSetLocalBool(String key, bool value) async {
  await bind.mainSetLocalOption(key: key, value: value ? 'Y' : 'N');
}

String get _startupShortcutPath {
  final appData = Platform.environment['APPDATA'] ?? '';
  return '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\DeskForce.lnk';
}

/// Create/remove a per-user Startup shortcut to this DeskForce.exe.
Future<bool> dfSetWindowsAutostart(bool enable) async {
  if (!Platform.isWindows) return false;
  final exe = Platform.resolvedExecutable;
  final lnk = _startupShortcutPath;
  try {
    if (!enable) {
      final f = File(lnk);
      if (await f.exists()) await f.delete();
      await dfSetLocalBool(kDfAutostart, false);
      return true;
    }
    final dir = Directory(lnk).parent;
    if (!await dir.exists()) await dir.create(recursive: true);
    final workDir = File(exe).parent.path.replaceAll("'", "''");
    final ps = '''
\$ws = New-Object -ComObject WScript.Shell
\$s = \$ws.CreateShortcut('$lnk')
\$s.TargetPath = '$exe'
\$s.WorkingDirectory = '$workDir'
\$s.Description = 'DeskForce'
\$s.Save()
''';
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', ps],
      runInShell: true,
    );
    if (r.exitCode != 0) {
      debugPrint('autostart failed: ${r.stderr}');
      return false;
    }
    await dfSetLocalBool(kDfAutostart, true);
    return true;
  } catch (e) {
    debugPrint('autostart error: $e');
    return false;
  }
}

Future<bool> dfIsWindowsAutostartEnabled() async {
  if (!Platform.isWindows) return false;
  try {
    return await File(_startupShortcutPath).exists();
  } catch (_) {
    return dfLocalBool(kDfAutostart);
  }
}

Future<bool> _tryMaximize() async {
  try {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 30));
    }
  } catch (_) {}
  try {
    if (!(await windowManager.isMaximized())) {
      await windowManager.maximize();
    }
    final ok = await windowManager.isMaximized();
    if (ok) {
      stateGlobal.setMaximized(true);
    }
    return ok;
  } catch (e) {
    debugPrint('maximize failed: $e');
    return false;
  }
}

/// Apply tray / maximized / size after the main window is ready.
///
/// Windows drops maximize when requested before show. Show first, then
/// maximize with post-frame retries so the window actually sticks maximized.
Future<void> dfApplyStartupWindowBehavior() async {
  try {
    await windowManager.setMinimumSize(const Size(720, 640));
    const target = Size(960, 860);

    if (dfLocalBool(kDfStartInTray)) {
      await windowManager.hide();
      return;
    }

    // Show first — maximize-before-show is unreliable on Windows.
    await windowManager.show();
    await windowManager.focus();

    // Default ON: expand to work-area (maximize). Exclusive fullscreen
    // remains available via «Полный экран сейчас» in settings.
    if (dfLocalBoolDefaultOn(kDfStartFullscreen)) {
      for (final delayMs in <int>[0, 50, 150, 400, 900]) {
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        if (await _tryMaximize()) {
          return;
        }
      }
      try {
        await windowManager.setFullScreen(true);
      } catch (_) {}
      return;
    }

    final cur = await windowManager.getSize();
    if (cur.width < 900 || cur.height < 780) {
      await windowManager.setSize(target);
    }
    await windowManager.setAlignment(Alignment.center);
  } catch (e) {
    debugPrint('startup window behavior: $e');
  }
}

Future<void> dfToggleFullscreen() async {
  try {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      return;
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
      return;
    }
    await windowManager.maximize();
  } catch (_) {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }
}
