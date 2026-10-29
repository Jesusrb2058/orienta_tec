# Antes de publicar la app (Android)

## 1. Nombre que se ve bajo el ícono
`android/app/src/main/AndroidManifest.xml`: cambia
`android:label="orienta_tec"` por `android:label="Orienta-Tec"`.

## 2. Firma del APK (importante)
Hoy el APK se firma con la llave de pruebas ("debug"). Para publicar conviene una llave propia.

OJO: Android solo actualiza una app si la nueva versión está firmada con la MISMA llave que la
instalada. Al cambiar de llave, quien ya la tenga instalada debe desinstalar e instalar de nuevo
una sola vez (la actualización dentro de la app fallará esa vez). Hazlo cuando haya pocos usuarios.

1. Crea la llave (guárdala en un lugar seguro y haz una copia; si la pierdes no podrás actualizar):
   `keytool -genkey -v -keystore ~/orienta-tec.jks -keyalg RSA -keysize 2048 -validity 10000 -alias orientatec`
2. Crea `android/key.properties` (NO lo subas a GitHub; agrégalo a .gitignore):
   ```
   storePassword=TU_CONTRASEÑA
   keyPassword=TU_CONTRASEÑA
   keyAlias=orientatec
   storeFile=/ruta/completa/orienta-tec.jks
   ```
3. En `android/app/build.gradle.kts` agrega arriba (antes de `android {`):
   ```kotlin
   import java.util.Properties
   import java.io.FileInputStream
   val keyProps = Properties().apply {
       val f = rootProject.file("key.properties")
       if (f.exists()) load(FileInputStream(f))
   }
   ```
   y dentro de `android { ... }`:
   ```kotlin
   signingConfigs {
       create("release") {
           keyAlias = keyProps["keyAlias"] as String?
           keyPassword = keyProps["keyPassword"] as String?
           storeFile = keyProps["storeFile"]?.let { file(it as String) }
           storePassword = keyProps["storePassword"] as String?
       }
   }
   ```
   y en `buildTypes { release { ... } }` cambia
   `signingConfig = signingConfigs.getByName("debug")` por
   `signingConfig = signingConfigs.getByName("release")`.

## 3. Nombre del paquete (com.example.orienta_tec)
Para Play Store hay que cambiarlo (por ejemplo `mx.edu.itorizaba.orientatec`), pero Android lo
trata como OTRA app: los usuarios actuales tendrían que instalar la nueva y desinstalar la vieja.
Si solo la repartes por APK/PWA, puedes dejarlo como está.
