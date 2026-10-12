# orienta_tec

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# Ejecutar en mi celular 

flutter run -d RZCX41N7MEZ
flutter run -d linux
flutter run -d chrome

# Realizar pruevas de ejecucion 

flutter analyze


# Actualizar la web
flutter pub get
flutter build web --release

# Lanzar la web 
python3 -m http.server 8000 --directory build/web --bind 0.0.0.0


# Lanzar app de Administrador 
flutter run -d linux -t lib/main_admin.dart --dart-define=ORIENTA_TOKEN=lgkRfa27my9DXMXylPgcalgRXNP4X92rgarwkT6rW - Personal/orienta_tec_admin_cambios/orienta_tec$ 


# Modo administrador (Orienta-Tec-Administrador)

Es la misma app, pero con herramientas para dibujar los recuadros de los
salones y las rutas. Lo que se publica llega a Orienta-Tec sin reinstalarla.

## Configurar el servidor (una sola vez)
1. Crea un proyecto en https://console.firebase.google.com y activa **Realtime Database**.
2. Pega la URL de la base de datos en `lib/core/config_sync.dart` (`urlBaseDatos`, sin "/" al final).
3. Reglas sugeridas:
   `{ "rules": { "mapa": { ".read": true, ".write": "auth != null" } } }`
4. El token de escritura NO se guarda en el código: se pasa al ejecutar el administrador.

## Ejecutar
flutter pub get
flutter run -d chrome -t lib/main_admin.dart --dart-define=ORIENTA_TOKEN=tu_token

## Publicar el administrador como web
flutter build web --release -t lib/main_admin.dart --dart-define=ORIENTA_TOKEN=tu_token -o build/web_admin
python3 -m http.server 8001 --directory build/web_admin --bind 0.0.0.0

## Orienta-Tec (usuarios)
Sigue igual: `flutter run`, `flutter build web --release`. Al abrir, al volver a
primer plano y cada 30 s descarga la última versión publicada; guarda una copia
en el teléfono para usarla sin internet.

## Cómo se usa el administrador
- Editar: toca un salón o una ruta. Toca un punto para elegirlo y luego toca el
  mapa para moverlo; toca un círculo vacío para agregar un punto.
- Nuevo salón: dos toques (esquinas opuestas) o polígono libre. Se dibuja en la
  vista activa (mapa o satélite), así que puedes ajustar cada vista por separado.
- Nueva ruta: toca punto por punto. Si tocas cerca de otra ruta se conecta sola.
- Menú ⋮ > Revisar: avisa de rutas desconectadas o salones lejos de una ruta.
- Publicar: sube todo a la base de datos.
