import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/common/deskforce_update.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

const kDfAutostart = 'df-autostart';
const kDfStartInTray = 'df-start-in-tray';
const kDfStartFullscreen = 'df-start-fullscreen';

/// Serialize all startup window ops (beta.13–15 native crashes from concurrent
/// maximize/setSize/setFullScreen across main.dart + home page).
Future<void>? _dfStartupWindowInFlight;
bool _dfStartupWindowDone = false;

bool dfLocalBool(String key) =>
    bind.mainGetLocalOption(key: key) == 'Y';

/// True when option is Y, or unset (legacy helper — prefer explicit defaults).
bool dfLocalBoolDefaultOn(String key) {
  final v = bind.mainGetLocalOption(key: key);
  if (v.isEmpty) return true;
  return v == 'Y';
}

/// True only when explicitly Y (unset = OFF). Used for maximize-on-start.
bool dfLocalBoolDefaultOff(String key) {
  final v = bind.mainGetLocalOption(key: key);
  if (v.isEmpty) return false;
  return v == 'Y';
}

Future<void> dfSetLocalBool(String key, bool value) async {
  await bind.mainSetLocalOption(key: key, value: value ? 'Y' : 'N');
}

String get _startupShortcutPath {
  final appData = Platform.environment['APPDATA'] ?? '';
  return '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\DeskForce.lnk';
}

String get _trayStartupShortcutPath {
  final appData = Platform.environment['APPDATA'] ?? '';
  return '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\DeskForce Tray.lnk';
}

/// Spawn native `--tray` process (notification area icon). Idempotent via Rust check_process.
Future<void> dfEnsureNativeTray() async {
  if (!Platform.isWindows) return;
  try {
    final exe = Platform.resolvedExecutable;
    await Process.start(
      exe,
      ['--tray'],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
  } catch (e) {
    debugPrint('native tray spawn failed: $e');
  }
}

Future<bool> _createWindowsShortcut(
  String lnk,
  String exe, {
  String arguments = '',
  String description = 'DeskForce',
}) async {
  final dir = Directory(lnk).parent;
  if (!await dir.exists()) await dir.create(recursive: true);
  final workDir = File(exe).parent.path.replaceAll("'", "''");
  final desc = description.replaceAll("'", "''");
  final argsPs = arguments.isEmpty
      ? ''
      : "\n\$s.Arguments = '${arguments.replaceAll("'", "''")}'";
  final ps = r"""
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut('""" + lnk + r"""')
$s.TargetPath = '""" + exe + r"""'
$s.WorkingDirectory = '""" + workDir + r"""'
$s.Description = '""" + desc + r"""'""" + argsPs + r"""
$s.Save()
""";
  final r = await Process.run(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-Command', ps],
    runInShell: true,
  );
  return r.exitCode == 0;
}

/// Create/remove per-user Startup shortcuts (main app + native tray).
Future<bool> dfSetWindowsAutostart(bool enable) async {
  if (!Platform.isWindows) return false;
  final exe = Platform.resolvedExecutable;
  try {
    if (!enable) {
      for (final path in [_startupShortcutPath, _trayStartupShortcutPath]) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
      await dfSetLocalBool(kDfAutostart, false);
      return true;
    }
    final okMain = await _createWindowsShortcut(_startupShortcutPath, exe);
    final okTray = await _createWindowsShortcut(
      _trayStartupShortcutPath,
      exe,
      arguments: '--tray',
      description: 'DeskForce (трей)',
    );
    if (!okMain || !okTray) {
      debugPrint('autostart shortcut failed main=$okMain tray=$okTray');
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
    return await File(_startupShortcutPath).exists() ||
        await File(_trayStartupShortcutPath).exists();
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
  // Never force a min size larger than the work area (beta.13 clip/crash).
  final minW = math.min(400.0, math.max(280.0, work.width * 0.40));
  final minH = math.min(300.0, math.max(200.0, work.height * 0.40));
  try {
    await windowManager.setMinimumSize(Size(minW, minH));
  } catch (e) {
    debugPrint('setMinimumSize failed: $e');
  }
}

/// Soft maximize — never exclusive fullscreen. Any failure → false.
Future<bool> _tryMaximizeOnce() async {
  try {
    if (await windowManager.isMaximized()) {
      stateGlobal.setMaximized(true);
      return true;
    }
    await windowManager.maximize();
    await Future.delayed(const Duration(milliseconds: 60));
    final ok = await windowManager.isMaximized();
    if (ok) stateGlobal.setMaximized(true);
    return ok;
  } catch (e) {
    debugPrint('maximize failed: $e');
    return false;
  }
}

/// Fit a safe normal window inside the work area (high-DPI / small laptop safe).
Future<void> _fitWorkArea(Size work) async {
  final maxW = math.max(320.0, work.width - 24);
  final maxH = math.max(240.0, work.height - 24);
  final w = math.min(maxW, math.max(480.0, work.width * 0.82));
  final h = math.min(maxH, math.max(360.0, work.height * 0.82));
  final safeW = math.min(w, maxW);
  final safeH = math.min(h, maxH);
  try {
    await windowManager.setSize(Size(safeW, safeH));
    await Future.delayed(const Duration(milliseconds: 30));
    await windowManager.setAlignment(Alignment.center);
  } catch (e) {
    debugPrint('fitWorkArea failed: $e');
    try {
      await windowManager.setSize(const Size(640, 480));
      await windowManager.setAlignment(Alignment.center);
    } catch (_) {}
  }
}

Future<void> _applyStartupWindowBehaviorImpl({required bool force}) async {
  try {
    if (Platform.isWindows) {
      await dfRememberPackerExeForUpdate();
      await dfEnsureNativeTray();
    }
    final work = await _workAreaSize();
    await _applySafeMinSize(work);

    if (dfLocalBool(kDfStartInTray)) {
      try {
        await windowManager.hide();
      } catch (_) {}
      _dfStartupWindowDone = true;
      return;
    }

    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('show/focus failed: $e');
    }

    // beta.16: maximize-on-start is OPT-IN only (unset = OFF).
    // Never call setFullScreen during startup — exclusive FS crashed Win
    // window_manager / desktop_multi_window on some DPI setups (beta.13–15).
    if (dfLocalBoolDefaultOff(kDfStartFullscreen)) {
      if (!await _tryMaximizeOnce()) {
        await _fitWorkArea(work);
      }
      _dfStartupWindowDone = true;
      return;
    }

    // Default path: safe normal window fitting work area.
    await _fitWorkArea(work);
    _dfStartupWindowDone = true;
  } catch (e, st) {
    debugPrint('startup window behavior: $e\n$st');
    try {
      await windowManager.setMinimumSize(const Size(320, 240));
      await windowManager.setSize(const Size(800, 600));
      await windowManager.show();
    } catch (_) {}
    _dfStartupWindowDone = true;
  }
}

/// Concurrent callers share one in-flight Future.
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
