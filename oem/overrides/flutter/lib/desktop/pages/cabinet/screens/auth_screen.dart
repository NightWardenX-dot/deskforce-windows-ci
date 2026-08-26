import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';
import 'package:url_launcher/url_launcher.dart';

enum _AuthMode { login, register, verify, forgot }

class CabinetAuthScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const CabinetAuthScreen({Key? key, required this.onLoggedIn}) : super(key: key);

  @override
  State<CabinetAuthScreen> createState() => _CabinetAuthScreenState();
}

class _CabinetAuthScreenState extends State<CabinetAuthScreen> {
  _AuthMode _mode = _AuthMode.login;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _tfa = TextEditingController();
  final _verify = TextEditingController();
  bool _remember = true;
  bool _needTfa = false;
  bool _busy = false;
  String _error = '';
  String _ok = '';
  late int _formOpenedAt;
  String _challengeId = '';

  @override
  void initState() {
    super.initState();
    _formOpenedAt = DateTime.now().millisecondsSinceEpoch;
    _loadChallenge();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _name.dispose();
    _email.dispose();
    _tfa.dispose();
    _verify.dispose();
    super.dispose();
  }

  Future<void> _loadChallenge() async {
    final ch = await CabinetApi.instance.fetchChallenge();
    if (!mounted || ch == null) return;
    setState(() => _challengeId = (ch['id'] ?? '').toString());
  }

  void _setMode(_AuthMode m) {
    setState(() {
      _mode = m;
      _error = '';
      _ok = '';
      _needTfa = false;
      _formOpenedAt = DateTime.now().millisecondsSinceEpoch;
    });
    _loadChallenge();
  }

  Future<void> _submit() async {
    await dfPlayClickSound();
    setState(() {
      _busy = true;
      _error = '';
      _ok = '';
    });
    // Ensure form was open ≥ ~2s (server minFillMs).
    final opened = _formOpenedAt;
    final elapsed = DateTime.now().millisecondsSinceEpoch - opened;
    if (elapsed < 2000) {
      await Future.delayed(Duration(milliseconds: 2000 - elapsed));
    }
    try {
      final api = CabinetApi.instance;
      switch (_mode) {
        case _AuthMode.login:
          final res = await api.login(
            username: _user.text.trim(),
            password: _pass.text,
            formOpenedAt: opened,
            tfaCode: _tfa.text.trim(),
            rememberMe: _remember,
            captchaId: _challengeId,
          );
          if (res['need_tfa'] == true) {
            setState(() {
              _needTfa = true;
              _ok = dfCabinetError('TfaRequired');
            });
            return;
          }
          if (res['is_admin'] == true) {
            final url = (res['admin_redirect'] ?? '/index.html').toString();
            final abs = url.startsWith('http')
                ? url
                : 'https://deskforce.dr6ter.ru$url';
            await launchUrl(Uri.parse(abs), mode: LaunchMode.externalApplication);
            await api.clearToken();
            setState(() => _ok = 'Открыта консоль администратора в браузере.');
            return;
          }
          widget.onLoggedIn();
          break;
        case _AuthMode.register:
          final res = await api.register(
            username: _user.text.trim(),
            password: _pass.text,
            email: _email.text.trim(),
            name: _name.text.trim(),
            formOpenedAt: opened,
            captchaId: _challengeId,
          );
          setState(() {
            _mode = _AuthMode.verify;
            _ok =
                'Код отправлен на ${(res['email'] ?? _email.text).toString()}. Введите его ниже.';
            _formOpenedAt = DateTime.now().millisecondsSinceEpoch;
          });
          break;
        case _AuthMode.verify:
          await api.post('/auth/verify-email', auth: false, body: {
            'code': _verify.text.trim(),
          });
          setState(() {
            _mode = _AuthMode.login;
            _ok = 'Email подтверждён. Войдите в кабинет.';
          });
          break;
        case _AuthMode.forgot:
          final u = _user.text.trim();
          final body = <String, dynamic>{
            ...CabinetApi.botFields(
                formOpenedAt: opened, captchaId: _challengeId),
          };
          if (u.contains('@')) {
            body['email'] = u;
          } else {
            body['username'] = u;
          }
          await api.post('/auth/forgot-password', auth: false, body: body);
          setState(() =>
              _ok = 'Если аккаунт найден, письмо для сброса пароля отправлено.');
          break;
      }
    } catch (e) {
      final msg = dfCabinetError(e);
      final data = e is CabinetApiException ? e.data : null;
      if (e is CabinetApiException && e.message == 'EmailNotVerified') {
        setState(() {
          _mode = _AuthMode.verify;
          _error = msg;
          if (data is Map && data['email'] != null) {
            _ok = 'Код нужен для ${data['email']}';
          }
        });
      } else {
        setState(() => _error = msg);
      }
      _loadChallenge();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _title {
    switch (_mode) {
      case _AuthMode.login:
        return 'Вход в кабинет';
      case _AuthMode.register:
        return 'Регистрация';
      case _AuthMode.verify:
        return 'Подтверждение email';
      case _AuthMode.forgot:
        return 'Сброс пароля';
    }
  }

  String get _subtitle {
    switch (_mode) {
      case _AuthMode.login:
        return 'Логин DeskForce УД для устройств и лицензии.';
      case _AuthMode.register:
        return 'Создайте учётную запись оператора.';
      case _AuthMode.verify:
        return 'Введите код из письма.';
      case _AuthMode.forgot:
        return 'Укажите логин или email — пришлём ссылку.';
    }
  }

  String get _btn {
    switch (_mode) {
      case _AuthMode.login:
        return 'Войти';
      case _AuthMode.register:
        return 'Зарегистрироваться';
      case _AuthMode.verify:
        return 'Подтвердить';
      case _AuthMode.forgot:
        return 'Отправить';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DfCabinetTheme.panel(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('DeskForce УД',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: DfCabinetTheme.brass)),
                const SizedBox(height: 10),
                Text(_title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: DfCabinetTheme.ink)),
                const SizedBox(height: 4),
                Text(_subtitle,
                    style: TextStyle(
                        fontSize: 13,
                        color: DfCabinetTheme.ink.withOpacity(0.55))),
                const SizedBox(height: 18),
                if (_mode == _AuthMode.login ||
                    _mode == _AuthMode.register ||
                    _mode == _AuthMode.forgot)
                  TextField(
                    controller: _user,
                    decoration: DfCabinetTheme.field(
                        _mode == _AuthMode.forgot ? 'Логин или email' : 'Логин'),
                    textInputAction: TextInputAction.next,
                  ),
                if (_mode == _AuthMode.register) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    decoration: DfCabinetTheme.field('Имя'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _email,
                    decoration: DfCabinetTheme.field('Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
                if (_mode == _AuthMode.login || _mode == _AuthMode.register) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: DfCabinetTheme.field('Пароль'),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                ],
                if (_mode == _AuthMode.verify) ...[
                  TextField(
                    controller: _verify,
                    decoration: DfCabinetTheme.field('Код из письма'),
                  ),
                ],
                if (_needTfa && _mode == _AuthMode.login) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tfa,
                    decoration: DfCabinetTheme.field('Код 2FA'),
                    keyboardType: TextInputType.number,
                  ),
                ],
                if (_mode == _AuthMode.login) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: DfCabinetTheme.brass,
                    title: const Text('Запомнить меня',
                        style: TextStyle(fontSize: 14)),
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? true),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                // Hidden honeypot (bots only)
                Opacity(
                  opacity: 0,
                  child: SizedBox(
                    height: 0,
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'company'),
                      enabled: false,
                    ),
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_error,
                      style: const TextStyle(
                          color: DfCabinetTheme.danger, fontSize: 13)),
                ],
                if (_ok.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_ok,
                      style: const TextStyle(
                          color: DfCabinetTheme.ok, fontSize: 13)),
                ],
                const SizedBox(height: 14),
                ElevatedButton(
                  style: DfCabinetTheme.primaryButton(),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? '…' : _btn,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (_mode != _AuthMode.login)
                      TextButton(
                          onPressed: () => _setMode(_AuthMode.login),
                          child: const Text('Вход')),
                    if (_mode == _AuthMode.login)
                      TextButton(
                          onPressed: () => _setMode(_AuthMode.register),
                          child: const Text('Регистрация')),
                    if (_mode == _AuthMode.login)
                      TextButton(
                          onPressed: () => _setMode(_AuthMode.forgot),
                          child: const Text('Забыли пароль?')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
