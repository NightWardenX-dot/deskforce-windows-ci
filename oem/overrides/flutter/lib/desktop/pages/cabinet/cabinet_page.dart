import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_session.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/screens/auth_screen.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/screens/billing_screen.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/screens/devices_screen.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/screens/overview_screen.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/screens/profile_screen.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/screens/support_screen.dart';
import 'package:url_launcher/url_launcher.dart';

enum CabinetSection { overview, devices, billing, support, profile }

CabinetSection cabinetSectionFromUrl(String url) {
  final u = url.toLowerCase();
  if (u.contains('/billing')) return CabinetSection.billing;
  if (u.contains('/support')) return CabinetSection.support;
  if (u.contains('/devices')) return CabinetSection.devices;
  if (u.contains('/profile') || u.contains('/account')) {
    return CabinetSection.profile;
  }
  return CabinetSection.overview;
}

/// Native DeskForce personal cabinet (paper / brass).
class DeskForceCabinetPage extends StatefulWidget {
  final String initialUrl;
  final String title;

  const DeskForceCabinetPage({
    Key? key,
    this.initialUrl = 'https://deskforce.dr6ter.ru/cabinet/?embed=1',
    this.title = 'Личный кабинет',
  }) : super(key: key);

  static const tabKey = 'deskforce-cabinet';

  @override
  State<DeskForceCabinetPage> createState() => _DeskForceCabinetPageState();
}

class _DeskForceCabinetPageState extends State<DeskForceCabinetPage> {
  late CabinetSection _section;
  late bool _loggedIn;

  @override
  void initState() {
    super.initState();
    DfCabinetSession.ensure();
    _section = cabinetSectionFromUrl(widget.initialUrl);
    _loggedIn = CabinetApi.instance.isLoggedIn;
    if (_loggedIn) {
      DfCabinetSession.to.refresh();
    }
  }

  void _go(CabinetSection s) {
    dfPlayClickSound();
    setState(() => _section = s);
  }

  void _goNamed(String name) {
    switch (name) {
      case 'devices':
        _go(CabinetSection.devices);
        break;
      case 'billing':
        _go(CabinetSection.billing);
        break;
      case 'support':
        _go(CabinetSection.support);
        break;
      case 'profile':
        _go(CabinetSection.profile);
        break;
      default:
        _go(CabinetSection.overview);
    }
  }

  Future<void> _openBrowser() async {
    await dfPlayClickSound();
    final uri = Uri.parse(widget.initialUrl.contains('cabinet')
        ? widget.initialUrl
        : 'https://deskforce.dr6ter.ru/cabinet/?embed=1');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String get _sectionTitle {
    switch (_section) {
      case CabinetSection.overview:
        return widget.title;
      case CabinetSection.devices:
        return 'Устройства';
      case CabinetSection.billing:
        return 'Тарифы';
      case CabinetSection.support:
        return 'Поддержка';
      case CabinetSection.profile:
        return 'Профиль';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn && !CabinetApi.instance.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loggedIn && !CabinetApi.instance.isLoggedIn) {
          setState(() {
            _loggedIn = false;
            _section = CabinetSection.overview;
          });
        }
      });
    }
    return Theme(
      data: DfCabinetTheme.darkTheme(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF070B14),
              Color(0xFF0C1422),
              Color(0xFF070B14),
            ],
          ),
        ),
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: !_loggedIn
                  ? CabinetAuthScreen(
                      onLoggedIn: () {
                        setState(() => _loggedIn = true);
                        DfCabinetSession.to.refresh();
                      },
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sideNav(),
                        Expanded(child: _body()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: DfCabinetTheme.bar,
        border: Border(bottom: BorderSide(color: DfCabinetTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle_outlined,
              color: DfCabinetTheme.brass, size: 20),
          const SizedBox(width: 8),
          Text(
            _sectionTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: DfCabinetTheme.ink,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          if (_loggedIn)
            TextButton(
              onPressed: () async {
                await dfPlayClickSound();
                await CabinetApi.instance.logout();
                if (mounted) {
                  setState(() {
                    _loggedIn = false;
                    _section = CabinetSection.overview;
                  });
                }
              },
              child: const Text('Выйти'),
            ),
          TextButton(
            onPressed: _openBrowser,
            child: const Text('В браузере'),
          ),
        ],
      ),
    );
  }

  Widget _sideNav() {
    final items = <Map<String, Object>>[
      {
        'section': CabinetSection.overview,
        'icon': Icons.dashboard_outlined,
        'label': 'Обзор',
      },
      {
        'section': CabinetSection.devices,
        'icon': Icons.devices_other_outlined,
        'label': 'Устройства',
      },
      {
        'section': CabinetSection.billing,
        'icon': Icons.payments_outlined,
        'label': 'Тарифы',
      },
      {
        'section': CabinetSection.support,
        'icon': Icons.support_agent_outlined,
        'label': 'Поддержка',
      },
      {
        'section': CabinetSection.profile,
        'icon': Icons.person_outline,
        'label': 'Профиль',
      },
    ];
    return Container(
      width: 168,
      decoration: const BoxDecoration(
        color: Color(0xCC0F172A),
        border: Border(right: BorderSide(color: DfCabinetTheme.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          for (final item in items)
            _navTile(
              selected: _section == item['section'],
              icon: item['icon'] as IconData,
              label: item['label'] as String,
              onTap: () => _go(item['section'] as CabinetSection),
            ),
        ],
      ),
    );
  }

  Widget _navTile({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0x262DD4BF) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? DfCabinetTheme.brassDeep
                      : DfCabinetTheme.ink.withOpacity(0.55)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? DfCabinetTheme.ink
                        : DfCabinetTheme.ink.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_section) {
      case CabinetSection.overview:
        return CabinetOverviewScreen(onNavigate: _goNamed);
      case CabinetSection.devices:
        return const CabinetDevicesScreen();
      case CabinetSection.billing:
        return const CabinetBillingScreen();
      case CabinetSection.support:
        return const CabinetSupportScreen();
      case CabinetSection.profile:
        return CabinetProfileScreen(
          onLoggedOut: () {
                          setState(() {
                            _loggedIn = false;
                            _section = CabinetSection.overview;
                          });
                          DfCabinetSession.to.refresh();
                        },
        );
    }
  }
}
