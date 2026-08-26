import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_session.dart';
import 'package:flutter_hbb/desktop/pages/cabinet_webview_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

/// DeskForce peer lists under the connect form: Recent / Favorites / Address book.
/// Address book uses cabinet-api (same peers as web cabinet), not stock PeerTabPage
/// (OEM restyle removed PeerTab and hard-disabled AB).
class DeskForcePeerLists extends StatefulWidget {
  const DeskForcePeerLists({
    Key? key,
    required this.ink,
    required this.onPickId,
  }) : super(key: key);

  final Color ink;
  final void Function(String id) onPickId;

  @override
  State<DeskForcePeerLists> createState() => _DeskForcePeerListsState();
}

class _DeskForcePeerListsState extends State<DeskForcePeerLists> {
  int _tab = 0; // 0 recent, 1 fav, 2 address book
  List<Map<String, dynamic>> _abPeers = [];
  bool _abLoading = false;
  String _abError = '';

  static const _brass = Color(0xFF2DD4BF);
  static const _panel = Color(0xFF0C1422);
  static const _tileBg = Color(0xFF111827);

  @override
  void initState() {
    super.initState();
    DfCabinetSession.ensure();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bind.mainLoadRecentPeers();
      bind.mainLoadFavPeers();
      _loadAb();
    });
  }

  Future<void> _loadAb() async {
    if (!CabinetApi.instance.isLoggedIn) {
      if (mounted) {
        setState(() {
          _abPeers = [];
          _abLoading = false;
          _abError = '';
        });
      }
      return;
    }
    setState(() {
      _abLoading = true;
      _abError = '';
    });
    try {
      final data = await CabinetApi.instance.get('/address-book');
      final list = <Map<String, dynamic>>[];
      if (data is Map) {
        final peers = data['peers'];
        if (peers is List) {
          for (final p in peers) {
            if (p is Map) list.add(Map<String, dynamic>.from(p));
          }
        }
      }
      if (mounted) {
        setState(() {
          _abPeers = list;
          _abLoading = false;
        });
      }
      // Keep stock abModel in sync for chat hub etc.
      try {
        await gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: true);
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _abLoading = false;
          _abError = e is CabinetApiException ? e.ru : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x338BA0B8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _tabChip(0, 'НЕДАВНИЕ', labelColor),
              const SizedBox(width: 6),
              _tabChip(1, 'ИЗБРАННЫЕ', labelColor),
              const SizedBox(width: 6),
              _tabChip(2, 'АДРЕСНАЯ КНИГА', labelColor),
              const Spacer(),
              if (_tab == 2)
                IconButton(
                  tooltip: 'Обновить',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _abLoading ? null : _loadAb,
                  icon: Icon(Icons.refresh, size: 16, color: labelColor),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_tab == 0) _buildRecent(),
          if (_tab == 1) _buildFav(),
          if (_tab == 2) _buildAddressBook(labelColor),
        ],
      ),
    );
  }

  Widget _tabChip(int index, String label, Color accent) {
    final selected = _tab == index;
    return InkWell(
      onTap: () {
        setState(() => _tab = index);
        if (index == 2) _loadAb();
        if (index == 0) bind.mainLoadRecentPeers();
        if (index == 1) bind.mainLoadFavPeers();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent.withOpacity(0.55) : const Color(0x2212161C),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: selected ? accent : widget.ink.withOpacity(0.45),
          ),
        ),
      ),
    );
  }

  Widget _buildRecent() {
    return ListenableBuilder(
      listenable: gFFI.recentPeersModel,
      builder: (context, _) {
        final peers = gFFI.recentPeersModel.peers.take(8).toList();
        if (peers.isEmpty) {
          return _hint(
            'Здесь появятся устройства, к которым вы уже подключались.',
          );
        }
        return Column(
          children: peers.map((p) => _peerTileFromModel(p)).toList(),
        );
      },
    );
  }

  Widget _buildFav() {
    return ListenableBuilder(
      listenable: gFFI.favoritePeersModel,
      builder: (context, _) {
        final peers = gFFI.favoritePeersModel.peers.take(12).toList();
        if (peers.isEmpty) {
          return _hint(
            'Добавляйте устройства в избранное из меню карточки сессии.',
          );
        }
        return Column(
          children: peers.map((p) => _peerTileFromModel(p)).toList(),
        );
      },
    );
  }

  Widget _buildAddressBook(Color accent) {
    return Obx(() {
      final logged = DfCabinetSession.to.loggedIn.value ||
          CabinetApi.instance.isLoggedIn;
      if (!logged) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Адресная книга доступна после входа в личный кабинет DeskForce.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: widget.ink.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openDeskForceCabinet(
                    url: 'https://deskforce.dr6ter.ru/cabinet/?embed=1',
                    title: 'Личный кабинет',
                  ),
                  icon: Icon(Icons.login, size: 18, color: accent),
                  label: Text(
                    'Войти в кабинет',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              ),
              Text(
                'Кабинет → Адресная книга · deskforce.dr6ter.ru',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.ink.withOpacity(0.45),
                ),
              ),
            ],
          ),
        );
      }
      if (_abLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (_abError.isNotEmpty) {
        return _hint(_abError);
      }
      if (_abPeers.isEmpty) {
        return _hint(
          'Адресная книга пуста. Добавьте устройства в кабинете '
          '(раздел «Адресная книга») или сохраните peer после подключения.',
        );
      }
      return Column(
        children: _abPeers.map<Widget>((m) {
          final id = (m['id'] ?? '').toString();
          final alias = (m['alias'] ?? '').toString();
          final hostname = (m['hostname'] ?? '').toString();
          final username = (m['username'] ?? '').toString();
          final title = alias.isNotEmpty
              ? alias
              : (hostname.isNotEmpty
                  ? hostname
                  : (id.isNotEmpty ? formatID(id) : '—'));
          final subtitle = [
            if (username.isNotEmpty) username,
            if (hostname.isNotEmpty && hostname != title) hostname,
            if (id.isNotEmpty) id,
          ].join(' · ');
          return _tile(
            title: title,
            subtitle: subtitle,
            online: null,
            onTap: id.isEmpty ? null : () => widget.onPickId(id),
          );
        }).toList(),
      );
    });
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: widget.ink.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _peerTileFromModel(Peer peer) {
    final title = peer.alias.isNotEmpty
        ? peer.alias
        : (peer.id.isNotEmpty ? formatID(peer.id) : '—');
    final subtitle = [
      if (peer.username.isNotEmpty) peer.username,
      if (peer.hostname.isNotEmpty) peer.hostname,
    ].join('@');
    return _tile(
      title: title,
      subtitle: subtitle,
      online: peer.online,
      onTap: peer.id.isEmpty ? null : () => widget.onPickId(peer.id),
    );
  }

  Widget _tile({
    required String title,
    required String subtitle,
    required bool? online,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: _tileBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: online == null
                        ? const Color(0xFF2DD4BF)
                        : (online
                            ? const Color(0xFF34D399)
                            : const Color(0xFF8BA0B8)),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x552DD4BF)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8F4FF),
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.ink.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFF2DD4BF)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
