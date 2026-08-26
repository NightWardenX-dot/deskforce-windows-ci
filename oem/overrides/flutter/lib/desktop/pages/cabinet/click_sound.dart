import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path_provider/path_provider.dart';

const kDfClickSound = 'deskforce-click-sound';

bool dfClickSoundEnabled() =>
    bind.mainGetLocalOption(key: kDfClickSound) == 'Y';

Future<void> dfSetClickSoundEnabled(bool value) async {
  await bind.mainSetLocalOption(key: kDfClickSound, value: value ? 'Y' : 'N');
}

File? _cachedWav;

String _windowsPowerShell() {
  const full =
      r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';
  if (File(full).existsSync()) return full;
  return 'powershell';
}

/// Soft UI click — default OFF. Plays bundled wav when enabled.
Future<void> dfPlayClickSound() async {
  if (!dfClickSoundEnabled()) return;
  try {
    _cachedWav ??= await _ensureWav();
    final path = _cachedWav!.path;
    if (Platform.isWindows) {
      // SoundPlayer.Play() returns immediately; a detached powershell would
      // exit and tear down async playback → silence. PlaySync keeps it alive.
      final escaped = path.replaceAll("'", "''");
      await Process.start(
        _windowsPowerShell(),
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "(New-Object Media.SoundPlayer '$escaped').PlaySync()",
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return;
    }
    if (Platform.isMacOS) {
      try {
        final r = await Process.run('afplay', [path]);
        if (r.exitCode == 0) return;
      } catch (_) {}
    }
    if (Platform.isLinux) {
      for (final cmd in [
        ['paplay', path],
        ['aplay', '-q', path],
      ]) {
        try {
          final r = await Process.run(cmd.first, cmd.sublist(1));
          if (r.exitCode == 0) return;
        } catch (_) {}
      }
    }
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }
}

Future<File> _ensureWav() async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/deskforce_ui_click.wav');
  if (await f.exists() && await f.length() > 100) return f;
  final data = await rootBundle.load('assets/sounds/ui_click.wav');
  await f.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true);
  return f;
}

/// Primary button helper: play click then invoke [onPressed].
VoidCallback? dfClickWrap(VoidCallback? onPressed) {
  if (onPressed == null) return null;
  return () {
    dfPlayClickSound();
    onPressed();
  };
}
