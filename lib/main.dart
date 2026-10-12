import 'package:flutter/material.dart';
import 'package:orienta_tec/app/theme/tema_app.dart';
import 'package:orienta_tec/core/mapa_repositorio.dart';
import 'features/home/presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lee el modo de apariencia guardado antes de mostrar la primera pantalla,
  // para que no parpadee entre claro y oscuro.
  await controladorTema.cargar();
  // Carga los salones y rutas (copia guardada + versión publicada).
  await repositorioMapa.iniciar();
  runApp(const OrientaTecApp());
}

class OrientaTecApp extends StatelessWidget {
  const OrientaTecApp({super.key, this.admin = false});

  /// true = Orienta-Tec-Administrador (se abre desde lib/main_admin.dart).
  final bool admin;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controladorTema,
      builder: (context, modo, _) => MaterialApp(
        title: admin ? 'OrientaTec Administrador' : 'OrientaTec',
        debugShowCheckedModeBanner: false,
        theme: temaClaro(),
        darkTheme: temaOscuro(),
        // ThemeMode.system sigue el modo del teléfono automáticamente.
        themeMode: modo,
        home: HomeScreen(admin: admin),
      ),
    );
  }
}
