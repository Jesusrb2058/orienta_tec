import 'package:flutter/material.dart';
import 'package:orienta_tec/app/theme/tema_app.dart';
import 'package:orienta_tec/core/mapa_repositorio.dart';
import 'package:orienta_tec/main.dart' show OrientaTecApp;

/// Orienta-Tec-Administrador: la misma app, con las herramientas para dibujar
/// salones y rutas. Se ejecuta con:
///   flutter run -d chrome -t lib/main_admin.dart --dart-define=ORIENTA_TOKEN=...
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await controladorTema.cargar();
  await repositorioMapa.iniciar();
  runApp(const OrientaTecApp(admin: true));
}
