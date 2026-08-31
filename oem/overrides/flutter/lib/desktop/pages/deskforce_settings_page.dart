import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/deskforce_startup.dart';
import 'package:flutter_hbb/common/deskforce_update.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart' show setPasswordDialog;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// DeskForce slate/teal settings — single scroll, site visual language.
class DeskForceSettingsPage extends StatefulWidget {
  const DeskForceSettingsPage({Key? key}) : super(key: key);

  @override
  State<DeskForceSettingsPage> createState() => _DeskForceSettingsPageState();
}

class _DeskForceSettingsPageState extends State<DeskForceSettingsPage> {
  static const _ink = DfCabinetTheme.ink;
  static const _paper = DfCabinetTheme.paper;
  static const _card = Color(0xFF0C1422);
  static const _brass = DfCabinetTheme.brass;

  bool _autostart = false;
  bool _startTray = false;
  bool _startFs = false; // default OFF (beta.16 safe start)
  bool _clickSound = false; // default OFF
  bool _hideOnLan = false; // Deny LAN discovery → enable-lan-discovery = N
  bool _busy = false;
  bool _testBuilds = false;
  String _updateChannel = 'release';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auto = await dfIsWindowsAutostartEnabled();
    // "Deny LAN discovery" in stock UI: reverse of enable-lan-discovery
    final lanEnabled = mainGetBoolOptionSync(kOptionEnableLanDiscovery);
    final testBuilds = await dfTestBuildsEnabled();
    final channel = await dfGetUpdateChannel();
    setState(() {
      _autostart = auto || dfLocalBool(kDfAutostart);
      _testBuilds = testBuilds;
      _updateChannel = channel;
      _startTray = dfLocalBool(kDfStartInTray);
      _startFs = dfLocalBoolDefaultOff(kDfStartFullscreen);
      _clickSound = dfClickSoundEnabled();
      _hideOnLan = !lanEnabled;
    });
  }

  Future<void> _setHideOnLan(bool hide) async {
    // hide=true → enable-lan-discovery = N (do not answer LAN pings)
    await mainSetBoolOption(kOptionEnableLanDiscovery, !hide);
    setState(() => _hideOnLan = !mainGetBoolOptionSync(kOptionEnableLanDiscovery));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        children: [
          const Text(
            'Настройки',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Запуск, окно, локальная сеть и обновления. Личный кабинет — на соседней вкладке.',
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
                  'Разворачивать главное окно при открытии (по умолчанию выключено — безопасный старт)',
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
            _toggle(
              title: 'Звук нажатий',
              subtitle:
                  'Короткий щелчок при нажатии основных кнопок (по умолчанию выключено)',
              value: _clickSound,
              onChanged: (v) async {
                await dfSetClickSoundEnabled(v);
                setState(() => _clickSound = v);
                if (v) await dfPlayClickSound();
              },
            ),
            const Divider(height: 24, color: Color(0x338BA0B8)),
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
                style: TextButton.styleFrom(foregroundColor: _brass),
                child: const Text('Переключить',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
          const SizedBox(height: 28),
          _sectionTitle('Доступ к этому ПК'),
          const SizedBox(height: 12),
          _buildAccessSecurityCard(),
          const SizedBox(height: 28),
          _sectionTitle('Локальная сеть'),
          const SizedBox(height: 12),
          _cardBox(children: [
            _toggle(
              title: 'Не видно в локальной сети',
              subtitle:
                  'Не отвечать на поиск устройств в LAN — другие ПК в этой сети не увидят этот компьютер',
              value: _hideOnLan,
              onChanged: (v) => _setHideOnLan(v),
            ),
          ]),
          const SizedBox(height: 28),
          _sectionTitle('Обновления'),
          const SizedBox(height: 12),
          _cardBox(children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Канал обновлений: ${dfUpdateChannelLabel(_updateChannel)}'
                '${_testBuilds ? '' : ' (только релиз — включите «Тестовые сборки» для смены)'}',
                style: TextStyle(fontSize: 14, color: _ink.withOpacity(0.72)),
              ),
            ),
            _toggle(
              title: 'Тестовые сборки',
              subtitle:
                  'Показать выбор канала обновлений (альфа / бета / релиз). По умолчанию — только релиз.',
              value: _testBuilds,
              onChanged: (v) async {
                await dfSetTestBuildsEnabled(v);
                setState(() {
                  _testBuilds = v;
                  if (!v) _updateChannel = 'release';
                });
              },
            ),

          if (_testBuilds) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Канал: ${dfUpdateChannelLabel(_updateChannel)}',
                style: TextStyle(color: _ink.withOpacity(0.7), fontSize: 14),
              ),
            ),
            ...kDfUpdateChannels.map((ch) => RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  activeColor: _brass,
                  title: Text(dfUpdateChannelLabel(ch),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16, color: _ink)),
                  subtitle: Text(
                    ch == 'release'
                        ? 'Стабильные сборки для всех пользователей'
                        : ch == 'beta'
                            ? 'Предрелизные сборки для тестирования'
                            : 'Экспериментальные сборки — может быть нестабильно',
                    style: TextStyle(fontSize: 13, color: _ink.withOpacity(0.55)),
                  ),
                  value: ch,
                  groupValue: _updateChannel,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          if (v == null) return;
                          await dfSetUpdateChannel(v);
                          setState(() => _updateChannel = v);
                        },
                )),
          ],

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
                  foregroundColor: const Color(0xFF041016),
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
                _link('Инструкция', () async {
                  await launchUrl(
                      Uri.parse('https://deskforce.dr6ter.ru/guide'),
                      mode: LaunchMode.externalApplication);
                }),
              ]);
            },
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1422),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x332DD4BF)),
            ),
            child: const Text(
              'Copyright © 2026 DeskForce УД\nDeskForce — удалённый доступ для вашей команды',
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w600,
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
        color: _brass,
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
        color: _card.withOpacity(0.84),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x338BA0B8)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
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
