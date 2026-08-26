// DeskForce mobile connect — AutoSizeTextField + themed recent peers
// (no stock autocomplete overlay / no empty PeerTab fill)

import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/deskforce_update.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.connected_tv);

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();
  StreamSubscription? _uniLinksSubscription;

  static const _paper = Color(0xFFFBF8F1);
  static const _panel = Color(0xFFE8E2D4);
  static const _ink = Color(0xFF12161C);
  static const _brass = Color(0xFFB8892A);
  static const _muted = Color(0xFF4A5563);
  static const _label = Color(0xFF8F6A1C);

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
        if (mounted) {
          await dfCheckUpdateOnStartup(context);
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await dfCheckUpdateOnStartup(context);
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bind.mainLoadRecentPeers();
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: kMobilePageConstraints,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRemoteIDTextField(),
              const SizedBox(height: 12),
              _buildRecentPeers(),
            ],
          ),
        ),
      ),
    );
  }

  void onConnect() {
    var id = _idController.id;
    connect(context, id);
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      final textLength = _idEditingController.value.text.length;
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  Widget _buildRemoteIDTextField() {
    return SizedBox(
      height: 84,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.all(Radius.circular(13)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 16, right: 16),
                  child: AutoSizeTextField(
                    controller: _idEditingController,
                    focusNode: _idFocusNode,
                    minFontSize: 18,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    onChanged: (String text) {
                      _idController.id = text;
                    },
                    style: const TextStyle(
                      fontFamily: 'WorkSans',
                      fontWeight: FontWeight.bold,
                      fontSize: 30,
                      color: _label,
                    ),
                    decoration: InputDecoration(
                      labelText: translate('Remote ID'),
                      border: InputBorder.none,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        letterSpacing: 0.2,
                        color: _muted,
                      ),
                    ),
                    inputFormatters: [IDTextInputFormatter()],
                    onSubmitted: (_) {
                      onConnect();
                    },
                  ),
                ),
              ),
              Obx(() => Offstage(
                    offstage: _idEmpty.value,
                    child: IconButton(
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                            _idEditingController.clear();
                          });
                        },
                        icon: const Icon(Icons.clear, color: _muted)),
                  )),
              SizedBox(
                width: 60,
                height: 60,
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: _brass, size: 45),
                  onPressed: onConnect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentPeers() {
    return ListenableBuilder(
      listenable: gFFI.recentPeersModel,
      builder: (context, _) {
        final peers = gFFI.recentPeersModel.peers.take(6).toList();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0x3312161C)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'НЕДАВНИЕ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: _label,
                ),
              ),
              const SizedBox(height: 8),
              if (peers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Здесь появятся устройства, к которым вы уже подключались.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: Color(0x8012161C),
                    ),
                  ),
                )
              else
                ...peers.map((peer) {
                  final title = peer.alias.isNotEmpty
                      ? peer.alias
                      : (peer.id.isNotEmpty ? formatID(peer.id) : '—');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: _paper,
                      borderRadius: BorderRadius.circular(3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(3),
                        onTap: () {
                          setState(() {
                            _idController.id = peer.id;
                            _idEditingController.text = formatID(peer.id);
                          });
                          onConnect();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  size: 18, color: _label),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}
