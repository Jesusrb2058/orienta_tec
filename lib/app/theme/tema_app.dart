import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla el modo de apariencia (automático, claro u oscuro) y lo recuerda
/// aunque se cierre la app.
class ControladorTema extends ValueNotifier<ThemeMode> {
  ControladorTema() : super(ThemeMode.system);

  static const String _clave = 'modo_tema';

  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = switch (prefs.getString(_clave)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      value = ThemeMode.system;
    }
  }

  Future<void> cambiar(ThemeMode modo) async {
    value = modo;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _clave,
        switch (modo) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
    } catch (_) {
      // Si no se puede guardar, el cambio igual funciona en esta sesión.
    }
  }
}

/// Instancia única que usa toda la app.
final ControladorTema controladorTema = ControladorTema();

const Color _azulMarca = Color(0xFF1B396A);

ThemeData temaClaro() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: _azulMarca),
      scaffoldBackgroundColor: const Color(0xFFF1F4F8),
    );

ThemeData temaOscuro() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _azulMarca,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF11151C),
    );

/// Colores de la interfaz de Orienta-TEC para el modo claro y el oscuro.
class Paleta {
  const Paleta._(this.oscuro);

  final bool oscuro;

  static Paleta of(BuildContext context) =>
      Paleta._(Theme.of(context).brightness == Brightness.dark);

  /// Fondo general.
  Color get fondo => oscuro ? const Color(0xFF11151C) : const Color(0xFFF1F4F8);

  /// Tarjetas, buscador y botones flotantes.
  Color get superficie => oscuro ? const Color(0xFF1E232D) : Colors.white;

  /// Fondo de chips y recuadros suaves.
  Color get chip => oscuro ? const Color(0xFF2B3342) : const Color(0xFFF1F4F8);

  /// Texto principal.
  Color get texto => oscuro ? const Color(0xFFE8EAED) : const Color(0xDD000000);

  /// Texto secundario.
  Color get textoSec => oscuro ? const Color(0xFF9AA0A6) : const Color(0xFF5F6368);

  /// Textos e íconos de marca.
  Color get acento => oscuro ? const Color(0xFF8AB4F8) : _azulMarca;

  /// Botones rellenos e insignias de marca.
  Color get primario => oscuro ? const Color(0xFF4F83E0) : _azulMarca;

  /// Banner de navegación.
  Color get banner => oscuro ? const Color(0xFF254A8F) : _azulMarca;

  /// Color de los salones dibujados sobre el mapa.
  Color get mapa => oscuro ? const Color(0xFF8AB4F8) : _azulMarca;

  Color get verde => oscuro ? const Color(0xFF81C995) : const Color(0xFF2E9E6B);

  /// Líneas divisorias y fondo de barras de progreso.
  Color get divisor => oscuro ? const Color(0xFF3A4150) : const Color(0xFFE0E3E7);
}
