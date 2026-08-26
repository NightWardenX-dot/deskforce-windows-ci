import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

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


/// Primary-monitor work area (excludes taskbar). Falls back to a safe laptop size.
Future<Size> _workAreaSize() async {
  try {
    final screens = await window_size.getScreenList();
    if (screens.isNotEmpty) {
      // Prefer the screen that currently hosts the window; else first.
      window_size.Screen screen = screens.first;
      try {
        final info = await window_size.getWindowInfo();
        final host = info.screen;
        if (host != null) screen = host;
      } catch (_) {}
      final vf = screen.visibleFrame;
      if (vf.width >= 320 && vf.height >= 240) {
        return Size(vf.width, vf.height);
      }
    }
  } catch (e) {
    debugPrint('workAreaSize failed: $e');
  }
  return const Size(1280, 720);
}

Future<void> _applySafeMinSize(Size work) async {
  // Never force a min size larger than the work area — that clips the window
  // on 1366x768 / high-DPI laptops (beta.13 symptom).
  final minW = math.min(480.0, math.max(320.0, work.width * 0.45));
  final minH = math.min(360.0, math.max(240.0, work.height * 0.45));
  try {
    await windowManager.setMinimumSize(Size(minW, minH));
  } catch (_) {}
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
      await Future.delayed(const Duration(milliseconds: 40));
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

/// Fit ~95% of work area, centered — used when maximize is unavailable.
Future<void> _fitWorkArea(Size work) async {
  final w = math.max(480.0, work.width * 0.95);
  final h = math.max(360.0, work.height * 0.95);
  try {
    await windowManager.setSize(Size(w, h));
    await windowManager.setAlignment(Alignment.center);
  } catch (e) {
    debugPrint('fitWorkArea failed: $e');
  }
}

/// Apply tray / maximized / size after the main window is ready.
///
/// Windows drops maximize when requested before show. Show first, then
/// maximize with post-frame retries. Fixed 960x860 defaults were larger than
/// many laptop work areas and left the window clipped off-screen.
Future<void> dfApplyStartupWindowBehavior() async {
  try {
    final work = await _workAreaSize();
    await _applySafeMinSize(work);

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
      for (final delayMs in <int>[0, 80, 200, 450, 900]) {
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        if (await _tryMaximize()) {
          return;
        }
      }
      // Do NOT fall back to exclusive fullscreen — that feels broken and
      // still fails when the initial size exceeded the work area. Fit instead.
      await _fitWorkArea(work);
      return;
    }

    await _fitWorkArea(work);
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
