import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';

/// In-app DeskForce personal cabinet (WebView2 on Windows).
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
  final WebviewController _controller = WebviewController();
  bool _ready = false;
  bool _failed = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!Platform.isWindows) {
      setState(() {
        _failed = true;
        _error = 'Встроенный кабинет доступен в Windows-клиенте.';
      });
      return;
    }
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(const Color(0xFFF3EFE6));
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.loadUrl(widget.initialUrl);
      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(widget.initialUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF12161C);
    const paper = Color(0xFFF3EFE6);
    const brass = Color(0xFFB8892A);
    return Container(
      color: paper,
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFE8E2D4),
              border: Border(bottom: BorderSide(color: Color(0x3312161C))),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_circle_outlined, color: brass, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ink,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    if (_ready) {
                      await _controller.reload();
                    }
                  },
                  child: const Text('Обновить'),
                ),
                TextButton(
                  onPressed: _openExternal,
                  child: const Text('В браузере'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _failed
                ? _Fallback(error: _error, onOpen: _openExternal)
                : (!_ready
                    ? const Center(
                        child: CircularProgressIndicator(color: brass),
                      )
                    : Webview(_controller)),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String error;
  final VoidCallback onOpen;
  const _Fallback({required this.error, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 40, color: Color(0xFFB8892A)),
              const SizedBox(height: 12),
              const Text(
                'Не удалось открыть встроенный кабинет.\nОткройте его во внешнем браузере.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF12161C)),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.45)),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB8892A),
                  foregroundColor: const Color(0xFF111111),
                ),
                onPressed: onOpen,
                child: const Text('Открыть личный кабинет'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open cabinet as a main-window tab (preferred) or fallback externally.
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
