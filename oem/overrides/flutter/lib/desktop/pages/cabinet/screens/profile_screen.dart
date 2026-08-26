import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_session.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';

class CabinetProfileScreen extends StatefulWidget {
  final VoidCallback onLoggedOut;
  const CabinetProfileScreen({Key? key, required this.onLoggedOut})
      : super(key: key);

  @override
  State<CabinetProfileScreen> createState() => _CabinetProfileScreenState();
}

class _CabinetProfileScreenState extends State<CabinetProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _oldPwd = TextEditingController();
  final _newPwd = TextEditingController();
  final _tfaCode = TextEditingController();
  final _disablePwd = TextEditingController();
  final _disableCode = TextEditingController();

  Map<String, dynamic>? _me;
  Map<String, dynamic>? _tfa;
  Map<String, dynamic>? _setup;
  bool _loading = true;
  String _error = '';
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _oldPwd.dispose();
    _newPwd.dispose();
    _tfaCode.dispose();
    _disablePwd.dispose();
    _disableCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final api = CabinetApi.instance;
      final me = Map<String, dynamic>.from(await api.get('/me') as Map);
      Map<String, dynamic>? tfa;
      try {
        final t = await api.get('/2fa');
        if (t is Map) tfa = Map<String, dynamic>.from(t);
      } catch (_) {
        tfa = {
          'enabled': me['tfa_enabled'] == true,
        };
      }
      if (!mounted) return;
      _name.text = (me['name'] ?? '').toString();
      _email.text = (me['email'] ?? '').toString();
      setState(() {
        _me = me;
        _tfa = tfa;
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

  Future<void> _saveProfile() async {
    await dfPlayClickSound();
    setState(() {
      _error = '';
      _msg = '';
    });
    try {
      await CabinetApi.instance.post('/me', body: {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
      });
      setState(() => _msg = 'Профиль сохранён');
      await _load();
    } catch (e) {
      setState(() => _error = dfCabinetError(e));
    }
  }

  Future<void> _changePassword() async {
    await dfPlayClickSound();
    setState(() {
      _error = '';
      _msg = '';
    });
    try {
      await CabinetApi.instance.post('/password', body: {
        'oldPassword': _oldPwd.text,
        'newPassword': _newPwd.text,
      });
      _oldPwd.clear();
      _newPwd.clear();
      setState(() => _msg = 'Пароль изменён');
    } catch (e) {
      setState(() => _error = dfCabinetError(e));
    }
  }

  Future<void> _setup2fa() async {
    await dfPlayClickSound();
    try {
      final data = await CabinetApi.instance.post('/2fa/setup', body: {});
      setState(() {
        _setup = Map<String, dynamic>.from(data as Map);
        _msg = 'Добавьте секрет в приложение-аутентификатор';
        _error = '';
      });
    } catch (e) {
      setState(() => _error = dfCabinetError(e));
    }
  }

  Future<void> _enable2fa() async {
    await dfPlayClickSound();
    try {
      final secret = (_setup?['key'] ?? _setup?['secret'] ?? '').toString();
      await CabinetApi.instance.post('/2fa/enable', body: {
        'secret': secret,
        'code': _tfaCode.text.trim(),
      });
      _tfaCode.clear();
      _setup = null;
      setState(() => _msg = '2FA включена');
      await _load();
    } catch (e) {
      setState(() => _error = dfCabinetError(e));
    }
  }

  Future<void> _disable2fa() async {
    await dfPlayClickSound();
    try {
      await CabinetApi.instance.post('/2fa/disable', body: {
        'password': _disablePwd.text,
        'code': _disableCode.text.trim(),
      });
      _disablePwd.clear();
      _disableCode.clear();
      setState(() => _msg = '2FA выключена');
      await _load();
    } catch (e) {
      setState(() => _error = dfCabinetError(e));
    }
  }

  Future<void> _logout() async {
    await dfPlayClickSound();
    await DfCabinetSession.to.logout();
    widget.onLoggedOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: DfCabinetTheme.brass));
    }
    final me = _me ?? {};
    final enabled = _tfa?['enabled'] == true || me['tfa_enabled'] == true;
    final force = me['force_2fa'] == true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      children: [
        DfCabinetTheme.heading('Профиль',
            subtitle: 'Данные аккаунта, пароль и 2FA.'),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_error, style: const TextStyle(color: DfCabinetTheme.danger)),
        ],
        if (_msg.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_msg, style: const TextStyle(color: DfCabinetTheme.ok)),
        ],
        const SizedBox(height: 16),
        DfCabinetTheme.panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Данные',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: DfCabinetTheme.ink)),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: DfCabinetTheme.field('Логин'),
                child: Text((me['username'] ?? '').toString(),
                    style: const TextStyle(color: DfCabinetTheme.ink)),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: _name, decoration: DfCabinetTheme.field('Имя')),
              const SizedBox(height: 10),
              TextField(
                  controller: _email,
                  decoration: DfCabinetTheme.field('Email'),
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              ElevatedButton(
                style: DfCabinetTheme.primaryButton(),
                onPressed: _saveProfile,
                child: const Text('Сохранить',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DfCabinetTheme.panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Смена пароля',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: DfCabinetTheme.ink)),
              const SizedBox(height: 10),
              TextField(
                  controller: _oldPwd,
                  obscureText: true,
                  decoration: DfCabinetTheme.field('Текущий пароль')),
              const SizedBox(height: 10),
              TextField(
                  controller: _newPwd,
                  obscureText: true,
                  decoration: DfCabinetTheme.field('Новый пароль')),
              const SizedBox(height: 12),
              ElevatedButton(
                style: DfCabinetTheme.primaryButton(),
                onPressed: _changePassword,
                child: const Text('Сменить пароль',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DfCabinetTheme.panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'Двухфакторная аутентификация — ${enabled ? 'включена' : 'выключена'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: DfCabinetTheme.ink)),
              const SizedBox(height: 10),
              if (!enabled) ...[
                OutlinedButton(
                  style: DfCabinetTheme.ghostButton(),
                  onPressed: _setup2fa,
                  child: const Text('Получить QR / секрет',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (_setup != null) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    (_setup!['key'] ?? _setup!['secret'] ?? '').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: DfCabinetTheme.ink),
                  ),
                  if ((_setup!['url'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(_setup!['url'].toString(),
                        style: TextStyle(
                            fontSize: 11,
                            color: DfCabinetTheme.ink.withOpacity(0.55))),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                      controller: _tfaCode,
                      decoration: DfCabinetTheme.field('Код из приложения'),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: DfCabinetTheme.primaryButton(),
                    onPressed: _enable2fa,
                    child: const Text('Включить 2FA',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ] else ...[
                TextField(
                    controller: _disablePwd,
                    obscureText: true,
                    decoration: DfCabinetTheme.field('Пароль')),
                const SizedBox(height: 10),
                TextField(
                    controller: _disableCode,
                    decoration: DfCabinetTheme.field('Код 2FA'),
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: DfCabinetTheme.primaryButton(),
                  onPressed: force ? null : _disable2fa,
                  child: const Text('Выключить 2FA',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (force)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Администратор запретил отключение 2FA.',
                        style: TextStyle(color: DfCabinetTheme.danger)),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          style: DfCabinetTheme.ghostButton(),
          onPressed: _logout,
          child: const Text('Выйти из кабинета',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
