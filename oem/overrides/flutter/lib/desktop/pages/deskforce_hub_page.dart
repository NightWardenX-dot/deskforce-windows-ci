import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_page.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/deskforce_settings_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:get/get.dart';

/// Unified entry: settings (no login) + personal cabinet (login when needed).
enum DeskForceHubTab { settings, cabinet }

class DeskForceHubPage extends StatefulWidget {
  const DeskForceHubPage({
    Key? key,
    this.initialTab = DeskForceHubTab.settings,
    this.cabinetUrl = 'https://deskforce.dr6ter.ru/cabinet/?embed=1',
    this.cabinetTitle = 'Личный кабинет',
  }) : super(key: key);

  static const tabKey = 'deskforce-hub';

  final DeskForceHubTab initialTab;
  final String cabinetUrl;
  final String cabinetTitle;

  @override
  State<DeskForceHubPage> createState() => _DeskForceHubPageState();
}

class _DeskForceHubPageState extends State<DeskForceHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  static const _ink = DfCabinetTheme.ink;
  static const _paper = DfCabinetTheme.paper;
  static const _brass = DfCabinetTheme.brass;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == DeskForceHubTab.cabinet ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _returnToHome() {
    try {
      final tabController = Get.find<DesktopTabController>();
      tabController.closeBy(DeskForceHubPage.tabKey);
      tabController.jumpToByKey(kTabLabelHomePage);
    } catch (e) {
      debugPrint('DeskForce hub: return to home failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: const Color(0xFF0C1422),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'На главную',
                      onPressed: _returnToHome,
                      icon: const Icon(Icons.arrow_back, color: _brass),
                    ),
                    const Expanded(
                      child: Text(
                        'Настройки и кабинет',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Material(
            color: const Color(0xFF0C1422),
            child: TabBar(
              controller: _tabs,
              indicatorColor: _brass,
              labelColor: _brass,
              unselectedLabelColor: _ink.withOpacity(0.55),
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              tabs: const [
                Tab(text: 'Настройки'),
                Tab(text: 'Личный кабинет'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const DeskForceSettingsPage(key: ValueKey('deskforce-settings')),
                DeskForceCabinetPage(
                  key: const ValueKey('deskforce-cabinet-embed'),
                  initialUrl: widget.cabinetUrl,
                  title: widget.cabinetTitle,
                  embedded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Open unified hub tab (settings always accessible; cabinet tab may require login).
void openDeskForceHub({
  DeskForceHubTab initialTab = DeskForceHubTab.settings,
  String cabinetUrl = 'https://deskforce.dr6ter.ru/cabinet/?embed=1',
  String cabinetTitle = 'Личный кабинет',
}) {
  try {
    final tabController = Get.find<DesktopTabController>();
    tabController.add(TabInfo(
      key: DeskForceHubPage.tabKey,
      label: initialTab == DeskForceHubTab.cabinet ? cabinetTitle : 'Настройки',
      selectedIcon: Icons.tune,
      unselectedIcon: Icons.tune_outlined,
      page: DeskForceHubPage(
        initialTab: initialTab,
        cabinetUrl: cabinetUrl,
        cabinetTitle: cabinetTitle,
      ),
    ));
  } catch (e, st) {
    debugPrintStack(label: 'openDeskForceHub failed: $e', stackTrace: st);
  }
}
