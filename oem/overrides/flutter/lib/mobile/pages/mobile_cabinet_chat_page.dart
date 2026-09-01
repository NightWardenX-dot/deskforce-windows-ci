import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_session.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/screens/chat_screen.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';

/// Android chat tab — DeskForce cabinet chat hub (same as desktop).
class MobileCabinetChatPage extends StatelessWidget implements PageShape {
  MobileCabinetChatPage({Key? key}) : super(key: key);

  @override
  final title = translate('Chat');

  @override
  final icon = const Icon(Icons.chat_bubble_outline);

  @override
  final appBarActions = const <Widget>[];

  @override
  Widget build(BuildContext context) {
    DfCabinetSession.ensure();
    return Theme(
      data: DfCabinetTheme.darkTheme(),
      child: const ColoredBox(
        color: DfCabinetTheme.paper,
        child: CabinetChatScreen(),
      ),
    );
  }
}
