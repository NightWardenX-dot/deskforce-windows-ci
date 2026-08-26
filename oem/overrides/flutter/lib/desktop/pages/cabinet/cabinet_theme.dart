import 'package:flutter/material.dart';

/// DeskForce paper / brass palette shared by native cabinet screens.
class DfCabinetTheme {
  static const ink = Color(0xFF12161C);
  static const paper = Color(0xFFF3EFE6);
  static const card = Color(0xFFFBF8F1);
  static const brass = Color(0xFFB8892A);
  static const brassDeep = Color(0xFF8F6A1C);
  static const bar = Color(0xFFE8E2D4);
  static const border = Color(0x3312161C);
  static const danger = Color(0xFFB33A2B);
  static const ok = Color(0xFF2F6B3A);

  static InputDecoration field(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: ink.withOpacity(0.65)),
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: brass, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  static ButtonStyle primaryButton() => ElevatedButton.styleFrom(
        backgroundColor: brass,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      );

  static ButtonStyle ghostButton() => OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: brass, width: 1.2),
        backgroundColor: card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      );

  static Widget panel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1412161C), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: child,
    );
  }

  static Widget sectionTitle(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: brassDeep,
        ),
      );

  static Widget heading(String text, {String? subtitle}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: ink,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(fontSize: 14, color: ink.withOpacity(0.55))),
          ],
        ],
      );
}
