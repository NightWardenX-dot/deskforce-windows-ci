import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_session.dart';
import 'package:flutter_hbb/desktop/pages/cabinet_webview_page.dart';
import 'package:get/get.dart';

/// Peer entry for cabinet chat hub (devices + recent + address book).
class _ChatPeer {
  _ChatPeer({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.online = false,
    this.source = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final bool online;
  final String source;
}

/// Chat / voice hub: computers from your list → open DeskForce session chat/voice.
class CabinetChatScreen extends StatefulWidget {
  const CabinetChatScreen({Key? key}) : super(key: key);

  @override
  State<CabinetChatScreen> createState() => _CabinetChatScreenState();
}

class _CabinetChatScreenState extends State<CabinetChatScreen> {
  List<_ChatPeer> _peers = [];
  bool _loading = true;
  String _error = '';
  String _hint = '';

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
    final map = <String, _ChatPeer>{};

    void put(_ChatPeer p) {
      if (p.id.isEmpty) return;
      final prev = map[p.id];
      if (prev == null) {
        map[p.id] = p;
        return;
      }
      map[p.id] = _ChatPeer(
        id: p.id,
        title: p.title.isNotEmpty && p.title != p.id ? p.title : prev.title,
        subtitle: [
          if (p.subtitle.isNotEmpty) p.subtitle,
          if (prev.subtitle.isNotEmpty && prev.subtitle != p.subtitle)
            prev.subtitle,
        ].join(' · '),
        online: p.online || prev.online,
        source: {prev.source, p.source}.where((s) => s.isNotEmpty).join('+'),
      );
    }

    try {
      bind.mainLoadRecentPeers();
    } catch (_) {}

    try {
      for (final peer in gFFI.recentPeersModel.peers) {
        put(_ChatPeer(
          id: peer.id,
          title: peer.alias.isNotEmpty
              ? peer.alias
              : (peer.hostname.isNotEmpty ? peer.hostname : peer.id),
          subtitle: [
            peer.id,
            if (peer.platform.isNotEmpty) peer.platform,
            'недавние',
          ].join(' · '),
          online: peer.online,
          source: 'recent',
        ));
      }
    } catch (_) {}

    try {
      for (final peer in gFFI.abModel.currentAbPeers) {
        put(_ChatPeer(
          id: peer.id,
          title: peer.getId(),
          subtitle: [
            peer.id,
            if (peer.platform.isNotEmpty) peer.platform,
            'адресная книга',
          ].join(' · '),
          online: peer.online,
          source: 'ab',
        ));
      }
    } catch (_) {}

    if (CabinetApi.instance.isLoggedIn) {
      try {
        final data = await CabinetApi.instance.get('/devices', query: {
          'current': '1',
          'size': '100',
        });
        final list = <Map<String, dynamic>>[];
        if (data is Map) {
          final records = data['records'] ?? data['list'] ?? data['data'];
          if (records is List) {
            for (final r in records) {
              if (r is Map) list.add(Map<String, dynamic>.from(r));
            }
          }
        } else if (data is List) {
          for (final r in data) {
            if (r is Map) list.add(Map<String, dynamic>.from(r));
          }
        }
        for (final d in list) {
          final id = (d['device_id'] ?? '').toString();
          put(_ChatPeer(
            id: id,
            title: (d['hostname'] ?? id).toString(),
            subtitle: [
              id,
              d['os'],
              d['version'],
              'кабинет',
            ].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
            online: d['is_online'] == true,
            source: 'cabinet',
          ));
        }
      } catch (e) {
        _error = dfCabinetError(e);
      }
    }

    final sorted = map.values.toList()
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    if (!mounted) return;
    setState(() {
      _peers = sorted;
      _loading = false;
    });
  }

  Future<void> _openSession(_ChatPeer peer, {required bool voice}) async {
    await dfPlayClickSound();
    if (peer.id.isEmpty) return;
    try {
      if (voice) {
        await bind.mainSetLocalOption(
            key: 'df_pending_voice_call', value: peer.id);
      } else {
        await bind.mainSetLocalOption(key: 'df_pending_voice_call', value: '');
      }
    } catch (_) {}

    setState(() {
      _hint = voice
          ? 'Подключение к «${peer.title}»… После входа откройте «Голосовой вызов» в панели удалённого стола (меню Чат).'
          : 'Подключение к «${peer.title}»… После входа откройте чат в панели удалённого стола.';
    });

    try {
      await connect(context, peer.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось подключиться: $e';
      });
    }
  }

  Widget _upgradePrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: DfCabinetTheme.lightPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Чат и голосовые вызовы',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: DfCabinetTheme.inkOnLight,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Доступны на платных тарифах DeskForce. Оформите подписку в кабинете — удалённый доступ останется доступен.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: DfCabinetTheme.inkMutedOnLight,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: DfCabinetTheme.primaryButton(),
                onPressed: dfClickWrap(() {
                  openDeskForceCabinet(
                    url: 'https://deskforce.dr6ter.ru/cabinet/billing?embed=1',
                    title: 'Тарифы',
                  );
                }),
                child: const Text('Перейти к тарифам',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DfCabinetSession.ensure();
    final session = DfCabinetSession.to;
    return Obx(() {
      if (!session.chatCallsEnabled.value) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: DfCabinetTheme.heading('Чат', subtitle: 'Голос и переписка в сессии DeskForce.'),
            ),
            const SizedBox(height: 12),
            Expanded(child: _upgradePrompt()),
          ],
        );
      }
      return _buildChatBody(context);
    });
  }

  Widget _buildChatBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              Expanded(
                child: DfCabinetTheme.heading(
                  'Чат',
                  subtitle:
                      'Компьютеры из вашего списка. Чат и голос — через сессию DeskForce (как в удалённом столе).',
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: _loading ? null : dfClickWrap(_load),
                icon: const Icon(Icons.refresh, color: DfCabinetTheme.brass),
              ),
            ],
          ),
        ),
        if (_hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: DfCabinetTheme.panel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: DfCabinetTheme.brass, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_hint,
                        style: TextStyle(
                            fontSize: 13,
                            color: DfCabinetTheme.ink.withOpacity(0.75))),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 18,
                        color: DfCabinetTheme.ink.withOpacity(0.45)),
                    onPressed: () => setState(() => _hint = ''),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: DfCabinetTheme.brass))
              : _peers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _error.isNotEmpty
                              ? _error
                              : 'Пока нет устройств в списке. Добавьте пир на главном экране или войдите в кабинет.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _error.isNotEmpty
                                  ? DfCabinetTheme.danger
                                  : DfCabinetTheme.ink.withOpacity(0.5)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: DfCabinetTheme.brass,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                        itemCount: _peers.length + (_error.isNotEmpty ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          if (_error.isNotEmpty && i == 0) {
                            return Text(_error,
                                style: const TextStyle(
                                    color: DfCabinetTheme.danger, fontSize: 13));
                          }
                          final idx = _error.isNotEmpty ? i - 1 : i;
                          final p = _peers[idx];
                          return DfCabinetTheme.panel(
                            child: Row(
                              children: [
                                Icon(
                                  p.online
                                      ? Icons.circle
                                      : Icons.circle_outlined,
                                  size: 12,
                                  color: p.online
                                      ? DfCabinetTheme.ok
                                      : DfCabinetTheme.ink.withOpacity(0.35),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: DfCabinetTheme.ink),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        p.subtitle,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: DfCabinetTheme.ink
                                                .withOpacity(0.55)),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: dfClickWrap(
                                      () => _openSession(p, voice: false)),
                                  icon: const Icon(Icons.chat_bubble_outline,
                                      size: 16, color: DfCabinetTheme.brass),
                                  label: const Text('Чат',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: DfCabinetTheme.brass)),
                                ),
                                TextButton.icon(
                                  onPressed: dfClickWrap(
                                      () => _openSession(p, voice: true)),
                                  icon: const Icon(Icons.mic_none,
                                      size: 16, color: DfCabinetTheme.brassDeep),
                                  label: const Text('Голос',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: DfCabinetTheme.brassDeep)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

