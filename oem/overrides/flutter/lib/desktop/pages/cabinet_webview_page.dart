import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_page.dart';
import 'package:flutter_hbb/desktop/pages/deskforce_hub_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:get/get.dart';

export 'package:flutter_hbb/desktop/pages/cabinet/cabinet_page.dart'
    show DeskForceCabinetPage, CabinetSection, cabinetSectionFromUrl;

/// Open native cabinet as a main-window tab. Never opens the system browser.
Future<void> openDeskForceCabinet({
  String url = 'https://deskforce.dr6ter.ru/cabinet/?embed=1',
  String title = 'Личный кабинет',
}) async {
  openDeskForceHub(
    initialTab: DeskForceHubTab.cabinet,
    cabinetUrl: url,
    cabinetTitle: title,
  );
}
