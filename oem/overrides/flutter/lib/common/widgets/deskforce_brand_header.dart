import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

/// DeskForce logo row for mobile settings — avoids garbled PNG wordmark scaling.
Widget deskforceBrandHeader({double iconSize = 40}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        loadIcon(iconSize),
        const SizedBox(width: 12),
        const Text(
          'DeskForce',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF12161C),
            letterSpacing: -0.3,
            height: 1.1,
          ),
        ),
      ],
    ),
  );
}
