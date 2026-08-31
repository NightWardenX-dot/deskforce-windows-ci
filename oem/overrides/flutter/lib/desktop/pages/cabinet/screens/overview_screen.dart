import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_session.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';

class CabinetOverviewScreen extends StatefulWidget {
  final void Function(String section) onNavigate;
  const CabinetOverviewScreen({Key? key, required this.onNavigate})
      : super(key: key);

  @override
  State<CabinetOverviewScreen> createState() => _CabinetOverviewScreenState();
}

class _CabinetOverviewScreenState extends State<CabinetOverviewScreen> {
  Map<String, dynamic>? _me;
  Map<String, dynamic>? _license;
  Map<String, dynamic>? _downloads;
  String _error = '';
  bool _loading = true;

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
      final me = await api.get('/me');
      Map<String, dynamic>? lic;
      Map<String, dynamic>? dl;
      try {
        final l = await api.get('/billing/license');
        if (l is Map) lic = Map<String, dynamic>.from(l);
      } catch (_) {}
      try {
        final d = await api.get('/downloads');
        if (d is Map) dl = Map<String, dynamic>.from(d);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _me = Map<String, dynamic>.from(me as Map);
        _license = lic;
        _downloads = dl;
        _loading = false;
      });
      // Keep home-page account chip in sync.
      DfCabinetSession.to.refresh();
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
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: DfCabinetTheme.brass));
    }
    if (_error.isNotEmpty && _me == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error, style: const TextStyle(color: DfCabinetTheme.danger)),
          const SizedBox(height: 12),
          ElevatedButton(
              style: DfCabinetTheme.primaryButton(),
              onPressed: dfClickWrap(_load),
              child: const Text('Повторить')),
        ]),
      );
    }
    final me = _me ?? {};
    final name = (me['name'] ?? me['username'] ?? '').toString();
    final lic = _license;
    return RefreshIndicator(
      color: DfCabinetTheme.brass,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        children: [
          DfCabinetTheme.heading('Обзор',
              subtitle: name.isEmpty
                  ? 'Кабинет оператора'
                  : 'Кабинет оператора · $name'),
          const SizedBox(height: 20),
          DfCabinetTheme.panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Учётная запись',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DfCabinetTheme.ink)),
                const SizedBox(height: 6),
                Text(
                  '${me['username'] ?? ''} · ${me['email'] ?? 'email не указан'}',
                  style: TextStyle(
                      color: DfCabinetTheme.ink.withOpacity(0.6), fontSize: 14),
                ),
                const SizedBox(height: 10),
                _badge(me['tfa_enabled'] == true ? '2FA включена' : '2FA выключена',
                    ok: me['tfa_enabled'] == true),
                if (me['need_tfa_setup'] == true) ...[
                  const SizedBox(height: 8),
                  const Text(
                      'Требуется включить 2FA в разделе «Профиль».',
                      style: TextStyle(
                          color: DfCabinetTheme.danger, fontSize: 13)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          DfCabinetTheme.panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Лицензия',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DfCabinetTheme.ink)),
                const SizedBox(height: 6),
                Text(
                  lic == null
                      ? 'Статус недоступен'
                      : (lic['active'] == true
                          ? '${lic['plan']} · удал. сессии ${lic['concurrent_used']}/${lic['concurrent_limit']}'
                          : 'не активна'),
                  style: TextStyle(
                      color: DfCabinetTheme.ink.withOpacity(0.65), fontSize: 14),
                ),
                if (lic?['active'] == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    DfCabinetSession.to.sessionsHint.isNotEmpty
                        ? DfCabinetSession.to.sessionsHint
                        : 'Сессии — одновременные удалённые подключения по тарифу.',
                    style: TextStyle(
                        fontSize: 12,
                        color: DfCabinetTheme.ink.withOpacity(0.55),
                        height: 1.35),
                  ),
                ],
                if (lic?['over_limit'] == true) ...[
                  const SizedBox(height: 6),
                  const Text('Лимит одновременных удалённых подключений исчерпан.',
                      style: TextStyle(
                          color: DfCabinetTheme.danger, fontSize: 13)),
                ],
                const SizedBox(height: 12),
                ElevatedButton(
                  style: DfCabinetTheme.primaryButton(),
                  onPressed: dfClickWrap(() => widget.onNavigate('billing')),
                  child: const Text('Тарифы и оплата',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DfCabinetTheme.panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Разделы',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DfCabinetTheme.ink)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  _navBtn('Устройства', 'devices'),
                  _navBtn('Чат', 'chat'),
                  _navBtn('Новости', 'news'),
                  _navBtn('Обновления', 'updates'),
                  _navBtn('Поддержка', 'support'),
                  _navBtn('Профиль', 'profile'),
                ]),
              ],
            ),
          ),
          DfCabinetTheme.panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Этот ПК',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DfCabinetTheme.ink)),
                const SizedBox(height: 6),
                Builder(builder: (_) {
                  final s = DfCabinetSession.to;
                  final id = s.localDeviceId.value;
                  final linked = s.localIdLinked.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        id.isEmpty
                            ? 'Идентификатор DeskForce ещё не получен'
                            : 'ID: $id',
                        style: TextStyle(
                            color: DfCabinetTheme.ink.withOpacity(0.65),
                            fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        linked
                            ? 'Привязан к вашему аккаунту кабинета'
                            : 'Не привязан — нажмите, чтобы связать с аккаунтом',
                        style: TextStyle(
                            color: linked
                                ? DfCabinetTheme.ok
                                : DfCabinetTheme.brassDeep,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      if (!linked && id.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ElevatedButton(
                          style: DfCabinetTheme.primaryButton(),
                          onPressed: dfClickWrap(() async {
                            await s.claimLocalDevice();
                            await _load();
                          }),
                          child: const Text('Привязать этот ПК',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_downloads != null) ...[

            const SizedBox(height: 14),
            DfCabinetTheme.panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Клиент DeskForce',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: DfCabinetTheme.ink)),
                  const SizedBox(height: 6),
                  Text(
                    'Сервер: ${_downloads!['id_server'] ?? '—'}',
                    style: TextStyle(
                        color: DfCabinetTheme.ink.withOpacity(0.6),
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navBtn(String label, String section) => OutlinedButton(
        style: DfCabinetTheme.ghostButton(),
        onPressed: dfClickWrap(() => widget.onNavigate(section)),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _badge(String text, {required bool ok}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ok ? const Color(0x1A2F6B3A) : const Color(0x1AB8892A),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ok ? DfCabinetTheme.ok : DfCabinetTheme.brassDeep)),
      );
}
