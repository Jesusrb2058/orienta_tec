# Que los enlaces abran la app

## 1. pubspec.yaml  (dependencies:)
    qr_flutter: ^4.1.0
    app_links: ^6.4.0
Luego: `flutter pub get`

## 2. android/app/src/main/AndroidManifest.xml
Dentro de <activity android:name=".MainActivity" ...>, junto al intent-filter que ya existe, agrega:

    <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="orienta-tec-orizaba.web.app" />
    </intent-filter>

(y de paso: android:label="orienta_tec"  ->  android:label="Orienta-Tec")

## 3. Archivo que verifica el enlace
Copia `extra/web/.well-known/assetlinks.json` a  web/.well-known/assetlinks.json  de tu proyecto.
Contiene la huella (SHA-256) con la que está firmado tu APK actual. Si algún día cambias la llave
de firma, agrega aquí la huella nueva (puedes dejar las dos).

## 4. firebase.json  (dentro de "hosting")
Firebase ignora por defecto las carpetas que empiezan con punto. Cambia/agrega:

    "ignore": ["firebase.json", "**/node_modules/**", "**/.DS_Store"],
    "headers": [
      { "source": "/.well-known/assetlinks.json",
        "headers": [ { "key": "Content-Type", "value": "application/json" } ] }
      // ...deja también los headers que ya tengas (no-cache)
    ]

## 5. Compilar y desplegar
    flutter build web --release   y   npx firebase-tools deploy --only hosting
Comprueba que abre:  https://orienta-tec-orizaba.web.app/.well-known/assetlinks.json
Compila e instala el APK nuevo (sube la versión). Los enlaces verificados abren la app.

## Si en un teléfono no abre la app
Ajustes > Apps > Orienta-Tec > "Abrir de forma predeterminada" > Agregar enlaces > marca
orienta-tec-orizaba.web.app. (Pasa si Android no pudo verificar el enlace al instalar.)

## iPhone
Apple no permite que un enlace abra una PWA instalada: siempre se abre en Safari.
Alternativa incluida: en la PWA, pegar el enlace en el buscador ofrece "Abrir <salón>".
