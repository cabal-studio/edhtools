import 'package:flutter/material.dart';

const kBg = Color(0xFF120E1F);
const kCard = Color(0xFF211A3A);
const kLine = Color(0xFF342A56);
const kGold = Color(0xFFE2B552);
const kGoldLight = Color(0xFFF5D27A);
const kMuted = Color(0xFFA59CC0);
const kOk = Color(0xFF4FC28A);
const kBad = Color(0xFFEF6B5B);
const kBlue = Color(0xFF5AA0EF);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kGold,
    brightness: Brightness.dark,
    surface: kBg,
  ).copyWith(primary: kGold, onPrimary: const Color(0xFF1B1405));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    cardTheme: const CardThemeData(
      color: kCard,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: kLine),
      ),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: kBg, centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF150F27),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kLine)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kLine)),
    ),
  );
}

String fmtPct(double x) => '${(x * 100).toStringAsFixed(1)}%';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirmDialog(BuildContext context, String text,
    {String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Ejecuta una acción mostrando errores como snackbar.
Future<void> guard(BuildContext context, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    if (context.mounted) toast(context, 'Error: $e');
  }
}
