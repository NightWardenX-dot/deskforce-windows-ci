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


class DeskForceUpdateBannerData {
  DeskForceUpdateBannerData({required this.info, required this.localVersion});
  final DeskForceUpdateInfo info;
  final String localVersion;
}

/// Non-blocking update hint shown on the home screen (dismissible).
final ValueNotifier<DeskForceUpdateBannerData?> dfUpdateBannerNotifier =
    ValueNotifier<DeskForceUpdateBannerData?>(null);

const _bannerDismissKey = 'df_update_banner_dismissed';

Future<bool> _isBannerDismissed(String remoteVersion) async {
  try {
    final prefs = await bind.mainGetLocalOption(key: _bannerDismissKey);
    return prefs.trim() == remoteVersion.trim();
  } catch (_) {
    return false;
  }
}

Future<void> _dismissBanner(String remoteVersion) async {
  dfUpdateBannerNotifier.value = null;
  try {
    await bind.mainSetLocalOption(key: _bannerDismissKey, value: remoteVersion);
  } catch (_) {}
}

Future<void> dfShowUpdateBannerIfNeeded(
  BuildContext context,
  DeskForceUpdateInfo info,
  String localVersion,
) async {
  if (await _isBannerDismissed(info.version)) return;
  dfUpdateBannerNotifier.value =
      DeskForceUpdateBannerData(info: info, localVersion: localVersion);
}

/// Subtle paper/brass banner — top of home screen, does not block connect flow.
Widget dfUpdateBannerHost(BuildContext context) {
  return ValueListenableBuilder<DeskForceUpdateBannerData?>(
    valueListenable: dfUpdateBannerNotifier,
    builder: (context, data, _) {
      if (data == null) return const SizedBox.shrink();
      final info = data.info;
      return Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF8F1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x55B8892A)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, color: _brass, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Доступно обновление ${info.version}',
                  style: TextStyle(
                    color: _ink.withOpacity(0.86),
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => dfShowUpdateDialog(context, info,
                    localVersion: data.localVersion),
                style: TextButton.styleFrom(
                  foregroundColor: _brass,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Обновление',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Скрыть',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: _ink.withOpacity(0.45)),
                onPressed: () => _dismissBanner(info.version),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class DeskForceUpdateInfo {
  DeskForceUpdateInfo({
    required this.platform,
    required this.version,
    required this.downloadUrl,
    required this.mandatory,
    required this.releaseNotes,
    required this.available,
    this.updateAvailable,
  });

  final String platform;
  final String version;
  final String downloadUrl;
  final bool mandatory;
  final String releaseNotes;
  final bool available;
  /// Server-side compare result when client sent ?version= (null = unknown).
  final bool? updateAvailable;

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
  final core = v.split('+').first.split('-').first.trim();
  final parts = core.split('.').where((p) => p.isNotEmpty).toList();
  while (parts.length < 3) {
    parts.add('0');
  }
  return parts.take(3).join('.');
}

/// Core numeric (RustDesk-style) for major.minor.patch only — ignores prerelease.
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
  return n;
}

/// Prerelease segment after first `-` and before `+` (empty = release).
String dfPrerelease(String v) {
  final noBuild = v.split('+').first.trim();
  final i = noBuild.indexOf('-');
  if (i < 0 || i + 1 >= noBuild.length) return '';
  return noBuild.substring(i + 1);
}

int _cmpIdent(String a, String b) {
  final ai = int.tryParse(a);
  final bi = int.tryParse(b);
  if (ai != null && bi != null) return ai.compareTo(bi);
  if (ai != null) return -1; // numeric < non-numeric (semver)
  if (bi != null) return 1;
  return a.compareTo(b);
}

/// Semver compare with prerelease: 1.2.0-beta.3 < 1.2.0-beta.4 < 1.2.0.
/// Returns negative if a<b, 0 if equal, positive if a>b.
int dfCompareVersions(String a, String b) {
  final core = dfVersionNumber(a).compareTo(dfVersionNumber(b));
  if (core != 0) return core;
  final pa = dfPrerelease(a);
  final pb = dfPrerelease(b);
  if (pa.isEmpty && pb.isEmpty) return 0;
  if (pa.isEmpty) return 1; // release > prerelease
  if (pb.isEmpty) return -1;
  final aa = pa.split('.');
  final bb = pb.split('.');
  final n = aa.length < bb.length ? aa.length : bb.length;
  for (var i = 0; i < n; i++) {
    final c = _cmpIdent(aa[i], bb[i]);
    if (c != 0) return c;
  }
  return aa.length.compareTo(bb.length);
}

bool dfIsNewerVersion(String remote, String local) =>
    dfCompareVersions(remote, local) > 0;

String dfCurrentPlatformKey() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  return 'windows';
}

Future<DeskForceUpdateInfo?> dfFetchUpdateInfo({
  String? platform,
  String? localVersion,
}) async {
  final plat = platform ?? dfCurrentPlatformKey();
  // Prefer API (platform slice); fall back to static update.json.
  try {
    final q = <String, String>{'platform': plat};
    if (localVersion != null && localVersion.trim().isNotEmpty) {
      q['version'] = localVersion.trim();
    }
    final api = Uri.parse(kDfUpdateApiUrl).replace(queryParameters: q);
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
  bool? updateAvail;
  if (map.containsKey('update_available')) {
    updateAvail = map['update_available'] == true;
  }
  return DeskForceUpdateInfo(
    platform: '${map['platform'] ?? plat}',
    version: version,
    downloadUrl: url,
    mandatory: map['mandatory'] == true,
    releaseNotes: '${map['release_notes'] ?? ''}'.trim(),
    available: map['available'] != false,
    updateAvailable: updateAvail,
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

/// Silent startup check: non-intrusive banner when a newer build is available.
bool dfUpdateNeeded(DeskForceUpdateInfo info, String local) {
  // Prefer server decision when present (helps older clients after API fixes).
  // Otherwise fall back to local semver compare (incl. 1.2.0-beta.N).
  if (info.updateAvailable != null) return info.updateAvailable!;
  return dfIsNewerVersion(info.version, local);
}

Future<void> dfCheckUpdateOnStartup(BuildContext context) async {
  try {
    final local = await dfLocalAppVersion();
    final info = await dfFetchUpdateInfo(localVersion: local);
    if (info == null || !info.hasDownload) return;
    if (!dfUpdateNeeded(info, local)) return;
    if (!context.mounted) return;
    await dfShowUpdateBannerIfNeeded(context, info, local);
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
    final info = await dfFetchUpdateInfo(localVersion: local);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;
    if (info == null || !info.hasDownload) {
      await _toast(context, 'Не удалось проверить обновления. Попробуйте позже.');
      return;
    }
    if (!dfUpdateNeeded(info, local)) {
      await _toast(context, 'У вас актуальная версия DeskForce ($local).');
      return;
    }
    await dfShowUpdateBannerIfNeeded(context, info, local);
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

