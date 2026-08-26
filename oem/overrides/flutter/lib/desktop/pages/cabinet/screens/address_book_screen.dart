import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';

/// Native cabinet «Адресная книга» — same data as web /cabinet/address-book.
class CabinetAddressBookScreen extends StatefulWidget {
  const CabinetAddressBookScreen({Key? key}) : super(key: key);

  @override
  State<CabinetAddressBookScreen> createState() =>
      _CabinetAddressBookScreenState();
}

class _CabinetAddressBookScreenState extends State<CabinetAddressBookScreen> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _peers = [];
  final _idCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
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
          _peers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is CabinetApiException ? e.ru : e.toString();
        });
      }
    }
  }

  Future<void> _add() async {
    await dfPlayClickSound();
    final id = _idCtrl.text.trim();
    if (id.isEmpty) return;
    try {
      await CabinetApi.instance.post('/address-book/peer', body: {
        'id': id,
        'alias': _aliasCtrl.text.trim(),
        'username': '',
        'hostname': '',
        'platform': '',
        'tags': <String>[],
      });
      _idCtrl.clear();
      _aliasCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is CabinetApiException ? e.ru : e.toString();
        });
      }
    }
  }

  Future<void> _delete(String id) async {
    await dfPlayClickSound();
    try {
      await CabinetApi.instance
          .post('/address-book/peer/delete', body: {'id': id});
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is CabinetApiException ? e.ru : e.toString();
        });
      }
    }
  }

  Future<void> _connect(String id) async {
    await dfPlayClickSound();
    if (id.isEmpty) return;
    try {
      connect(context, id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Адресная книга',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: DfCabinetTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Сохранённые устройства аккаунта DeskForce. Те же записи, что в веб-кабинете.',
            style: TextStyle(fontSize: 13, color: Color(0x99E8F4FF)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _idCtrl,
                  style: DfCabinetTheme.inputStyle,
                  decoration: DfCabinetTheme.field('ID устройства'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _aliasCtrl,
                  style: DfCabinetTheme.inputStyle,
                  decoration: DfCabinetTheme.field('Имя (необязательно)'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _add,
                style: FilledButton.styleFrom(
                  backgroundColor: DfCabinetTheme.brass,
                  foregroundColor: const Color(0xFF041016),
                ),
                child: const Text('Добавить'),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: DfCabinetTheme.brass),
              ),
            ],
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_error, style: const TextStyle(color: DfCabinetTheme.danger)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: DfCabinetTheme.brass),
                  )
                : _peers.isEmpty
                    ? const Center(
                        child: Text(
                          'Пока пусто — добавьте ID выше или сохраните peer после сессии.',
                          style: TextStyle(color: Color(0x99E8F4FF)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _peers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final m = _peers[i];
                          final id = (m['id'] ?? '').toString();
                          final alias = (m['alias'] ?? '').toString();
                          final host = (m['hostname'] ?? '').toString();
                          final title = alias.isNotEmpty
                              ? alias
                              : (host.isNotEmpty
                                  ? host
                                  : (id.isNotEmpty ? formatID(id) : '—'));
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: DfCabinetTheme.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: DfCabinetTheme.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: DfCabinetTheme.ink,
                                        ),
                                      ),
                                      if (id.isNotEmpty)
                                        Text(
                                          id,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0x99E8F4FF),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _connect(id),
                                  child: const Text('Подключить'),
                                ),
                                IconButton(
                                  tooltip: 'Удалить',
                                  onPressed: () => _delete(id),
                                  icon: const Icon(Icons.delete_outline,
                                      color: DfCabinetTheme.danger),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
