import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// DeskForce-only update channel (never third-party hosts).
const kDfUpdateHost = 'deskforce.dr6ter.ru';
const kDfUpdateJsonUrl = 'https://$kDfUpdateHost/downloads/update.json';
const kDfUpdateApiUrl = 'https://$kDfUpdateHost/api/client/update';

const _ink = Color(0xFF12161C);
const _paper = Color(0xFFF3EFE6);
const _card = Color(0xFFFBF8F1);
const _brass = Color(0xFFB8892A);

class DeskForceUpdateInfo {
  DeskForceUpdateInfo({
    required this.platform,
    required this.version,
    required this.downloadUrl,
    required this.mandatory,
    required this.releaseNotes,
    required this.available,
  });

  final String platform;
  final String version;
  final String downloadUrl;
  final bool mandatory;
  final String releaseNotes;
  final bool available;

  bool get hasDownload =>
      available && downloadUrl.isNotEmpty && _isAllowedUrl(downloadUrl);
}

bool _isAllowedUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return false;
  if (u.scheme != 'https') return false;
  return u.host == kDfUpdateHost;
}

/// Pad to major.minor.patch so 1.0 and 1.0.0 compare equal.
String dfNormalizeVersion(String v) {
  final main = v.split('-').first.trim();
  final parts = main.split('.').where((p) => p.isNotEmpty).toList();
  while (parts.length < 3) {
    parts.add('0');
  }
  return parts.take(3).join('.');
}

/// Numeric compare aligned with RustDesk get_version_number.
int dfVersionNumber(String v) {
  final main = dfNormalizeVersion(v);
  var n = 0;
  var last = 0;
  for (final part in main.split('.')) {
    last = int.tryParse(part) ?? 0;
    n = n * 1000 + last;
  }
  n -= last;
  n += last * 10;
  final dash = v.split('-');
  if (dash.length > 1) {
    n += int.tryParse(dash[1].split(RegExp(r'[^0-9]')).first) ?? 0;
  }
  return n;
}

bool dfIsNewerVersion(String remote, String local) =>
    dfVersionNumber(remote) > dfVersionNumber(local);

String dfCurrentPlatformKey() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  return 'windows';
}

Future<DeskForceUpdateInfo?> dfFetchUpdateInfo({String? platform}) async {
  final plat = platform ?? dfCurrentPlatformKey();
  // Prefer API (platform slice); fall back to static update.json.
  try {
    final api = Uri.parse('$kDfUpdateApiUrl?platform=$plat');
    final resp = await http.get(api).timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      final map = jsonDecode(utf8.decode(resp.bodyBytes));
      if (map is Map<String, dynamic>) {
        return _parsePlatform(map, plat);
      }
    }
  } catch (_) {}

  try {
    final resp =
        await http.get(Uri.parse(kDfUpdateJsonUrl)).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final doc = jsonDecode(utf8.decode(resp.bodyBytes));
    if (doc is! Map<String, dynamic>) return null;
    final platforms = doc['platforms'];
    if (platforms is! Map<String, dynamic>) return null;
    final entry = platforms[plat];
    if (entry is! Map<String, dynamic>) return null;
    return _parsePlatform(entry, plat);
  } catch (_) {
    return null;
  }
}

DeskForceUpdateInfo? _parsePlatform(Map<String, dynamic> map, String plat) {
  final version = '${map['version'] ?? ''}'.trim();
  if (version.isEmpty) return null;
  var url = '${map['download_url'] ?? ''}'.trim();
  final urls = map['download_urls'];
  if (url.isEmpty && urls is Map) {
    for (final key in ['exe', 'apk', 'deb', 'appimage', 'zip']) {
      final v = '${urls[key] ?? ''}'.trim();
      if (v.isNotEmpty) {
        url = v;
        break;
      }
    }
  }
  if (url.isNotEmpty && !_isAllowedUrl(url)) {
    // Refuse any non-DeskForce host.
    url = '';
  }
  return DeskForceUpdateInfo(
    platform: '${map['platform'] ?? plat}',
    version: version,
    downloadUrl: url,
    mandatory: map['mandatory'] == true,
    releaseNotes: '${map['release_notes'] ?? ''}'.trim(),
    available: map['available'] != false,
  );
}

Future<String> dfLocalAppVersion() async {
  try {
    final v = await bind.mainGetVersion();
    if (v.trim().isNotEmpty) return v.trim();
  } catch (_) {}
  return '1.0';
}

Future<void> dfDownloadAndExecute(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    final tempDir = await getTemporaryDirectory();
    final fileName = uri.pathSegments.last;
    final filePath = p.join(tempDir.path, fileName);

    final resp = await http.get(uri).timeout(const Duration(seconds: 60));
    if (resp.statusCode == 200) {
      await File(filePath).writeAsBytes(resp.bodyBytes);
      if (context.mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: Card(
              color: _card,
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: _brass),
                    ),
                    SizedBox(width: 14),
                    Text('Запуск установки...', style: TextStyle(color: _ink)),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      await Process.start(filePath, [], runInShell: true);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } else {
      throw Exception('HTTP ${resp.statusCode}');
    }
  } catch (e) {
    debugPrint('DeskForce direct update failed: $e');
    if (context.mounted) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

/// Silent startup check: show dialog only when a newer build is available.
Future<void> dfCheckUpdateOnStartup(BuildContext context) async {
  try {
    final local = await dfLocalAppVersion();
    final info = await dfFetchUpdateInfo();
    if (info == null || !info.hasDownload) return;
    if (!dfIsNewerVersion(info.version, local)) return;
    if (!context.mounted) return;
    await dfShowUpdateDialog(context, info, localVersion: local);
  } catch (e) {
    debugPrint('DeskForce update check: $e');
  }
}

/// Manual check from Настройки — always reports result.
Future<void> dfCheckUpdateManual(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        color: _card,
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: _brass),
              ),
              SizedBox(width: 14),
              Text('Проверка обновлений…', style: TextStyle(color: _ink)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    final local = await dfLocalAppVersion();
    final info = await dfFetchUpdateInfo();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;
    if (info == null || !info.hasDownload) {
      await _toast(context, 'Не удалось проверить обновления. Попробуйте позже.');
      return;
    }
    if (!dfIsNewerVersion(info.version, local)) {
      await _toast(context, 'У вас актуальная версия DeskForce ($local).');
      return;
    }
    await dfShowUpdateDialog(context, info, localVersion: local);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      await _toast(context, 'Ошибка проверки обновлений.');
    }
    debugPrint('DeskForce manual update: $e');
  }
}

Future<void> _toast(BuildContext context, String msg) async {
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _card,
      title: const Text('Обновление', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
      content: Text(msg, style: TextStyle(color: _ink.withOpacity(0.8))),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK', style: TextStyle(color: _brass, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

Future<void> dfShowUpdateDialog(
  BuildContext context,
  DeskForceUpdateInfo info, {
  required String localVersion,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: !info.mandatory,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: _paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0x66B8892A)),
        ),
        title: Row(
          children: const [
            Icon(Icons.system_update_alt, color: _brass),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Доступно обновление',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Установлено: $localVersion → доступно: ${info.version}',
                style: TextStyle(color: _ink.withOpacity(0.75), fontSize: 14),
              ),
              if (info.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0x3312161C)),
                  ),
                  child: Text(
                    info.releaseNotes,
                    style: TextStyle(color: _ink.withOpacity(0.85), height: 1.4, fontSize: 13.5),
                  ),
                ),
              ],
              if (info.mandatory) ...[
                const SizedBox(height: 10),
                const Text(
                  'Это обязательное обновление.',
                  style: TextStyle(color: Color(0xFF8B3A1A), fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Позже', style: TextStyle(color: _ink.withOpacity(0.55))),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _brass,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () async {
              await dfDownloadAndExecute(ctx, info.downloadUrl);
              if (ctx.mounted && !info.mandatory) Navigator.of(ctx).pop();
            },
            child: const Text('Скачать / Установить'),
          ),
        ],
      );
    },
  );
}

