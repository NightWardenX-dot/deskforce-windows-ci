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
                    subtitle: 'Привязанные клиенты и онлайн-статус.'),
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
              : _error.isNotEmpty
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
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final d = _items[i];
                              final online = d['is_online'] == true;
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
