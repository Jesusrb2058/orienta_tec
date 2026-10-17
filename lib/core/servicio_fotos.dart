import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ServicioFotos {
  final ImagePicker _picker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // 1. Seleccionar foto (Cámara o Galería)
  Future<File?> seleccionarFoto(ImageSource origen) async {
    final XFile? imagen = await _picker.pickImage(
      source: origen,
      imageQuality: 70, // Optimiza el tamaño de la foto antes de subir
    );
    if (imagen != null) {
      return File(imagen.path);
    }
    return null;
  }

  // 2. Subir imagen a Firebase Storage y vincular URL en Realtime Database
  Future<String?> subirFotoSalon({
    required File archivoFoto,
    required String idSalon,
    required List<String> fotosActuales,
  }) async {
    try {
      // Definir la ruta en Firebase Storage
      String nombreArchivo = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = _storage.ref().child('salones/$idSalon/$nombreArchivo');

      // Subir archivo
      UploadTask uploadTask = ref.putFile(archivoFoto);
      TaskSnapshot snapshot = await uploadTask;

      // Obtener la URL pública de la imagen guardada
      String urlDescarga = await snapshot.ref.getDownloadURL();

      // Guardar la nueva URL en el arreglo "fotos" del salón en Realtime Database
      List<String> fotosActualizadas = [...fotosActuales, urlDescarga];

      final urlDatabase = Uri.parse(
        "https://orienta-tec-administrador-default-rtdb.firebaseio.com/mapa/salones/$idSalon/fotos.json?auth=lgkRfa27my9DXMXylPgcalgRXNP4X92rgarwkT6r"
      );

      await http.put(
        urlDatabase,
        body: jsonEncode(fotosActualizadas),
      );

      return urlDescarga;
    } catch (e) {
      print("Error al subir la foto: $e");
      return null;
    }
  }
}