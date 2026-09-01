import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/cabinet_webview_page.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_session.dart';
import 'package:flutter_hbb/common/deskforce_startup.dart';
import 'package:flutter_hbb/common/deskforce_update.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/deskforce_hub_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2DD4BF);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();
  final GlobalKey _connectionPageKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final ink = MyTheme.dark;
    return _buildBlock(
      child: Container(
        color: MyTheme.canvasColor,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _DeskForcePaperGridPainter()),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<DeskForceUpdateBannerData?>(
                valueListenable: dfUpdateBannerNotifier,
                builder: (context, _, __) => LayoutBuilder(
                  builder: (context, constraints) {
                  // Zero/non-finite width happens for a frame while HWND sizes —
                  // prefer wide to avoid a narrow→wide layout flip on open.
                  final mw = constraints.maxWidth;
                  final wide = (!mw.isFinite || mw <= 0) ? true : mw >= 980;
                  final left = <Widget>[
                    _buildBrandHeader(context, ink),
                    const SizedBox(height: 14),
                    _buildCabinetAccountPanel(context),
                    const SizedBox(height: 22),
                    if (!isOutgoingOnly) buildPresetPasswordWarning(),
                    if (!isOutgoingOnly) ...[
                      _sectionLabel('Этот ПК'),
                      const SizedBox(height: 10),
                      _stationCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildIDBoard(context),
                            const SizedBox(height: 8),
                            buildPasswordBoard(context),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      OnlineStatusWidget(
                        onSvcStatusChanged: () {
                          if (isIncomingOnly && isInHomePage()) {
                            Future.delayed(const Duration(milliseconds: 300),
                                () {
                              _updateWindowSize();
                            });
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildFooterLinks(context),
                    buildPluginEntry(),
                  ];
                  final right = <Widget>[
                    if (!isIncomingOnly) ...[
                      _sectionLabel('Подключение'),
                      const SizedBox(height: 10),
                      _stationCard(child: ConnectionPage(key: _connectionPageKey)),
                    ],
                  ];
                  final bannerTop = dfUpdateBannerNotifier.value != null ? 58.0 : 0.0;
                  final pad = EdgeInsets.fromLTRB(
                    wide ? 28 : 18,
                    18 + bannerTop,
                    wide ? 28 : 18,
                    28,
                  );
                  // CRITICAL (beta.13–16): never attach the same GlobalKey to Row
                  // vs Column. First frame often has narrow/zero width; when the
                  // window settles wide Flutter aborts on element type change —
                  // UI flash then process exit. One stable KeyedSubtree type.
                  final body = wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: SingleChildScrollView(
                                controller: _leftPaneScrollController,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: left,
                                ),
                              ),
                            ),
                            const SizedBox(width: 22),
                            Expanded(
                              flex: 6,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: right,
                                ),
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          controller: _leftPaneScrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...left,
                              if (!isIncomingOnly) ...[
                                const SizedBox(height: 22),
                                ...right,
                              ],
                            ],
                          ),
                        );
                  return KeyedSubtree(
                    key: _childKey,
                    child: Padding(
                      padding: pad,
                      child: body,
                    ),
                  );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Material(
                  elevation: 12,
                  color: Colors.transparent,
                  shadowColor: Colors.black54,
                  child: dfUpdateBannerHost(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandHeader(BuildContext context, Color ink) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        loadIcon(48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DeskForce',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: ink,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Удалённый доступ',
                style: TextStyle(
                  fontSize: 14,
                  color: ink.withOpacity(0.55),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: Color(0xFF2DD4BF),
      ),
    );
  }

  Widget _stationCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xD60C1422),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x338BA0B8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }


  Widget _buildCabinetAccountPanel(BuildContext context) {
    DfCabinetSession.ensure();
    return Obx(() {
      final s = DfCabinetSession.to;
      final logged = s.loggedIn.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCabinetButton(context, loggedIn: logged, label: s.chipLabel),
          if (logged) ...[
            const SizedBox(height: 10),
            _cabinetStatusCard(context, s),
          ],
        ],
      );
    });
  }

  Widget _cabinetStatusCard(BuildContext context, DfCabinetSession s) {
    final ink = const Color(0xFFE8F4FF);
    final brass = const Color(0xFF2DD4BF);
    final devicesPreview = s.devices.take(3).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xD60C1422),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x552DD4BF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                s.licenseActive.value
                    ? Icons.verified_outlined
                    : Icons.warning_amber_outlined,
                size: 18,
                color: s.licenseActive.value
                    ? const Color(0xFF2F6B3A)
                    : brass,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.licenseLabel.isEmpty
                      ? 'Статус лицензии загружается…'
                      : s.licenseLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ink.withOpacity(0.85),
                  ),
                ),
              ),
              if (s.loading.value)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2DD4BF)),
                )
              else
                IconButton(
                  tooltip: 'Обновить',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => s.refresh(),
                  icon: Icon(Icons.refresh, size: 16, color: brass),
                ),
            ],
          ),
          if (s.sessionsHint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              s.sessionsHint,
              style: TextStyle(fontSize: 11, color: ink.withOpacity(0.55), height: 1.3),
            ),
          ],
          if (s.overLimit.value) ...[
            const SizedBox(height: 6),
            Text(
              'Лимит одновременных сессий исчерпан.',
              style: TextStyle(fontSize: 12, color: Color(0xFFF87171), fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Tooltip(
                message: s.sessionsHint.isNotEmpty
                    ? s.sessionsHint
                    : 'Устройства в личном кабинете',
                child: _cabinetChip(
                  'Устройства ${s.onlineDevices.value}/${s.deviceCount.value}',
                  onTap: () => openDeskForceHub(
                    initialTab: DeskForceHubTab.cabinet,
                    cabinetUrl: 'https://deskforce.dr6ter.ru/cabinet/devices?embed=1',
                    cabinetTitle: 'Устройства',
                  ),
                ),
              ),
              _cabinetChip(
                s.localIdLinked.value
                    ? 'Этот ПК привязан'
                    : 'Привязать этот ПК',
                onTap: () async {
                  if (!s.localIdLinked.value) {
                    await s.claimLocalDevice();
                    await s.refresh();
                  } else {
                    openDeskForceHub(
                      initialTab: DeskForceHubTab.cabinet,
                      cabinetUrl: 'https://deskforce.dr6ter.ru/cabinet/devices?embed=1',
                      cabinetTitle: 'Устройства',
                    );
                  }
                },
              ),
              if (s.openTickets.value > 0)
                _cabinetChip(
                  'Тикеты: ${s.openTickets.value}',
                  onTap: () => openDeskForceHub(
                    initialTab: DeskForceHubTab.cabinet,
                    cabinetUrl: 'https://deskforce.dr6ter.ru/cabinet/support?embed=1',
                    cabinetTitle: 'Поддержка',
                  ),
                ),
              _cabinetChip(
                'Тарифы',
                onTap: () => openDeskForceHub(
                  initialTab: DeskForceHubTab.cabinet,
                  cabinetUrl: 'https://deskforce.dr6ter.ru/cabinet/billing?embed=1',
                  cabinetTitle: 'Тарифы',
                ),
              ),
            ],
          ),
          if (devicesPreview.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'С устройствами кабинета',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ink.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 6),
            ...devicesPreview.map((d) {
              final online = d['is_online'] == true;
              final title = (d['hostname'] ?? d['device_id'] ?? '—').toString();
              final id = (d['device_id'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: online
                          ? const Color(0xFF2F6B3A)
                          : ink.withOpacity(0.3),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        id.isEmpty ? title : '$title · $id',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: ink.withOpacity(0.75)),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _cabinetChip(String label, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x1A2DD4BF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x552DD4BF)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFFE8F4FF),
          ),
        ),
      ),
    );
  }

  Widget _buildCabinetButton(BuildContext context,
      {bool loggedIn = false, String label = 'Личный кабинет'}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE8F4FF),
          side: const BorderSide(color: Color(0xFF2DD4BF), width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          backgroundColor: const Color(0xD60C1422),
        ),
        onPressed: () {
          openDeskForceHub(initialTab: DeskForceHubTab.cabinet);
        },
        icon: Icon(
          loggedIn ? Icons.account_circle : Icons.account_circle_outlined,
          color: const Color(0xFF2DD4BF),
        ),
        label: Text(
          loggedIn ? label : 'Войти в кабинет',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildFooterLinks(BuildContext context) {
    Widget link(String label, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: MyTheme.accent,
            decoration: TextDecoration.underline,
            decorationColor: MyTheme.accent,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 8,
          children: [
            link('Настройки и кабинет', () {
              openDeskForceHub(initialTab: DeskForceHubTab.settings);
            }),
            link('Тарифы', () {
              openDeskForceHub(
                initialTab: DeskForceHubTab.cabinet,
                cabinetUrl: 'https://deskforce.dr6ter.ru/cabinet/billing?embed=1',
                cabinetTitle: 'Тарифы',
              );
            }),
          ],
        ),
        const SizedBox(height: 10),
        _buildVersionFooter(context),
      ],
    );
  }


  Widget _buildVersionFooter(BuildContext context) {
    return FutureBuilder<String>(
      future: bind.mainGetVersion(),
      builder: (context, snap) {
        final v = snap.data?.trim() ?? '';
        if (v.isEmpty) return const SizedBox.shrink();
        return ValueListenableBuilder<DeskForceUpdateBannerData?>(
          valueListenable: dfUpdateBannerNotifier,
          builder: (context, banner, _) {
            final hasUpdate = banner != null;
            return Center(
              child: InkWell(
                onTap: hasUpdate
                    ? () => dfShowUpdateDialog(context, banner!.info,
                        localVersion: banner.localVersion)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'DeskForce $v',
                        style: TextStyle(
                          fontSize: 12,
                          color: MyTheme.dark.withOpacity(0.45),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasUpdate) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x332DD4BF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x552DD4BF)),
                          ),
                          child: Text(
                            '→ ${banner!.info.version}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2DD4BF),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  // Kept for compatibility with older call sites / patches.
  Widget buildLeftPane(BuildContext context) => const SizedBox.shrink();

  buildRightPane(BuildContext context) {
    return const ConnectionPage();
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ваш идентификатор',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.color
                      ?.withOpacity(0.55),
                ),
              ),
            ),
            buildPopupMenu(context),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onDoubleTap: () {
            Clipboard.setData(ClipboardData(text: model.serverId.text));
            showToast(translate("Copied"));
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1422),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x338BA0B8)),
            ),
            child: TextFormField(
              controller: model.serverId,
              readOnly: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: MyTheme.dark,
              ),
            ).workaroundFreezeLinuxMint(),
          ),
        ),
      ],
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      onHover: (value) => hover.value = value,
      child: Obx(
        () => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: hover.value ? const Color(0x332DD4BF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x552DD4BF)),
          ),
          child: Text(
            'Настройки и кабинет',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: hover.value
                  ? const Color(0xFFE8F4FF)
                  : const Color(0xFFE8F4FF).withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          showOneTime ? 'Пароль доступа' : translate("Password"),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor?.withOpacity(0.55),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1422),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x338BA0B8)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () {
                    if (showOneTime) {
                      Clipboard.setData(
                          ClipboardData(text: model.serverPasswd.text));
                      showToast(translate("Copied"));
                    }
                  },
                  child: TextFormField(
                    controller: model.serverPasswd,
                    readOnly: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.0,
                      color: MyTheme.dark,
                    ),
                  ).workaroundFreezeLinuxMint(),
                ),
              ),
              if (showOneTime)
                AnimatedRotationWidget(
                  onPressed: () => bind.mainUpdateTemporaryPassword(),
                  child: Tooltip(
                    message: translate('Refresh Password'),
                    child: Obx(() => RotatedBox(
                        quarterTurns: 2,
                        child: Icon(
                          Icons.refresh,
                          color: refreshHover.value
                              ? textColor
                              : const Color(0xFF2DD4BF),
                          size: 22,
                        ))),
                  ),
                  onHover: (value) => refreshHover.value = value,
                ).marginOnly(right: 8),
              if (!bind.isDisableSettings())
                InkWell(
                  child: Tooltip(
                    message: translate('Change Password'),
                    child: Obx(
                      () => Icon(
                        Icons.edit_outlined,
                        color: editHover.value
                            ? textColor
                            : const Color(0xFF2DD4BF),
                        size: 22,
                      ),
                    ),
                  ),
                  onTap: () => setPasswordDialog(),
                  onHover: (value) => editHover.value = value,
                ),
            ],
          ),
        ),
      ],
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    // DeskForce: never render stock install/help cards (pink/gray tall panels).
    // Service status lives in OnlineStatusWidget; installation is via portable EXE.
    return const SizedBox.shrink();
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        false /* DeskForce: never show stock download/update cards */) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://deskforce.dr6ter.ru/downloads/windows/DeskForce.exe');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://deskforce.dr6ter.ru/guide'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://deskforce.dr6ter.ru/guide',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://deskforce.dr6ter.ru/guide'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://deskforce.dr6ter.ru/guide'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    DfCabinetSession.ensure();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // multiWindowManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDeskForceWindowSize();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await dfCheckUpdateOnStartup(context);
    });
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  /// DeskForce: one serialized startup pass only (main.dart may already run it).
  /// Do NOT force-retry maximize/setSize — that re-touched HWND after first paint
  /// and contributed to beta.13–15 native crashes on some DPI setups.
  Future<void> _ensureDeskForceWindowSize() async {
    try {
      await dfApplyStartupWindowBehavior();
    } catch (e) {
      debugPrint('ensureDeskForceWindowSize: $e');
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
      if (DfCabinetSession.to.loggedIn.value) {
        // ignore: unawaited_futures
        DfCabinetSession.to.refresh();
      }
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final pw = await bind.mainGetPermanentPassword();
  final p0 = TextEditingController(text: pw);
  final p1 = TextEditingController(text: pw);
  var errMsg0 = "";
  var errMsg1 = "";
  final RxString rxPass = pw.trim().obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();

  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      bind.mainSetPermanentPassword(password: pass);
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Set Password")),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginSymmetric(vertical: 8),
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            const SizedBox(
              height: 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: 8,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// Subtle paper grid — DeskForce station atmosphere (not stock upstream chrome).
class _DeskForcePaperGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = const Color(0x148BA0B8)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final wash = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x00070B14), Color(0x332DD4BF), Color(0x99070B14)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, wash);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
