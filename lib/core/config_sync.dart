// Configuración de la sincronización entre Orienta-Tec-Administrador y Orienta-Tec.
//
// Los datos del mapa (salones y rutas) se guardan como un JSON en una
// Realtime Database de Firebase, usando solo su API REST (no hace falta
// instalar el SDK de Firebase ni agregar google-services.json).
//
// 1) Crea un proyecto en https://console.firebase.google.com y activa
//    "Realtime Database".
// 2) Pega aquí la URL de la base de datos, SIN "/" al final.
//    Ejemplo: 'https://orienta-tec-default-rtdb.firebaseio.com'
// 3) Reglas sugeridas (Realtime Database > Reglas):
//      { "rules": { "mapa": { ".read": true, ".write": "auth != null" } } }
//    y usa un token en el administrador (ver README, sección "Modo administrador").
//
// Con la URL vacía, ambas apps funcionan solo con los datos que traen
// dentro y el administrador no puede publicar.
const String urlBaseDatos = 'https://orienta-tec-administrador-default-rtdb.firebaseio.com';

/// Nombre del nodo donde se guarda el mapa.
const String nodoMapa = 'mapa';

/// Token de escritura. NO lo escribas aquí: se pasa solo al compilar el
/// administrador con --dart-define=ORIENTA_TOKEN=...
const String tokenAdmin = String.fromEnvironment('ORIENTA_TOKEN');