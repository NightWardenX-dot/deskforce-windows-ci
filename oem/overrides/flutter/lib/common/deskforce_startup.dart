import 'dart:async';
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

/// Serialize window ops — beta.14 crashed when main.dart + home page
/// called maximize/setSize concurrently (3 overlapping runs).
Future<void>? _dfStartupWindowInFlight;
bool _dfStartupWindowDone = false;

bool dfLocalBool(String key) =>
    bind.mainGetLocalOption(key: key) == 'Y';

/// True when option is Y, or unset (DeskForce default ON for maximized start).
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

/// Primary-monitor work area. Avoid getWindowInfo before HWND is stable.
Future<Size> _workAreaSize() async {
  try {
    final screens = await window_size.getScreenList();
    if (screens.isNotEmpty) {
      final vf = screens.first.visibleFrame;
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
  // Never force a min size larger than the work area (beta.13 clip).
  final minW = math.min(480.0, math.max(320.0, work.width * 0.45));
  final minH = math.min(360.0, math.max(240.0, work.height * 0.45));
  try {
    await windowManager.setMinimumSize(Size(minW, minH));
  } catch (_) {}
}

Future<bool> _tryMaximizeOnce() async {
  try {
    // Never call setFullScreen during startup — exclusive FS + maximize races
    // crash window_manager / desktop_multi_window on some DPI setups (beta.14).
    if (await windowManager.isMaximized()) {
      stateGlobal.setMaximized(true);
      return true;
    }
    await windowManager.maximize();
    await Future.delayed(const Duration(milliseconds: 80));
    final ok = await windowManager.isMaximized();
    if (ok) stateGlobal.setMaximized(true);
    return ok;
  } catch (e) {
    debugPrint('maximize failed: $e');
    return false;
  }
}

Future<void> _fitWorkArea(Size work) async {
  final w = math.max(480.0, math.min(work.width * 0.92, work.width - 16));
  final h = math.max(360.0, math.min(work.height * 0.92, work.height - 16));
  try {
    await windowManager.setSize(Size(w, h));
    await windowManager.setAlignment(Alignment.center);
  } catch (e) {
    debugPrint('fitWorkArea failed: $e');
  }
}

Future<void> _applyStartupWindowBehaviorImpl({required bool force}) async {
  try {
    final work = await _workAreaSize();
    await _applySafeMinSize(work);

    if (dfLocalBool(kDfStartInTray)) {
      await windowManager.hide();
      _dfStartupWindowDone = true;
      return;
    }

    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}

    if (dfLocalBoolDefaultOn(kDfStartFullscreen)) {
      if (await _tryMaximizeOnce()) {
        _dfStartupWindowDone = true;
        return;
      }
      await Future.delayed(const Duration(milliseconds: 120));
      if (await _tryMaximizeOnce()) {
        _dfStartupWindowDone = true;
        return;
      }
      await _fitWorkArea(work);
      _dfStartupWindowDone = true;
      return;
    }

    await _fitWorkArea(work);
    _dfStartupWindowDone = true;
  } catch (e) {
    debugPrint('startup window behavior: $e');
  }
}

/// Concurrent callers share one in-flight Future (beta.14 native crash fix).
Future<void> dfApplyStartupWindowBehavior({bool force = false}) async {
  if (!force && _dfStartupWindowDone) return;
  if (_dfStartupWindowInFlight != null) {
    await _dfStartupWindowInFlight;
    if (!force && _dfStartupWindowDone) return;
  }
  final run = _applyStartupWindowBehaviorImpl(force: force);
  _dfStartupWindowInFlight = run;
  try {
    await run;
  } finally {
    if (identical(_dfStartupWindowInFlight, run)) {
      _dfStartupWindowInFlight = null;
    }
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
      stateGlobal.setMaximized(false);
      return;
    }
    await windowManager.maximize();
    stateGlobal.setMaximized(true);
  } catch (_) {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
        stateGlobal.setMaximized(false);
      } else {
        await windowManager.maximize();
        stateGlobal.setMaximized(true);
      }
    } catch (_) {}
  }
}
