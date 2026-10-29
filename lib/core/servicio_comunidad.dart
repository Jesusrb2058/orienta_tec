import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:orienta_tec/core/config_sync.dart';
import 'package:orienta_tec/core/servicio_fotos.dart' show ServicioFotos;

/// Comentarios de los usuarios y conteo anónimo de salones consultados.
///
/// - `comentarios`: cada reporte se guarda con POST (solo se pueden crear, no
///   leer ni borrar sin la llave de administrador).
/// - `estadisticas/<salón>`: cuántas veces se consultó cada salón. No guarda
///   quién lo consultó.
class ServicioComunidad {
  static Uri _uri(String ruta) => Uri.parse('$urlBaseDatos/$ruta.json');

  /// Suma 1 a las consultas de un salón. Falla en silencio (sin red, etc.).
  static Future<void> contarConsulta(String clave, String nombre) async {
    try {
      final llave = ServicioFotos.llave(clave);
      final actual = await http.get(_uri('estadisticas/$llave/n')).timeout(const Duration(seconds: 10));
      final n = actual.statusCode == 200 ? (int.tryParse(actual.body.trim()) ?? 0) : 0;
      await http
          .patch(
            _uri('estadisticas/$llave'),
            body: jsonEncode({'n': n + 1, 'nombre': nombre.length > 100 ? nombre.substring(0, 100) : nombre}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Envía un comentario sobre un salón o sobre la app. Lanza si no se pudo.
  static Future<void> enviarComentario({required String texto, String salon = ''}) async {
    final t = texto.trim();
    if (t.isEmpty) throw Exception('Escribe tu comentario.');
    final r = await http
        .post(
          _uri('comentarios'),
          body: jsonEncode({
            'texto': t.length > 450 ? t.substring(0, 450) : t,
            'salon': salon,
            't': {'.sv': 'timestamp'},
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('No se pudo enviar (${r.statusCode}).');
    }
  }
}
