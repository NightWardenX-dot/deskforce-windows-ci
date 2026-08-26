import 'package:flutter/material.dart';

/// DeskForce paper / brass palette shared by native cabinet screens.
class DfCabinetTheme {
  static const ink = Color(0xFFE8F4FF);
  static const paper = Color(0xFF070B14);
  static const card = Color(0xD60C1422);
  static const brass = Color(0xFF2DD4BF);
  static const brassDeep = Color(0xFF0D9488);
  static const bar = Color(0xEE070B14);
  static const border = Color(0x338BA0B8);
  static const danger = Color(0xFFF87171);
  static const ok = Color(0xFF34D399);

  /// Readable field text on dark slate panels (app ThemeMode.light otherwise paints dark glyphs).
  static const inputStyle = TextStyle(color: ink, fontSize: 15.5, height: 1.3);
  static const hintStyle = TextStyle(color: Color(0x99E8F4FF), fontSize: 15);

  static ThemeData darkTheme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: paper,
        canvasColor: paper,
        cardColor: card,
        primaryColor: brass,
        colorScheme: const ColorScheme.dark(
          primary: brass,
          secondary: brassDeep,
          surface: paper,
          onSurface: ink,
          onPrimary: Color(0xFF041016),
        ),
        textTheme: const TextTheme(
          bodyLarge: inputStyle,
          bodyMedium: inputStyle,
          titleMedium: inputStyle,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: brass,
          selectionColor: Color(0x662DD4BF),
          selectionHandleColor: brass,
        ),
      );

  static InputDecoration field(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: ink.withOpacity(0.65)),
        hintStyle: hintStyle,
        floatingLabelStyle: TextStyle(color: brass),
        filled: true,
        fillColor: const Color(0xEE111827),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: brass, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  static ButtonStyle primaryButton() => ElevatedButton.styleFrom(
        backgroundColor: brass,
        foregroundColor: const Color(0xFF041016),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  static ButtonStyle ghostButton() => OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: brass, width: 1.2),
        backgroundColor: const Color(0xB30F172A),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  static Widget panel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x38000000), blurRadius: 26, offset: Offset(0, 18)),
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
