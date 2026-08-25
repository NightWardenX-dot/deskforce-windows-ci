import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';

Widget getConnectionPageTitle(BuildContext context, bool isWeb) {
  return Row(
    children: [
      Expanded(
          child: Row(
        children: [
          AutoSizeText(
            'Подключение',
            maxLines: 1,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.merge(const TextStyle(height: 1)),
          ).marginOnly(right: 4),
        ],
      )),
    ],
  );
}
