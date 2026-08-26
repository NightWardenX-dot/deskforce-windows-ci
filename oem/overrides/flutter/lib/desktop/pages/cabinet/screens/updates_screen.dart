import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/deskforce_update.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const _kChangelogUrl = 'https://deskforce.dr6ter.ru/downloads/changelog.json';
const _kUpdateJsonUrl = 'https://deskforce.dr6ter.ru/downloads/update.json';

class CabinetUpdatesScreen extends StatefulWidget {
  const CabinetUpdatesScreen({Key? key}) : super(key: key);

  @override
  State<CabinetUpdatesScreen> createState() => _CabinetUpdatesScreenState();
}

class _CabinetUpdatesScreenState extends State<CabinetUpdatesScreen> {
  List<Map<String, dynamic>> _entries = [];
  Map<String, dynamic>? _platformUpdate;
  String _localVersion = '';
  bool _loading = true;
  String _error = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final local = await dfLocalAppVersion();
    Map<String, dynamic>? plat;
    final entries = <Map<String, dynamic>>[];

    try {
      final res = await http
          .get(Uri.parse(_kChangelogUrl))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final json = jsonDecode(utf8.decode(res.bodyBytes));
        if (json is Map && json['entries'] is List) {
          for (final e in json['entries'] as List) {
            if (e is Map) entries.add(Map<String, dynamic>.from(e));
          }
        }
      }
    } catch (_) {}

    try {
      final res = await http
          .get(Uri.parse(_kUpdateJsonUrl))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final json = jsonDecode(utf8.decode(res.bodyBytes));
        if (json is Map && json['platforms'] is Map) {
          final platforms = Map<String, dynamic>.from(json['platforms'] as Map);
          final key = dfCurrentPlatformKey();
          final p = platforms[key];
          if (p is Map) plat = Map<String, dynamic>.from(p);
        }
      }
    } catch (e) {
      if (entries.isEmpty) {
        _error = 'Не удалось загрузить журнал обновлений.';
      }
    }

    // If changelog empty, synthesize one entry from update.json
    if (entries.isEmpty && plat != null) {
      entries.add({
        'version': plat['version'] ?? '',
        'date': '',
        'channel': plat['platform'] ?? '',
        'highlights': [
          if ((plat['release_notes'] ?? '').toString().isNotEmpty)
            plat['release_notes'].toString(),
        ],
      });
    }

    if (!mounted) return;
    setState(() {
      _localVersion = local;
      _platformUpdate = plat;
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      await dfPlayClickSound();
      await dfCheckUpdateManual(context);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openDownload() async {
    await dfPlayClickSound();
    final url = (_platformUpdate?['download_url'] ??
            'https://deskforce.dr6ter.ru/downloads/')
        .toString();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final remoteVer = (_platformUpdate?['version'] ?? '').toString();
    final notes = (_platformUpdate?['release_notes'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              Expanded(
                child: DfCabinetTheme.heading('Обновления',
                    subtitle: 'Журнал версий и проверка обновлений DeskForce.'),
              ),
              IconButton(
                tooltip: 'Обновить список',
                onPressed: _loading ? null : dfClickWrap(_load),
                icon: const Icon(Icons.refresh, color: DfCabinetTheme.brass),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: DfCabinetTheme.brass))
              : RefreshIndicator(
                  color: DfCabinetTheme.brass,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                    children: [
                      if (_error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_error,
                              style: const TextStyle(
                                  color: DfCabinetTheme.danger, fontSize: 13)),
                        ),
                      DfCabinetTheme.panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Текущая установка',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: DfCabinetTheme.ink)),
                            const SizedBox(height: 8),
                            Text(
                              _localVersion.isEmpty
                                  ? 'Версия клиента не определена'
                                  : 'У вас: $_localVersion',
                              style: TextStyle(
                                  color: DfCabinetTheme.ink.withOpacity(0.7),
                                  fontSize: 14),
                            ),
                            if (remoteVer.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'На сервере: $remoteVer',
                                style: TextStyle(
                                    color: DfCabinetTheme.ink.withOpacity(0.7),
                                    fontSize: 14),
                              ),
                            ],
                            if (notes.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(notes,
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: DfCabinetTheme.ink
                                          .withOpacity(0.6))),
                            ],
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                ElevatedButton(
                                  style: DfCabinetTheme.primaryButton(),
                                  onPressed:
                                      _checking ? null : dfClickWrap(_checkUpdate),
                                  child: Text(
                                      _checking
                                          ? 'Проверка…'
                                          : 'Проверить обновления',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ),
                                OutlinedButton(
                                  style: DfCabinetTheme.ghostButton(),
                                  onPressed: dfClickWrap(_openDownload),
                                  child: const Text('Скачать с сайта',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      DfCabinetTheme.sectionTitle('Лог обновлений'),
                      const SizedBox(height: 10),
                      if (_entries.isEmpty)
                        Text('Журнал пока пуст',
                            style: TextStyle(
                                color: DfCabinetTheme.ink.withOpacity(0.5)))
                      else
                        ..._entries.map((e) {
                          final ver = (e['version'] ?? '').toString();
                          final date = (e['date'] ?? '').toString();
                          final channel = (e['channel'] ?? '').toString();
                          final highlights = <String>[];
                          final h = e['highlights'];
                          if (h is List) {
                            for (final x in h) {
                              final s = '$x'.trim();
                              if (s.isNotEmpty) highlights.add(s);
                            }
                          }
                          final isCurrent = ver.isNotEmpty &&
                              _localVersion.isNotEmpty &&
                              ver == _localVersion;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DfCabinetTheme.panel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        ver.isEmpty ? '—' : ver,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: DfCabinetTheme.brass),
                                      ),
                                      if (isCurrent) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0x1A34D399),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text('установлена',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: DfCabinetTheme.ok)),
                                        ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        [
                                          if (date.isNotEmpty) date,
                                          if (channel.isNotEmpty) channel,
                                        ].join(' · '),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: DfCabinetTheme.ink
                                                .withOpacity(0.45)),
                                      ),
                                    ],
                                  ),
                                  if (highlights.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    ...highlights.map((line) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text('·  ',
                                                  style: TextStyle(
                                                      color: DfCabinetTheme
                                                          .brassDeep,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                              Expanded(
                                                child: Text(line,
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        height: 1.35,
                                                        color: DfCabinetTheme
                                                            .ink
                                                            .withOpacity(0.72))),
                                              ),
                                            ],
                                          ),
                                        )),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
