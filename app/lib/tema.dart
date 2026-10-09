/// Colores y tema de la app. Identidad sobria: azul río, tinta casi negra y
/// superficies blancas sobre un gris muy claro. El color fuerte se reserva para
/// el nivel del río. Todo plano y con bordes (las sombras no se ven al sol).
///
/// Hay dos paletas, clara y oscura. La app elige una ([Colores.oscuro]) antes
/// de dibujar y todos los colores salen de acá.
library;

import 'package:flutter/material.dart';

abstract final class Colores {
  /// true cuando la app está en modo oscuro. Lo fija la app al armar el tema.
  static bool oscuro = false;

  static Color _c(int claro, int enOscuro) => Color(oscuro ? enOscuro : claro);

  /// Color de marca para botones, enlaces, selección y la línea del gráfico.
  static Color get primario => _c(0xFF0B3C5D, 0xFF8CCBEE);

  /// Texto e íconos que van encima de [primario].
  static Color get sobrePrimario => _c(0xFFFFFFFF, 0xFF06283D);
  static Color get primarioSuave => _c(0xFFE3EEF6, 0xFF1D3446);
  static Color get fondo => _c(0xFFF4F6F8, 0xFF0E151B);

  /// Fondo de tarjetas y de la barra de navegación.
  static Color get superficie => _c(0xFFFFFFFF, 0xFF18222B);
  static Color get tinta => _c(0xFF111B24, 0xFFF1F5F8);
  static Color get tintaSecundaria => _c(0xFF44525E, 0xFFB4C0CB);
  static Color get bordeControl => _c(0xFF5B6770, 0xFF8A98A5);
  static Color get bordeSuave => _c(0xFFC3CDD6, 0xFF34424E);
  static Color get divisor => _c(0xFFDDE3E8, 0xFF2A3640);

  /// La barra superior es azul río en los dos modos, con texto blanco.
  static const barra = Color(0xFF0B3C5D);
  static const agua = Color(0xFF7CC4DE);
}

const _radio = BorderRadius.all(Radius.circular(12));

/// Arma el tema con la paleta que esté elegida en [Colores.oscuro].
ThemeData temaApp() {
  final esquema = ColorScheme(
    brightness: Colores.oscuro ? Brightness.dark : Brightness.light,
    primary: Colores.primario,
    onPrimary: Colores.sobrePrimario,
    secondary: Colores.primario,
    onSecondary: Colores.sobrePrimario,
    error: Colores.oscuro ? const Color(0xFFFF8A80) : const Color(0xFFB71C1C),
    onError: Colores.oscuro ? const Color(0xFF111B24) : Colors.white,
    surface: Colores.superficie,
    onSurface: Colores.tinta,
    onSurfaceVariant: Colores.tintaSecundaria,
    outline: Colores.bordeControl,
    outlineVariant: Colores.bordeSuave,
    secondaryContainer: Colores.primario,
    onSecondaryContainer: Colores.sobrePrimario,
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
      backgroundColor: Colores.barra,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colores.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: _radio, side: BorderSide(color: Colores.bordeSuave)),
    ),
    dividerTheme: DividerThemeData(color: Colores.divisor, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colores.tinta,
      contentTextStyle: TextStyle(color: Colores.fondo, fontSize: 16),
    ),
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
        backgroundColor: Colores.superficie,
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: Colores.primario, width: 2),
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
        backgroundColor: Colores.superficie,
        foregroundColor: Colores.primario,
        selectedBackgroundColor: Colores.primario,
        selectedForegroundColor: Colores.sobrePrimario,
        side: BorderSide(color: Colores.primario, width: 1.5),
        shape: formaBoton,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.primario : Colores.superficie),
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.sobrePrimario : Colores.bordeControl),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.primario : Colores.bordeControl),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      // Tilde o cruz dentro de la perilla: el estado no depende solo del color.
      thumbIcon: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? Icon(Icons.check, color: Colores.primario)
          : Icon(Icons.close, color: Colores.superficie)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colores.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: Colores.primario,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          size: 24, color: s.contains(WidgetState.selected) ? Colores.sobrePrimario : Colores.tintaSecundaria)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colores.primario)
          : TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colores.tintaSecundaria)),
    ),
  );
}
