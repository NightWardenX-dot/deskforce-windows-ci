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

/// Soft UI click — default OFF. Plays bundled wav when enabled.
Future<void> dfPlayClickSound() async {
  if (!dfClickSoundEnabled()) return;
  try {
    _cachedWav ??= await _ensureWav();
    final path = _cachedWav!.path;
    if (Platform.isWindows) {
      final escaped = path.replaceAll("'", "''");
      await Process.start(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "(New-Object Media.SoundPlayer '$escaped').Play()",
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return;
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
