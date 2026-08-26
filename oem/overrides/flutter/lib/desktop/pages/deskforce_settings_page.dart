import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/deskforce_startup.dart';
import 'package:flutter_hbb/common/deskforce_update.dart';
import 'package:flutter_hbb/desktop/pages/cabinet_webview_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// DeskForce paper/brass settings — single scroll of cards, no RustDesk left-nav chrome.
class DeskForceSettingsPage extends StatefulWidget {
  const DeskForceSettingsPage({Key? key}) : super(key: key);

  @override
  State<DeskForceSettingsPage> createState() => _DeskForceSettingsPageState();
}

class _DeskForceSettingsPageState extends State<DeskForceSettingsPage> {
  static const _ink = Color(0xFF12161C);
  static const _paper = Color(0xFFF3EFE6);
  static const _card = Color(0xFFFBF8F1);
  static const _brass = Color(0xFFB8892A);

  bool _autostart = false;
  bool _startTray = false;
  bool _startFs = true; // default ON
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auto = await dfIsWindowsAutostartEnabled();
    setState(() {
      _autostart = auto || dfLocalBool(kDfAutostart);
      _startTray = dfLocalBool(kDfStartInTray);
      _startFs = dfLocalBoolDefaultOn(kDfStartFullscreen);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          const Text(
            'Настройки DeskForce',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Запуск, окно и обновления — без лишних вкладок.',
            style: TextStyle(fontSize: 15, color: _ink.withOpacity(0.55)),
          ),
          const SizedBox(height: 28),
          _sectionTitle('Запуск и окно'),
          const SizedBox(height: 12),
          _cardBox(children: [
            if (Platform.isWindows)
              _toggle(
                title: 'Автозапуск',
                subtitle: 'Запускать DeskForce при входе в Windows',
                value: _autostart,
                onChanged: _busy
                    ? null
                    : (v) async {
                        setState(() => _busy = true);
                        final ok = await dfSetWindowsAutostart(v);
                        setState(() {
                          _autostart = ok ? v : _autostart;
                          _busy = false;
                        });
                      },
              ),
            _toggle(
              title: 'Запуск в трее',
              subtitle:
                  'Скрывать главное окно при старте (остаётся в системном трее)',
              value: _startTray,
              onChanged: (v) async {
                await dfSetLocalBool(kDfStartInTray, v);
                if (v) await dfSetLocalBool(kDfStartFullscreen, false);
                setState(() {
                  _startTray = v;
                  if (v) _startFs = false;
                });
              },
            ),
            _toggle(
              title: 'Полноэкранный режим при запуске',
              subtitle:
                  'Разворачивать главное окно на весь экран при открытии (по умолчанию включено)',
              value: _startFs,
              onChanged: (v) async {
                await dfSetLocalBool(kDfStartFullscreen, v);
                if (v) await dfSetLocalBool(kDfStartInTray, false);
                setState(() {
                  _startFs = v;
                  if (v) _startTray = false;
                });
              },
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Полный экран сейчас',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17, color: _ink)),
              subtitle: Text('Переключить развёрнутое окно прямо сейчас',
                  style:
                      TextStyle(color: _ink.withOpacity(0.55), fontSize: 14)),
              trailing: TextButton(
                onPressed: () => dfToggleFullscreen(),
                child: const Text('Переключить',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
          const SizedBox(height: 28),
          _sectionTitle('Обновления'),
          const SizedBox(height: 12),
          _cardBox(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Проверить обновления',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17, color: _ink)),
              subtitle: Text(
                'Только с deskforce.dr6ter.ru — без сторонних серверов',
                style: TextStyle(color: _ink.withOpacity(0.55), fontSize: 14),
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brass,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: () => dfCheckUpdateManual(context),
                child: const Text('Обновление',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
          const SizedBox(height: 28),
          _sectionTitle('О программе'),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, String>>(
            future: () async {
              return {
                'version': await bind.mainGetVersion(),
                'build': await bind.mainGetBuildDate(),
              };
            }(),
            builder: (context, snap) {
              final v = snap.data?['version'] ?? '1.1.0';
              final b = snap.data?['build'] ?? '';
              return _cardBox(children: [
                Row(
                  children: [
                    loadIcon(48),
                    const SizedBox(width: 14),
                    const Text('DeskForce УД',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _ink)),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Версия: $v',
                    style: const TextStyle(fontSize: 16, color: _ink)),
                if (b.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Сборка: $b',
                      style: TextStyle(
                          fontSize: 15, color: _ink.withOpacity(0.6))),
                ],
                const SizedBox(height: 14),
                _link('Личный кабинет', () => openDeskForceCabinet()),
                _link(
                    'Тарифы',
                    () => openDeskForceCabinet(
                          url:
                              'https://deskforce.dr6ter.ru/cabinet/billing?embed=1',
                          title: 'Тарифы',
                        )),
                _link('Инструкция', () async {
                  await launchUrl(
                      Uri.parse('https://deskforce.dr6ter.ru/guide'),
                      mode: LaunchMode.externalApplication);
                }),
              ]);
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _brass, width: 1.4),
                backgroundColor: _card,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => openDeskForceCabinet(),
              child: const Text('Открыть личный кабинет',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(color: Color(0xFFF5C518)),
            child: const Text(
              'Copyright © 2026 DeskForce УД\nDeskForce — удалённый доступ для вашей команды',
              style: TextStyle(
                color: Color(0xFF111111),
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: Color(0xFF8F6A1C),
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          label,
          style: const TextStyle(
            color: _brass,
            decoration: TextDecoration.underline,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _cardBox({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x3312161C)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1412161C), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _toggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: _brass,
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 17, color: _ink)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 14, color: _ink.withOpacity(0.55))),
      value: value,
      onChanged: onChanged,
    );
  }
}
