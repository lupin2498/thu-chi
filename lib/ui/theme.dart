import 'package:flutter/material.dart';

import '../data/models.dart';

const Color kPrimary = Color(0xFF1565C0);
const Color kExpenseColor = Color(0xFFE53935);
const Color kIncomeColor = Color(0xFF2E7D32);
const Color kTransferColor = Color(0xFF1E88E5);

Color txnColor(TxnType t) => switch (t) {
  TxnType.expense => kExpenseColor,
  TxnType.income => kIncomeColor,
  TxnType.transfer => kTransferColor,
};

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: brightness,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  return base.copyWith(
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF3F6FA)
        : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.light ? kPrimary : scheme.surface,
      foregroundColor: brightness == Brightness.light ? Colors.white : scheme.onSurface,
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
