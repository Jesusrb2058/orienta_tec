import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'config_sync.dart';

class ServicioActualizacion {
  /// Consulta Firebase y muestra la alerta si hay una versión superior
  static Future<void> verificarActualizacion(BuildContext context) async {
    try {
      // 1. Leer número de versión (build number) instalada localmente
      final packageInfo = await PackageInfo.fromPlatform();
      final int versionCodeLocal = int.tryParse(packageInfo.buildNumber) ?? 1;

      // Imprimir la versión local detectada para depurar
      print('=== ACTUALIZACION: versionCodeLocal detectado -> $versionCodeLocal ===');

      // 2. Consultar el nodo version_app en Firebase con token de autenticación
      final url = Uri.parse('$urlBaseDatos/version_app.json?auth=lgkRfa27my9DXMXylPgcalgRXNP4X92rgarwkT6r');
      final respuesta = await http.get(url);

      print('=== ACTUALIZACION: Status Code -> ${respuesta.statusCode} ===');
      print('=== ACTUALIZACION: Body -> ${respuesta.body} ===');

      if (respuesta.statusCode == 200 && respuesta.body != 'null') {
        final Map<String, dynamic> datos = json.decode(respuesta.body);
        final int versionCodeRemoto = datos['version_code'] ?? 1;
        final String urlApk = datos['url_apk'] ?? '';
        final String novedades = datos['novedades'] ?? 'Mejoras y correcciones generales.';
        final String versionName = datos['version_name'] ?? '1.0.0';

        print('=== ACTUALIZACION: Remote Version -> $versionCodeRemoto, Local Version -> $versionCodeLocal ===');

        // 3. Si la versión remota es mayor, desplegar la ventana emergente
        if (versionCodeRemoto > versionCodeLocal && urlApk.isNotEmpty) {
          if (!context.mounted) return;
          _mostrarDialogoActualizacion(context, versionName, novedades, urlApk);
        } else {
          print('=== ACTUALIZACION: La versión remota no es mayor que la local. No se muestra diálogo. ===');
        }
      }
    } catch (e) {
      print('=== ACTUALIZACION ERROR: $e ===');
    }
  }

  /// Despliega el AlertDialog modal
  static void _mostrarDialogoActualizacion(
      BuildContext context, String versionName, String novedades, String urlApk) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        bool descargando = false;
        String progreso = '0%';

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.system_update, color: Colors.blue),
                  const SizedBox(width: 10),
                  Text('Nueva versión v$versionName'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Hay una nueva versión disponible de Orienta-Tec:'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      novedades,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (descargando) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(value: _obtenerProgresoDecimal(progreso)),
                    const SizedBox(height: 8),
                    Center(child: Text('Descargando e instalando... $progreso')),
                  ],
                ],
              ),
              actions: [
                if (!descargando) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Más tarde'),
                  ),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        descargando = true;
                      });
                      _iniciarDescarga(urlApk, (nuevoProgreso) {
                        setState(() {
                          progreso = nuevoProgreso;
                        });
                      });
                    },
                    child: const Text('Actualizar ahora'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  static double _obtenerProgresoDecimal(String progreso) {
    final valor = double.tryParse(progreso.replaceAll('%', '')) ?? 0.0;
    return valor / 100;
  }

  static void _iniciarDescarga(String urlApk, Function(String) onProgreso) {
    try {
      OtaUpdate().execute(urlApk, destinationFilename: 'orienta_tec_update.apk').listen(
        (OtaEvent event) {
          if (event.status == OtaStatus.DOWNLOADING) {
            onProgreso('${event.value}%');
          } else if (event.status == OtaStatus.INSTALLING) {
            onProgreso('Instalando...');
          } else if (event.status == OtaStatus.ALREADY_RUNNING_ERROR) {
            debugPrint('Ya hay una descarga en proceso');
          } else if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
            debugPrint('Permisos insuficientes para instalar el APK');
          }
        },
      );
    } catch (e) {
      debugPrint('Error durante la descarga del APK: $e');
    }
  }
}