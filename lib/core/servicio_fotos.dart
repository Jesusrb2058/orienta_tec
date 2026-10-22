import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:orienta_tec/core/config_sync.dart';

/// Fotos de los salones compartidas entre todos los dispositivos.
///
/// Cada salón tiene UNA foto en `fotos/<clave>` de la Realtime Database:
///   { "d": "<imagen en base64>", "t": <marca de tiempo del servidor> }
/// Quien sube una foto reemplaza la anterior y quien la borra la quita para
/// todos. Vive fuera de `mapa`, así que publicar el mapa NO borra las fotos.
/// No necesita token: las reglas del nodo `fotos` permiten leer y escribir.
const String nodoFotos = 'fotos';

/// Tamaño máximo de la imagen (bytes) antes de pasarla a base64.
const int maxBytesFoto = 600 * 1024;

class FotoRemota {
  const FotoRemota(this.bytes, this.marca);
  final Uint8List bytes;
  final int marca;
}

class ServicioFotos {
  /// Convierte la clave del salón ("Edificio|Número") en una llave válida
  /// para Firebase (sin . $ # [ ] / ni acentos).
  static String llave(String clave) =>
      clave.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

  static Uri _uri(String clave) =>
      Uri.parse('$urlBaseDatos/$nodoFotos/${llave(clave)}.json');

  static FotoRemota? _decodificar(String cuerpo) {
    final json = jsonDecode(cuerpo);
    if (json is! Map) return null;
    final d = json['d'];
    if (d is! String || d.isEmpty) return null;
    final t = json['t'];
    return FotoRemota(base64Decode(d), t is int ? t : 0);
  }

  /// Guarda (o reemplaza) la foto del salón para todos.
  static Future<void> guardar(String clave, Uint8List bytes) async {
    if (bytes.length > maxBytesFoto) {
      throw Exception('La foto pesa demasiado (${bytes.length ~/ 1024} KB).');
    }
    final r = await http
        .put(
          _uri(clave),
          body: jsonEncode({
            'd': base64Encode(bytes),
            't': {'.sv': 'timestamp'},
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) {
      throw Exception('El servidor respondió ${r.statusCode}. Revisa las reglas del nodo "fotos".');
    }
  }

  /// Quita la foto del salón para todos.
  static Future<void> borrar(String clave) async {
    final r = await http.delete(_uri(clave)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('El servidor respondió ${r.statusCode}. Revisa las reglas del nodo "fotos".');
    }
  }

  /// Emite la foto actual (o null si no hay) al empezar a escuchar y cada vez
  /// que otro dispositivo la cambia o la borra. Consulta cada pocos segundos
  /// con ETag, así que cuando nada cambió casi no gasta datos.
  static Stream<FotoRemota?> observar(
    String clave, {
    Duration cada = const Duration(seconds: 4),
  }) {
    late final StreamController<FotoRemota?> c;
    Timer? timer;
    String? etag;
    var ocupado = false;
    var vivo = true;

    Future<void> consultar() async {
      if (ocupado || !vivo) return;
      ocupado = true;
      try {
        final r = await http.get(_uri(clave), headers: {
          'X-Firebase-ETag': 'true',
          if (etag != null) 'if-none-match': etag!,
        }).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200 && vivo && !c.isClosed) {
          etag = r.headers['etag'];
          c.add(_decodificar(r.body));
        }
        // 304: no cambió nada.
      } catch (_) {
        // Sin red: se reintenta en el siguiente ciclo.
      } finally {
        ocupado = false;
      }
    }

    c = StreamController<FotoRemota?>(
      onListen: () {
        consultar();
        timer = Timer.periodic(cada, (_) => consultar());
      },
      onCancel: () {
        vivo = false;
        timer?.cancel();
      },
    );
    return c.stream;
  }
}
