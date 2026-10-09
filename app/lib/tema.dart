/// Colores y tema de la app. Identidad sobria: azul río, tinta casi negra y
/// superficies blancas sobre un gris muy claro. El color fuerte se reserva para
/// el nivel del río. Todo plano y con bordes (las sombras no se ven al sol).
library;

import 'package:flutter/material.dart';

abstract final class Colores {
  static const primario = Color(0xFF0B3C5D);
  static const primarioSuave = Color(0xFFE3EEF6);
  static const agua = Color(0xFF7CC4DE);
  static const fondo = Color(0xFFF4F6F8);
  static const tinta = Color(0xFF111B24);
  static const tintaSecundaria = Color(0xFF44525E);
  static const bordeControl = Color(0xFF5B6770);
  static const bordeSuave = Color(0xFFC3CDD6);
  static const divisor = Color(0xFFDDE3E8);
}

const _radio = BorderRadius.all(Radius.circular(12));

ThemeData temaApp() {
  const esquema = ColorScheme.light(
    primary: Colores.primario,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: Colores.tinta,
    onSurfaceVariant: Colores.tintaSecundaria,
    outline: Colores.bordeControl,
    outlineVariant: Colores.bordeSuave,
    secondaryContainer: Colores.primario,
    onSecondaryContainer: Colors.white,
  );

  // Letra grande por defecto (cuerpo de 18); además se respeta el tamaño de
  // letra que el usuario eligió en su teléfono.
  final base = Typography.material2021(colorScheme: esquema).black;
  final letras = base
      .copyWith(
        bodyLarge: base.bodyLarge?.copyWith(fontSize: 18, height: 1.45),
        bodyMedium: base.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
        titleLarge: base.titleLarge?.copyWith(fontSize: 22, height: 1.25, fontWeight: FontWeight.w700),
        titleMedium: base.titleMedium?.copyWith(fontSize: 18, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: 0),
        titleSmall: base.titleSmall?.copyWith(fontSize: 16, height: 1.3, fontWeight: FontWeight.w700),
        headlineSmall: base.headlineSmall?.copyWith(fontSize: 24, height: 1.2, fontWeight: FontWeight.w700),
        headlineMedium: base.headlineMedium?.copyWith(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800),
        labelLarge: base.labelLarge?.copyWith(fontSize: 18, height: 1.2, fontWeight: FontWeight.w600),
      )
      .apply(bodyColor: Colores.tinta, displayColor: Colores.tinta);

  const formaBoton = RoundedRectangleBorder(borderRadius: _radio);
  final letraBoton = letras.labelLarge;

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.fondo,
    textTheme: letras,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colores.primario,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: _radio, side: BorderSide(color: Colores.bordeSuave)),
    ),
    dividerTheme: const DividerThemeData(color: Colores.divisor, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: formaBoton,
        textStyle: letraBoton,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colores.primario,
        backgroundColor: Colors.white,
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: const BorderSide(color: Colores.primario, width: 2),
        shape: formaBoton,
        textStyle: letraBoton,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colores.primario,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        shape: formaBoton,
        // Subrayado: se reconoce como enlace sin depender del color.
        textStyle: letraBoton?.copyWith(decoration: TextDecoration.underline, decorationThickness: 1.5),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colores.primario,
        selectedBackgroundColor: Colores.primario,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: Colores.primario, width: 1.5),
        shape: formaBoton,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.primario : Colors.white),
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Colores.bordeControl),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.primario : Colores.bordeControl),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      // Tilde o cruz dentro de la perilla: el estado no depende solo del color.
      thumbIcon: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? const Icon(Icons.check, color: Colores.primario)
          : const Icon(Icons.close, color: Colors.white)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: Colores.primario,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          size: 24, color: s.contains(WidgetState.selected) ? Colors.white : Colores.tintaSecundaria)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colores.primario)
          : const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colores.tintaSecundaria)),
    ),
  );
}
