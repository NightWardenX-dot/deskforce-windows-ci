import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';

class CabinetDevicesScreen extends StatefulWidget {
  const CabinetDevicesScreen({Key? key}) : super(key: key);

  @override
  State<CabinetDevicesScreen> createState() => _CabinetDevicesScreenState();
}

class _CabinetDevicesScreenState extends State<CabinetDevicesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _error = '';
  String _busyId = '';

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
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dfCabinetError(e);
        _loading = false;
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final deviceId = (d['device_id'] ?? '').toString();
    if (deviceId.isEmpty) return;
    final online = d['is_online'] == true;
    final fromPeer = d['from_peer'] == true;
    if (online && !fromPeer) {
      setState(() {
        _error = dfCabinetError('DeviceOnline');
      });
      return;
    }
    final label = (d['hostname'] ?? deviceId).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить устройство?'),
        content: Text('Убрать «$label» из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busyId = deviceId;
      _error = '';
    });
    try {
      await CabinetApi.instance.post('/devices/delete', body: {
        'device_id': deviceId,
        'id': d['id'] is num ? (d['id'] as num).toInt() : 0,
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dfCabinetError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busyId = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              Expanded(
                child: DfCabinetTheme.heading('Устройства',
                    subtitle:
                        'Привязанные клиенты. Офлайн-устройства можно удалить.'),
              ),
              IconButton(
                tooltip: 'Обновить',
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
              : _error.isNotEmpty && _items.isEmpty
                  ? Center(
                      child: Text(_error,
                          style:
                              const TextStyle(color: DfCabinetTheme.danger)))
                  : _items.isEmpty
                      ? Center(
                          child: Text('Устройств пока нет',
                              style: TextStyle(
                                  color:
                                      DfCabinetTheme.ink.withOpacity(0.5))))
                      : RefreshIndicator(
                          color: DfCabinetTheme.brass,
                          onRefresh: _load,
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(28, 0, 28, 32),
                            itemCount: _items.length + (_error.isNotEmpty ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              if (_error.isNotEmpty && i == 0) {
                                return Text(_error,
                                    style: const TextStyle(
                                        color: DfCabinetTheme.danger,
                                        fontSize: 13));
                              }
                              final idx = _error.isNotEmpty ? i - 1 : i;
                              final d = _items[idx];
                              final online = d['is_online'] == true;
                              final fromPeer = d['from_peer'] == true;
                              final deviceId =
                                  (d['device_id'] ?? '').toString();
                              final canDelete = !(online && !fromPeer);
                              final busy = _busyId == deviceId;
                              return DfCabinetTheme.panel(
                                child: Row(
                                  children: [
                                    Icon(
                                      online
                                          ? Icons.circle
                                          : Icons.circle_outlined,
                                      size: 12,
                                      color: online
                                          ? DfCabinetTheme.ok
                                          : DfCabinetTheme.ink
                                              .withOpacity(0.35),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (d['hostname'] ??
                                                    d['device_id'] ??
                                                    '—')
                                                .toString(),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: DfCabinetTheme.ink),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              d['device_id'],
                                              d['os'],
                                              d['version'],
                                              if (d['note'] != null &&
                                                  '${d['note']}'.isNotEmpty)
                                                d['note'],
                                            ]
                                                .where((e) =>
                                                    e != null &&
                                                    '$e'.isNotEmpty)
                                                .join(' · '),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: DfCabinetTheme.ink
                                                    .withOpacity(0.55)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      online ? 'онлайн' : 'офлайн',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: online
                                              ? DfCabinetTheme.ok
                                              : DfCabinetTheme.ink
                                                  .withOpacity(0.45)),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: canDelete
                                          ? 'Удалить'
                                          : 'Сначала отключите устройство',
                                      onPressed: (!canDelete || busy)
                                          ? null
                                          : dfClickWrap(() => _delete(d)),
                                      icon: busy
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: DfCabinetTheme
                                                          .brass),
                                            )
                                          : Icon(Icons.delete_outline,
                                              color: canDelete
                                                  ? DfCabinetTheme.danger
                                                  : DfCabinetTheme.ink
                                                      .withOpacity(0.25)),
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
