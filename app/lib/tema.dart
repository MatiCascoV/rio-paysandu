/// Colores y tema de la app. Diseño liviano: fondo liso, muy pocas superficies
/// (rellenas, sin contorno) y separación con aire o una línea fina. El único
/// color fuerte de cada pantalla es el del nivel del río.
///
/// Hay dos paletas, clara y oscura. La app elige una ([Colores.oscuro]) antes
/// de dibujar y todos los colores salen de acá.
library;

import 'package:flutter/material.dart';

abstract final class Colores {
  /// true cuando la app está en modo oscuro. Lo fija la app al armar el tema.
  static bool oscuro = false;

  static Color _c(int claro, int enOscuro) => Color(oscuro ? enOscuro : claro);

  /// Color de marca: botones, enlaces, selección y la línea del gráfico.
  static Color get primario => _c(0xFF0B3C5D, 0xFF8CCBEE);

  /// Texto e íconos que van encima de [primario].
  static Color get sobrePrimario => _c(0xFFFFFFFF, 0xFF06283D);
  static Color get primarioSuave => _c(0xFFDCEAF4, 0xFF1D3446);

  /// Fondo de la pantalla y de las barras superior e inferior.
  static Color get fondo => _c(0xFFFFFFFF, 0xFF0E151B);

  /// Tarjeta rellena, sin contorno: apenas distinta del fondo.
  static Color get superficie => _c(0xFFEEF2F6, 0xFF1D2A36);

  /// Zona destacada dentro de una tarjeta (la fila "Ahora" de la escalera).
  static Color get superficieAlta => _c(0xFFFFFFFF, 0xFF2A3947);
  static Color get tinta => _c(0xFF111B24, 0xFFF1F5F8);
  static Color get tintaSecundaria => _c(0xFF44525E, 0xFFB4C0CB);
  static Color get bordeControl => _c(0xFF5B6770, 0xFF8A98A5);
  static Color get bordeSuave => _c(0xFFC3CDD6, 0xFF34424E);
  static Color get divisor => _c(0xFFDDE3E8, 0xFF2A3640);
}

const _radioBoton = BorderRadius.all(Radius.circular(12));
const radioSuperficie = BorderRadius.all(Radius.circular(20));

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
    surface: Colores.fondo,
    onSurface: Colores.tinta,
    onSurfaceVariant: Colores.tintaSecundaria,
    outline: Colores.bordeControl,
    outlineVariant: Colores.bordeSuave,
    secondaryContainer: Colores.primarioSuave,
    onSecondaryContainer: Colores.primario,
  );

  // Pocos escalones de letra y tres pesos (400, 600 y 800). Cuerpo de 18;
  // además se respeta el tamaño de letra que el usuario eligió en su teléfono.
  final base = Typography.material2021(colorScheme: esquema).black;
  final letras = base
      .copyWith(
        headlineMedium: base.headlineMedium?.copyWith(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800),
        titleLarge: base.titleLarge?.copyWith(fontSize: 22, height: 1.25, fontWeight: FontWeight.w600),
        titleMedium: base.titleMedium?.copyWith(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: 0),
        labelLarge: base.labelLarge?.copyWith(fontSize: 18, height: 1.2, fontWeight: FontWeight.w600),
        bodyLarge: base.bodyLarge?.copyWith(fontSize: 18, height: 1.4, letterSpacing: 0.1),
        bodyMedium: base.bodyMedium?.copyWith(fontSize: 16, height: 1.4, letterSpacing: 0.1),
      )
      .apply(bodyColor: Colores.tinta, displayColor: Colores.tinta);

  const formaBoton = RoundedRectangleBorder(borderRadius: _radioBoton);
  final letraBoton = letras.labelLarge;

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.fondo,
    textTheme: letras,
    appBarTheme: AppBarTheme(
      backgroundColor: Colores.fondo,
      foregroundColor: Colores.tinta,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: Colores.primario),
      actionsIconTheme: IconThemeData(color: Colores.primario),
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colores.tinta),
      shape: Border(bottom: BorderSide(color: Colores.divisor)),
    ),
    cardTheme: CardThemeData(
      color: Colores.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: radioSuperficie),
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
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: Colores.primario, width: 1.5),
        shape: formaBoton,
        textStyle: letraBoton,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colores.primario,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: formaBoton,
        // Subrayado: se reconoce como enlace sin depender del color.
        textStyle: letraBoton?.copyWith(decoration: TextDecoration.underline, decorationThickness: 1.5),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Colores.superficie,
        foregroundColor: Colores.tinta,
        selectedBackgroundColor: Colores.primario,
        selectedForegroundColor: Colores.sobrePrimario,
        side: BorderSide.none,
        shape: formaBoton,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.primario : Colores.fondo),
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.sobrePrimario : Colores.bordeControl),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colores.primario : Colores.bordeControl),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      // Tilde o cruz dentro de la perilla: el estado no depende solo del color.
      thumbIcon: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? Icon(Icons.check, color: Colores.primario)
          : Icon(Icons.close, color: Colores.fondo)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colores.fondo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: Colores.primarioSuave,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          size: 24, color: s.contains(WidgetState.selected) ? Colores.primario : Colores.tintaSecundaria)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colores.primario)
          : TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: Colores.tintaSecundaria)),
    ),
  );
}
