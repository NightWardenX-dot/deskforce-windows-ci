// DeskForce connect panel — plain TextField + Recent/Fav/Address book (no stock autocomplete overlay)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/platform_model.dart';
import '../../models/peer_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;
import 'package:flutter_hbb/desktop/pages/deskforce_peer_lists.dart';

/// DeskForce paper/brass server status — not the classic RustDesk green/red dot.
class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  Timer? _updateTimer;

  static const _ink = Color(0xFFE8F4FF);
  static const _brass = Color(0xFF2DD4BF);
  static const _offline = Color(0xFFF87171);

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      widget.onSvcStatusChanged?.call();
      final stopped = _svcStopped.value;
      final st = stateGlobal.svcStatus.value;
      final online = !stopped && st == SvcStatus.ready;
      final connecting = !stopped && st == SvcStatus.connecting;

      String label;
      Color badgeBg;
      Color badgeFg;
      if (stopped) {
        label = 'Офлайн';
        badgeBg = const Color(0xFF1A2332);
        badgeFg = _offline;
      } else if (connecting) {
        label = 'Подключение…';
        badgeBg = const Color(0x332DD4BF);
        badgeFg = _brass;
      } else if (online) {
        label = 'Онлайн';
        badgeBg = const Color(0x332DD4BF);
        badgeFg = const Color(0xFF34D399);
      } else {
        label = 'Офлайн';
        badgeBg = const Color(0xFF1A2332);
        badgeFg = _offline;
      }

      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _brass.withOpacity(0.45)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: badgeFg,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                stopped
                    ? 'Служба DeskForce остановлена'
                    : connecting
                        ? 'Соединение с сервером…'
                        : online
                            ? 'Сервер доступен'
                            : 'Нет связи с сервером',
                style: TextStyle(
                  fontSize: 13,
                  color: _ink.withOpacity(0.55),
                ),
              ),
            ),
            if (stopped)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: _brass,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () async {
                  await start_service(true);
                },
                child: const Text(
                  'Включить',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
          ],
        ),
      );
    });
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  final _idController = IDTextEditingController();
  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  bool isWindowMinimized = false;
  final _menuOpen = false.obs;

  @override
  void initState() {
    super.initState();
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<IDTextEditingController>(_idController);
    Get.put<TextEditingController>(_idController);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bind.mainLoadRecentPeers();
      bind.mainLoadLanPeers();
      bind.mainDiscover();
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      final textLength = _idController.value.text.length;
      _idController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildRemoteIDTextField(context);
  }

  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false}) {
    var id = _idController.id;
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal);
  }

  /// UI for the remote ID TextField — DeskForce station connect panel.
  /// Plain TextField only (stock autocomplete overlay reserved a dead panel under
  /// «Подключить устройство» on Windows). Peer lists (incl. Адресная книга) below.
  Widget _buildRemoteIDTextField(BuildContext context) {
    final ink = MyTheme.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ID устройства',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ink.withOpacity(0.55),
          ),
        ),
        const SizedBox(height: 8),
        Obx(() => TextField(
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              focusNode: _idFocusNode,
              controller: _idController,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: 0.8,
                color: MyTheme.dark,
              ),
              maxLines: 1,
              cursorColor: MyTheme.accent,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF111827),
                counterText: '',
                hintText:
                    _idInputFocused.value ? null : 'Введите ID устройства',
                hintStyle: TextStyle(
                  color: ink.withOpacity(0.35),
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0x338BA0B8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0x338BA0B8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: MyTheme.accent, width: 1.4),
                ),
              ),
              inputFormatters: [IDTextInputFormatter()],
              onChanged: (v) {
                _idController.id = v;
              },
              onSubmitted: (_) {
                onConnect();
              },
            ).workaroundFreezeLinuxMint()),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.accent,
              foregroundColor: const Color(0xFF041016),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              onConnect();
            },
            child: const Text(
              'Подключить устройство',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Do NOT wrap in Obx unless an .obs is read in the builder — empty Obx
        // throws in release and Flutter paints RenderErrorBox gray (#C0C0C0),
        // which expands under unbounded Column constraints into a huge slab.
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTapDown: (e) async {
              final offset = e.globalPosition;
              _menuOpen.value = true;
              final x = offset.dx;
              final y = offset.dy;
              await mod_menu
                  .showMenu(
                context: context,
                position: RelativeRect.fromLTRB(x, y, x, y),
                items: [
                  (
                    'Передать файл',
                    () => onConnect(isFileTransfer: true)
                  ),
                ]
                    .map((e) => MenuEntryButton<String>(
                          childBuilder: (TextStyle? style) => Text(
                            e.$1,
                            style: style,
                          ),
                          proc: () => e.$2(),
                          padding: EdgeInsets.symmetric(
                              horizontal: kDesktopMenuPadding.left),
                          dismissOnClicked: true,
                        ))
                    .map((e) => e.build(
                        context,
                        const MenuConfig(
                            commonColor: CustomPopupMenuTheme.commonColor,
                            height: CustomPopupMenuTheme.height,
                            dividerHeight:
                                CustomPopupMenuTheme.dividerHeight)))
                    .expand((i) => i)
                    .toList(),
                elevation: 8,
              )
                  .then((_) {
                _menuOpen.value = false;
              });
            },
            child: Text(
              'Дополнительно',
              style: TextStyle(
                fontSize: 14,
                color: ink.withOpacity(0.5),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLocalPeers(context, ink),
        const SizedBox(height: 12),
        DeskForcePeerLists(
          ink: ink,
          onPickId: (id) {
            setState(() {
              _idController.id = id;
            });
            onConnect();
          },
        ),
      ],
    );
  }

  Widget _buildLocalPeers(BuildContext context, Color ink) {
    return ListenableBuilder(
      listenable: gFFI.lanPeersModel,
      builder: (context, _) {
        final peers = gFFI.lanPeersModel.peers.take(12).toList();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1422),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x338BA0B8)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ЛОКАЛЬНАЯ СЕТЬ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFF2DD4BF),
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2DD4BF),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      bind.mainLoadLanPeers();
                      bind.mainDiscover();
                    },
                    child: const Text(
                      'Обновить',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (peers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Ищем устройства в локальной сети… Нажмите «Обновить», если список пуст.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: ink.withOpacity(0.5),
                    ),
                  ),
                )
              else
                ...peers.map((peer) => _recentPeerTile(peer, ink)),
            ],
          ),
        );
      },
    );
  }

  Widget _recentPeerTile(Peer peer, Color ink) {
    final title = peer.alias.isNotEmpty
        ? peer.alias
        : (peer.id.isNotEmpty ? formatID(peer.id) : '—');
    final subtitle = [
      if (peer.username.isNotEmpty) peer.username,
      if (peer.hostname.isNotEmpty) peer.hostname,
    ].join('@');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _idController.id = peer.id;
            });
            onConnect();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: peer.online
                        ? const Color(0xFF34D399)
                        : const Color(0xFF8BA0B8),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x552DD4BF)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8F4FF),
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: ink.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFF2DD4BF)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
