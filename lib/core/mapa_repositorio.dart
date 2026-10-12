import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config_sync.dart';
import 'mapa_datos.dart';

/// Fuente única de los salones y rutas que usa la app.
///
/// Orden de prioridad al abrir: copia guardada en el teléfono (para que
/// funcione sin internet) y luego la versión publicada en el servidor.
/// Quien escuche este objeto se entera apenas llegan datos nuevos.
class MapaRepositorio extends ValueNotifier<DatosMapa> {
  MapaRepositorio() : super(DatosMapa.porDefecto());

  static const String _claveCache = 'mapa_datos_cache';

  bool get remotoConfigurado => urlBaseDatos.isNotEmpty;

  Uri _uri({required bool conToken}) {
    final base = Uri.parse('$urlBaseDatos/$nodoMapa.json');
    if (conToken && tokenAdmin.isNotEmpty) {
      return base.replace(queryParameters: {'auth': tokenAdmin});
    }
    return base;
  }

  /// Se llama una vez antes de mostrar la primera pantalla.
  Future<void> iniciar() async {
    await _leerCache();
    if (remotoConfigurado) {
      // No dejamos la pantalla de inicio esperando más de 4 s.
      await sincronizar().timeout(const Duration(seconds: 4), onTimeout: () => false);
    }
  }

  Future<void> _leerCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_claveCache);
      if (texto == null) return;
      final json = jsonDecode(texto);
      if (json is Map<String, dynamic>) {
        final datos = DatosMapa.fromJson(json);
        if (datos.salones.isNotEmpty) value = datos;
      }
    } catch (_) {
      // Si la copia está dañada se queda con los datos que trae la app.
    }
  }

  Future<void> _guardarCache(DatosMapa datos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_claveCache, jsonEncode(datos.toJson()));
    } catch (_) {}
  }

  /// Descarga la versión publicada. Devuelve true si había cambios nuevos.
  Future<bool> sincronizar() async {
    if (!remotoConfigurado) return false;
    try {
      final r = await http.get(_uri(conToken: false)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return false;
      final cuerpo = jsonDecode(r.body);
      // "null" = el administrador todavía no ha publicado nada.
      if (cuerpo is! Map<String, dynamic>) return false;
      final datos = DatosMapa.fromJson(cuerpo);
      if (datos.salones.isEmpty || datos.version == value.version) return false;
      value = datos;
      await _guardarCache(datos);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sube los datos al servidor y los deja como versión actual.
  /// Lanza una excepción con el motivo si no se pudo.
  Future<void> publicar(DatosMapa datos) async {
    if (!remotoConfigurado) {
      throw StateError('Falta configurar urlBaseDatos en lib/core/config_sync.dart');
    }
    final nuevo = datos.copyWith(version: DateTime.now().millisecondsSinceEpoch);
    final r = await http
        .put(
          _uri(conToken: true),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(nuevo.toJson()),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw StateError('El servidor respondió ${r.statusCode}. Revisa las reglas de la base de datos y el token.');
    }
    value = nuevo;
    await _guardarCache(nuevo);
  }
}

final MapaRepositorio repositorioMapa = MapaRepositorio();
