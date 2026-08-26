import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:flutter_hbb/desktop/pages/cabinet/cabinet_page.dart'
    show DeskForceCabinetPage, CabinetSection, cabinetSectionFromUrl;

/// Open native cabinet as a main-window tab (preferred) or fallback externally.
Future<void> openDeskForceCabinet({
  String url = 'https://deskforce.dr6ter.ru/cabinet/?embed=1',
  String title = 'Личный кабинет',
}) async {
  try {
    final tabController = Get.find<DesktopTabController>();
    tabController.add(TabInfo(
      key: DeskForceCabinetPage.tabKey,
      label: title,
      selectedIcon: Icons.account_circle,
      unselectedIcon: Icons.account_circle_outlined,
      page: DeskForceCabinetPage(initialUrl: url, title: title),
    ));
  } catch (_) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
