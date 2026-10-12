import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'config_sync.dart';

/// Revisa en Firebase si hay una versión nueva y, si el usuario acepta,
/// descarga el APK y abre el instalador de Android.
///
/// El nodo `version_app` de la base de datos debe tener:
///   version_code → número entero, mayor que el "build number" instalado
///                  (el número después del + en pubspec.yaml: 1.0.1+2 → 2)
///   version_name → texto, por ejemplo "1.0.1"
///   url_apk      → enlace directo (https) al archivo .apk
///   novedades    → texto con lo que cambió
///
/// Ese nodo se lee SIN token: en las reglas de Firebase debe tener
/// ".read": true. Nunca pongas el secreto de la base de datos en la app.
class ServicioActualizacion {
  static bool _mostrando = false;

  static Future<void> verificarActualizacion(BuildContext context) async {
    // El APK solo se puede instalar en Android (en web o escritorio no aplica).
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_mostrando) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final local = int.tryParse(info.buildNumber) ?? 1;

      final r = await http
          .get(Uri.parse('$urlBaseDatos/version_app.json'))
          .timeout(const Duration(seconds: 10));
      debugPrint('ACTUALIZACION: local=$local, status=${r.statusCode}');
      if (r.statusCode != 200 || r.body == 'null') return;

      final datos = json.decode(r.body);
      if (datos is! Map) return;
      final remoto = int.tryParse('${datos['version_code']}') ?? 0;
      final urlApk = '${datos['url_apk'] ?? ''}'.trim();
      final nombre = '${datos['version_name'] ?? ''}'.trim();
      var novedades = '${datos['novedades'] ?? ''}'.trim();
      if (novedades.isEmpty) novedades = 'Mejoras y correcciones generales.';
      debugPrint('ACTUALIZACION: remoto=$remoto');

      if (remoto <= local || urlApk.isEmpty) return;
      if (!context.mounted) return;

      _mostrando = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DialogoActualizacion(
          versionName: nombre,
          novedades: novedades,
          urlApk: urlApk,
        ),
      );
    } catch (e) {
      debugPrint('ACTUALIZACION ERROR: $e');
    } finally {
      _mostrando = false;
    }
  }
}

enum _Fase { listo, descargando, instalando, error }

class _DialogoActualizacion extends StatefulWidget {
  const _DialogoActualizacion({
    required this.versionName,
    required this.novedades,
    required this.urlApk,
  });

  final String versionName;
  final String novedades;
  final String urlApk;

  @override
  State<_DialogoActualizacion> createState() => _DialogoActualizacionState();
}

class _DialogoActualizacionState extends State<_DialogoActualizacion> {
  _Fase _fase = _Fase.listo;
  double _progreso = 0;
  String _mensaje = '';
  StreamSubscription<OtaEvent>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _fallar(String mensaje) {
    if (!mounted) return;
    setState(() {
      _fase = _Fase.error;
      _mensaje = mensaje;
    });
  }

  void _iniciar() {
    setState(() {
      _fase = _Fase.descargando;
      _progreso = 0;
      _mensaje = '';
    });
    _sub?.cancel();
    try {
      _sub = OtaUpdate()
          .execute(widget.urlApk, destinationFilename: 'orienta_tec_update.apk')
          .listen(
            _alEvento,
            onError: (Object e) => _fallar('No se pudo actualizar: $e'),
          );
    } catch (e) {
      _fallar('No se pudo iniciar la descarga: $e');
    }
  }

  void _alEvento(OtaEvent evento) {
    if (!mounted) return;
    final estado = evento.status;
    final valor = evento.value ?? '';
    if (estado == OtaStatus.DOWNLOADING) {
      final pct = double.tryParse(valor) ?? 0;
      setState(() {
        _fase = _Fase.descargando;
        _progreso = (pct / 100).clamp(0.0, 1.0).toDouble();
      });
    } else if (estado == OtaStatus.INSTALLING || estado == OtaStatus.INSTALLATION_DONE) {
      setState(() => _fase = _Fase.instalando);
    } else if (estado == OtaStatus.ALREADY_RUNNING_ERROR) {
      _fallar('Ya hay una descarga en curso. Espera un momento e inténtalo de nuevo.');
    } else if (estado == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
      _fallar('Falta un permiso para instalar. Actívalo en Ajustes → Apps → Orienta-Tec → '
          '«Instalar apps desconocidas» y vuelve a intentarlo.');
    } else if (estado == OtaStatus.DOWNLOAD_ERROR) {
      _fallar('No se pudo descargar la actualización. Revisa tu conexión a internet. $valor');
    } else if (estado == OtaStatus.INSTALLATION_ERROR) {
      _fallar('Android no pudo instalar la actualización. $valor');
    } else if (estado == OtaStatus.CANCELED) {
      _fallar('La descarga se canceló.');
    } else {
      _fallar('Error al actualizar. $valor');
    }
  }

  Future<void> _cancelar() async {
    _sub?.cancel();
    try {
      await OtaUpdate().cancel();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.versionName.isEmpty ? 'Nueva versión' : 'Nueva versión v${widget.versionName}';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.blue),
          const SizedBox(width: 10),
          Expanded(child: Text(titulo)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hay una nueva versión disponible de Orienta-Tec:'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.novedades, style: const TextStyle(fontSize: 13)),
            ),
            if (_fase == _Fase.descargando) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _progreso > 0 ? _progreso : null),
              const SizedBox(height: 8),
              Center(child: Text('Descargando… ${(_progreso * 100).round()}%')),
            ],
            if (_fase == _Fase.instalando) ...[
              const SizedBox(height: 20),
              const Text(
                'Descarga lista. Android te pedirá confirmar la instalación; acepta para terminar. '
                'Si te pide permiso para «instalar apps desconocidas», actívalo y vuelve a pulsar Actualizar.',
                style: TextStyle(fontSize: 13),
              ),
            ],
            if (_fase == _Fase.error) ...[
              const SizedBox(height: 16),
              Text(_mensaje, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (_fase == _Fase.descargando)
          TextButton(onPressed: _cancelar, child: const Text('Cancelar'))
        else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_fase == _Fase.listo ? 'Más tarde' : 'Cerrar'),
          ),
          if (_fase != _Fase.instalando)
            FilledButton(
              onPressed: _iniciar,
              child: Text(_fase == _Fase.error ? 'Reintentar' : 'Actualizar ahora'),
            ),
        ],
      ],
    );
  }
}