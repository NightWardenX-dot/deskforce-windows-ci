import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';
import 'package:url_launcher/url_launcher.dart';

class CabinetBillingScreen extends StatefulWidget {
  const CabinetBillingScreen({Key? key}) : super(key: key);

  @override
  State<CabinetBillingScreen> createState() => _CabinetBillingScreenState();
}

class _CabinetBillingScreenState extends State<CabinetBillingScreen> {
  Map<String, dynamic>? _license;
  Map<String, dynamic>? _plansMeta;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  bool _busy = false;
  String _error = '';
  String _msg = '';
  final Map<String, int> _seats = {};

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
      final api = CabinetApi.instance;
      final lic = await api.get('/billing/license');
      final plans = await api.get('/billing/plans');
      List<Map<String, dynamic>> orders = [];
      try {
        final o = await api.get('/billing/orders');
        if (o is Map && o['records'] is List) {
          for (final r in o['records']) {
            if (r is Map) orders.add(Map<String, dynamic>.from(r));
          }
        }
      } catch (_) {}
      if (!mounted) return;
      final meta = Map<String, dynamic>.from(plans as Map);
      final planList = meta['plans'];
      if (planList is List) {
        for (final p in planList) {
          if (p is Map) {
            final id = (p['id'] ?? '').toString();
            final min = (p['min_seats'] is num)
                ? (p['min_seats'] as num).toInt()
                : 1;
            _seats.putIfAbsent(id, () => min);
          }
        }
      }
      setState(() {
        _license = Map<String, dynamic>.from(lic as Map);
        _plansMeta = meta;
        _orders = orders;
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

  Future<void> _buy(Map<String, dynamic> plan) async {
    await dfPlayClickSound();
    setState(() {
      _busy = true;
      _error = '';
      _msg = '';
    });
    try {
      final api = CabinetApi.instance;
      final id = (plan['id'] ?? '').toString();
      final seats = _seats[id] ?? 1;
      final order = await api.post('/billing/orders', body: {
        'plan': id,
        'seats': plan['price_per_seat'] == true ? seats : 0,
      });
      var map = Map<String, dynamic>.from(order as Map);
      if (map['status']?.toString() == 'paid') {
        setState(() => _msg = plan['trial'] == true
            ? 'Пробный период активирован'
            : 'Лицензия активирована');
        await _load();
        return;
      }
      final provider = (_plansMeta?['provider'] ?? '').toString();
      if (provider != 'manual' && map['id'] != null) {
        try {
          final paid = await api.post('/billing/orders/pay', body: {
            'id': map['id'],
            'method': 'card',
          });
          if (paid is Map) map = Map<String, dynamic>.from(paid);
        } catch (_) {}
      }
      final payUrl = (map['payment_url'] ?? '').toString();
      if (payUrl.isNotEmpty) {
        await launchUrl(Uri.parse(payUrl),
            mode: LaunchMode.externalApplication);
        setState(() =>
            _msg = 'Заказ #${map['id']} создан. Открыта страница оплаты.');
      } else {
        setState(() => _msg =
            'Заказ #${map['id']} создан (${map['amount_rub'] ?? ''} ₽). '
            'Оплатите по инструкции ниже или напишите в поддержку.');
      }
      await _load();
    } catch (e) {
      setState(() => _error = dfCabinetError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(dynamic v) {
    if (v is num) return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: DfCabinetTheme.brass));
    }
    final lic = _license;
    final plans = (_plansMeta?['plans'] is List)
        ? List.from(_plansMeta!['plans'] as List)
        : <dynamic>[];
    final promo = _plansMeta?['promo_active'] == true;
    final manual = _plansMeta?['manual'];

    return RefreshIndicator(
      color: DfCabinetTheme.brass,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        children: [
          DfCabinetTheme.heading('Тарифы и оплата',
              subtitle: 'Лицензия по числу одновременных сессий.'),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error,
                style: const TextStyle(color: DfCabinetTheme.danger)),
          ],
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_msg, style: const TextStyle(color: DfCabinetTheme.ok)),
          ],
          const SizedBox(height: 18),
          DfCabinetTheme.panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Текущая лицензия',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DfCabinetTheme.ink)),
                const SizedBox(height: 6),
                Text(
                  lic == null
                      ? '—'
                      : (lic['active'] == true
                          ? '${lic['plan']} · лимит ${lic['concurrent_limit']} · занято ${lic['concurrent_used']}'
                              '${lic['expires_at'] != null && '${lic['expires_at']}'.isNotEmpty && !'${lic['expires_at']}'.startsWith('0001') ? ' · до ${lic['expires_at']}' : ''}'
                          : 'не активна'),
                  style: TextStyle(
                      color: DfCabinetTheme.ink.withOpacity(0.65),
                      fontSize: 14),
                ),
              ],
            ),
          ),
          if (promo) ...[
            const SizedBox(height: 12),
            DfCabinetTheme.panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((_plansMeta?['promo_title'] ?? 'Акция').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: DfCabinetTheme.ink)),
                  const SizedBox(height: 4),
                  Text(
                      'До ${_plansMeta?['promo_ends'] ?? '—'}',
                      style: TextStyle(
                          color: DfCabinetTheme.ink.withOpacity(0.55))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          DfCabinetTheme.sectionTitle(promo ? 'Доступные тарифы' : 'Тарифы'),
          const SizedBox(height: 10),
          ...plans.whereType<Map>().map((raw) {
            final p = Map<String, dynamic>.from(raw);
            final id = (p['id'] ?? '').toString();
            final perSeat = p['price_per_seat'] == true;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DfCabinetTheme.panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text((p['name'] ?? id).toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: DfCabinetTheme.ink)),
                        ),
                        if (p['promo'] == true)
                          const Text('акция',
                              style: TextStyle(
                                  color: DfCabinetTheme.brass,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p['trial'] == true
                          ? '0 ₽'
                          : '${_money(p['price_rub'])} ₽'
                              '${perSeat ? ' / сессия' : ''}'
                              '${p['period_label'] != null ? ' / ${p['period_label']}' : ''}',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: DfCabinetTheme.brassDeep),
                    ),
                    if ((p['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(p['description'].toString(),
                          style: TextStyle(
                              color: DfCabinetTheme.ink.withOpacity(0.55),
                              fontSize: 13)),
                    ],
                    if (perSeat) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 140,
                        child: TextFormField(
                          initialValue: '${_seats[id] ?? 1}',
                          keyboardType: TextInputType.number,
                          decoration:
                              DfCabinetTheme.field('Сессий одновременно'),
                          onChanged: (v) {
                            final n = int.tryParse(v) ?? 1;
                            _seats[id] = n < 1 ? 1 : n;
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: DfCabinetTheme.primaryButton(),
                      onPressed: _busy ? null : () => _buy(p),
                      child: Text(
                          p['trial'] == true
                              ? 'Активировать пробный период'
                              : 'Выбрать тариф',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (manual is Map) ...[
            const SizedBox(height: 8),
            DfCabinetTheme.panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((manual['title'] ?? 'Оплата').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: DfCabinetTheme.ink)),
                  const SizedBox(height: 6),
                  Text((manual['details'] ?? '').toString(),
                      style: TextStyle(
                          color: DfCabinetTheme.ink.withOpacity(0.7),
                          height: 1.4)),
                ],
              ),
            ),
          ],
          if (_orders.isNotEmpty) ...[
            const SizedBox(height: 18),
            DfCabinetTheme.sectionTitle('Последние заказы'),
            const SizedBox(height: 10),
            ..._orders.take(8).map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DfCabinetTheme.panel(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#${o['id']} · ${o['plan']} · ${_money(o['amount_rub'])} ₽',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: DfCabinetTheme.ink),
                          ),
                        ),
                        Text('${o['status']}',
                            style: TextStyle(
                                fontSize: 12,
                                color: DfCabinetTheme.ink.withOpacity(0.55))),
                        if ((o['payment_url'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              await dfPlayClickSound();
                              await launchUrl(
                                  Uri.parse(o['payment_url'].toString()),
                                  mode: LaunchMode.externalApplication);
                            },
                            child: const Text('Оплатить'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
