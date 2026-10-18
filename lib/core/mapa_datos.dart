import 'dart:convert';
import 'dart:ui' show Offset, Rect;

// ---------------------------------------------------------------------------
// Geometría compartida (coordenadas en píxeles del plano del campus)
// ---------------------------------------------------------------------------

/// Los contornos para el mapa base se ajustaron a los edificios de OpenStreetMap,
/// que van alineados con las calles. El plano está girado ~2° respecto a esa
/// rejilla, así que estas dos funciones convierten entre ambos.
Offset rejillaAPlano(Offset q) => Offset(
      0.9697495 * q.dx + -0.0247293 * q.dy + 13.99984,
      0.0390917 * q.dx + 1.083182 * q.dy + -54.26656,
    );

Offset planoARejilla(Offset p) => Offset(
      1.030246 * p.dx + 0.0235208 * p.dy + -13.14689,
      -0.0371812 * p.dx + 0.9223571 * p.dy + 50.57368,
    );

/// Redondea a 2 decimales. Las rutas se conectan por coordenadas idénticas,
/// así que todo punto nuevo se redondea para que sobreviva intacto al JSON.
double _r(double v) => (v * 100).round() / 100;
Offset redondear(Offset o) => Offset(_r(o.dx), _r(o.dy));

Offset proyectarEnSegmento(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return a;
  final t = ((((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2).clamp(0.0, 1.0)).toDouble();
  return a + ab * t;
}

double distanciaASegmento(Offset p, Offset a, Offset b) => (p - proyectarEnSegmento(p, a, b)).distance;

bool puntoEnPoligono(Offset p, List<Offset> poly) {
  var dentro = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i];
    final b = poly[j];
    final cruza = (a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx;
    if (cruza) dentro = !dentro;
  }
  return dentro;
}

bool puntoCercaDePoligono(Offset p, List<Offset> poly, {double tolerancia = 4}) {
  if (poly.length < 3) return false;
  if (puntoEnPoligono(p, poly)) return true;
  for (var i = 0; i < poly.length; i++) {
    if (distanciaASegmento(p, poly[i], poly[(i + 1) % poly.length]) <= tolerancia) return true;
  }
  return false;
}

Rect limitesDe(List<Offset> pts) {
  if (pts.isEmpty) return Rect.zero;
  var minX = pts.first.dx, maxX = pts.first.dx, minY = pts.first.dy, maxY = pts.first.dy;
  for (final p in pts) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

List<Offset> _rectAPoligono(Rect r) => [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];

List<List<double>> _ptsAJson(List<Offset> pts) => [for (final p in pts) [p.dx, p.dy]];

List<Offset> _ptsDeJson(Object? v) {
  if (v is! List) return const <Offset>[];
  final out = <Offset>[];
  for (final e in v) {
    if (e is List && e.length >= 2) {
      out.add(Offset((e[0] as num).toDouble(), (e[1] as num).toDouble()));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Salón
// ---------------------------------------------------------------------------
class Salon {
  const Salon({
    required this.numero,
    required this.edificio,
    required this.piso,
    this.tipo = 'Aula',
    this.descripcion = '',
    this.columna = -1,
    this.indicaciones = const <String>[],
    this.poligonoImagen = const <Offset>[],
    this.poligonoMapa = const <Offset>[],
  });

  /// Nombre o número del salón ("205", "L03", "Room 1", "Baños").
  final String numero;

  /// Nombre del bloque (edificio) al que pertenece.
  final String edificio;
  final int piso;
  final String tipo;
  final String descripcion;

  /// Columna dentro del bloque (0, 1, 2…). -1 = sin asignar: se reparten por piso.
  final int columna;

  /// "Cómo llegar" escrito por el administrador, una indicación por elemento.
  /// Vacío = la app genera las indicaciones sola a partir de la ruta.
  final List<String> indicaciones;

  /// Identificador único: el mismo nombre puede repetirse en otro bloque.
  String get clave => '$edificio|$numero';

  /// Contorno sobre la imagen del campus (vista satélite), en px del plano.
  final List<Offset> poligonoImagen;

  /// Contorno sobre el mapa base (OpenStreetMap), en px del plano.
  final List<Offset> poligonoMapa;

  bool get tieneImagen => poligonoImagen.length >= 3;
  bool get tieneMapa => poligonoMapa.length >= 3;

  /// Si falta el contorno de una vista se usa el de la otra.
  List<Offset> get esquinasImagen => tieneImagen ? poligonoImagen : poligonoMapa;
  List<Offset> get esquinasMapa => tieneMapa ? poligonoMapa : poligonoImagen;

  /// Rectángulo que envuelve al salón; las rutas se calculan hacia él.
  Rect get area => limitesDe(esquinasImagen);
  Offset get centro => area.center;
  Offset get centroMapa => limitesDe(esquinasMapa).center;

  String get nombre => 'Salón $numero';
  String get ubicacion => '$edificio, piso $piso';
  String get foto => 'assets/images/salones/$numero.jpg';

  String get detalle => descripcion.isEmpty
      ? '$tipo ubicada en el $edificio, en el piso $piso.'
      : descripcion;

  Salon copyWith({
    String? numero,
    String? edificio,
    int? piso,
    String? tipo,
    String? descripcion,
    int? columna,
    List<String>? indicaciones,
    List<Offset>? poligonoImagen,
    List<Offset>? poligonoMapa,
  }) =>
      Salon(
        numero: numero ?? this.numero,
        edificio: edificio ?? this.edificio,
        piso: piso ?? this.piso,
        tipo: tipo ?? this.tipo,
        descripcion: descripcion ?? this.descripcion,
        columna: columna ?? this.columna,
        indicaciones: indicaciones ?? this.indicaciones,
        poligonoImagen: poligonoImagen ?? this.poligonoImagen,
        poligonoMapa: poligonoMapa ?? this.poligonoMapa,
      );

  Map<String, dynamic> toJson() => {
        'numero': numero,
        'edificio': edificio,
        'piso': piso,
        'tipo': tipo,
        'descripcion': descripcion,
        'columna': columna,
        'indicaciones': indicaciones,
        'imagen': _ptsAJson(poligonoImagen),
        'mapa': _ptsAJson(poligonoMapa),
      };

  factory Salon.fromJson(Map<String, dynamic> j) => Salon(
        numero: '${j['numero']}',
        edificio: '${j['edificio'] ?? ''}',
        piso: (j['piso'] as num?)?.toInt() ?? 1,
        tipo: '${j['tipo'] ?? 'Aula'}',
        descripcion: '${j['descripcion'] ?? ''}',
        columna: (j['columna'] as num?)?.toInt() ?? -1,
        indicaciones: _textos(j['indicaciones']),
        poligonoImagen: _ptsDeJson(j['imagen']),
        poligonoMapa: _ptsDeJson(j['mapa']),
      );

  // Dos salones son el mismo si tienen el mismo bloque y el mismo nombre.
  @override
  bool operator ==(Object other) => other is Salon && other.clave == clave;

  @override
  int get hashCode => clave.hashCode;
}

// ---------------------------------------------------------------------------
// Texto y bloques
// ---------------------------------------------------------------------------
List<String> _textos(Object? v) {
  final items = v is Map ? v.values : (v is List ? v : const []);
  return [
    for (final e in items)
      if ('$e'.trim().isNotEmpty) '$e'.trim(),
  ];
}

String sinAcentos(String s) {
  const de = 'áàäâéèëêíìïîóòöôúùüûñ';
  const a = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? a[i] : c);
  }
  return b.toString();
}

/// Convierte "101-106, E01 al E03, Baños" en la lista de salones. Los rangos
/// pueden llevar letras ("E01-E03", "A61 al 64") y conservan los ceros.
/// Se separa por comas, punto y coma o renglones; no repite nombres.
List<String> expandirSalones(String texto) {
  final out = <String>[];
  final vistos = <String>{};
  void agregar(String s) {
    final t = s.trim();
    if (t.isNotEmpty && vistos.add(t.toLowerCase())) out.add(t);
  }

  final rango = RegExp(r'^([A-Za-z]*)(\d+)\s*(?:-|–|—|al|a)\s*([A-Za-z]*)(\d+)$', caseSensitive: false);
  for (final trozo in texto.split(RegExp(r'[,;\n]+'))) {
    final t = trozo.trim();
    if (t.isEmpty) continue;
    final m = rango.firstMatch(t);
    if (m != null) {
      final pre = m.group(1)!;
      final pre2 = m.group(3)!;
      if (pre2.isEmpty || pre2.toLowerCase() == pre.toLowerCase()) {
        final ini = m.group(2)!;
        var a = int.parse(ini);
        var b = int.parse(m.group(4)!);
        if (b < a) {
          final x = a;
          a = b;
          b = x;
        }
        if (b - a <= 200) {
          final ancho = ini.startsWith('0') ? ini.length : 0;
          for (var i = a; i <= b; i++) {
            agregar('$pre${i.toString().padLeft(ancho, '0')}');
          }
          continue;
        }
      }
    }
    agregar(t);
  }
  return out;
}

/// Tipo que se propone al crear un salón según su nombre (se puede cambiar).
String tipoSugerido(String nombre) {
  final n = sinAcentos(nombre.trim());
  if (n.startsWith('oficina')) return 'Oficina';
  if (n.contains('bano')) return 'Baños';
  if (n.contains('enfermeria')) return 'Enfermería';
  if (n.contains('consultorio')) return 'Consultorio';
  if (n.contains('aula magna')) return 'Auditorio';
  if (n.contains('objetos perdidos')) return 'Servicio';
  if (n.contains('escalera')) return 'Escaleras';
  if (n.contains('laboratorio') || RegExp(r'^lab\b').hasMatch(n) || RegExp(r'^l\d').hasMatch(n)) {
    return 'Laboratorio';
  }
  return 'Aula';
}

/// Salones de un bloque agrupados en columnas, de izquierda a derecha.
/// Con columnas asignadas se respetan; si no, hay una columna por piso.
List<List<Salon>> columnasDeBloque(List<Salon> lista) {
  if (lista.any((s) => s.columna >= 0)) {
    final claves = {for (final s in lista) s.columna}.toList()
      ..sort((a, b) => (a < 0 ? 1 << 30 : a).compareTo(b < 0 ? 1 << 30 : b));
    return [
      for (final k in claves) [for (final s in lista) if (s.columna == k) s],
    ];
  }
  final pisos = {for (final s in lista) s.piso}.toList()..sort();
  return [
    for (final p in pisos) [for (final s in lista) if (s.piso == p) s],
  ];
}

/// Contorno del bloque: el más grande entre sus salones. Con [propio] solo
/// cuenta el que se dibujó en esa vista (sin tomar prestado el de la otra).
List<Offset> contornoDeBloque(List<Salon> lista, bool imagen, {bool propio = false}) {
  var mejor = const <Offset>[];
  var area = -1.0;
  for (final s in lista) {
    final pts = propio
        ? (imagen ? s.poligonoImagen : s.poligonoMapa)
        : (imagen ? s.esquinasImagen : s.esquinasMapa);
    if (pts.length < 3) continue;
    final r = limitesDe(pts);
    final a = r.width * r.height;
    if (a > area) {
      area = a;
      mejor = pts;
    }
  }
  return mejor;
}

// ---------------------------------------------------------------------------
// Datos completos del mapa (lo que publica el administrador)
// ---------------------------------------------------------------------------
class DatosMapa {
  const DatosMapa({
    required this.version,
    required this.salones,
    required this.caminos,
    this.ajustes = const <String, dynamic>{},
  });

  /// 0 = datos que vienen dentro de la app; al publicar es la hora en ms.
  final int version;
  final List<Salon> salones;
  final List<List<Offset>> caminos;

  /// Textos y valores que cambia el administrador (título, nombres de los
  /// pisos, velocidad al caminar, punto de acceso…).
  final Map<String, dynamic> ajustes;

  DatosMapa copyWith({
    int? version,
    List<Salon>? salones,
    List<List<Offset>>? caminos,
    Map<String, dynamic>? ajustes,
  }) =>
      DatosMapa(
        version: version ?? this.version,
        salones: salones ?? this.salones,
        caminos: caminos ?? this.caminos,
        ajustes: ajustes ?? this.ajustes,
      );

  // ---------------------------------------------------------------- bloques
  /// Nombres de los bloques (edificios), en el orden en que aparecen.
  List<String> get bloques {
    final vistos = <String>{};
    return [
      for (final s in salones)
        if (s.edificio.isNotEmpty && vistos.add(s.edificio)) s.edificio,
    ];
  }

  List<Salon> salonesDe(String bloque) => [for (final s in salones) if (s.edificio == bloque) s];

  // ---------------------------------------------------------------- ajustes
  String textoAjuste(String clave, String defecto) {
    final v = ajustes[clave];
    final t = v == null ? '' : '$v'.trim();
    return t.isEmpty ? defecto : t;
  }

  double numeroAjuste(String clave, double defecto) {
    final v = ajustes[clave];
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}'.trim().replaceAll(',', '.')) ?? defecto;
  }

  String get titulo => textoAjuste('titulo', 'TecNM Campus Orizaba');
  String get subtitulo => textoAjuste('subtitulo', 'Toca un salón o edificio en el mapa');

  String nombrePiso(int piso) => switch (piso) {
        1 => textoAjuste('pisoBaja', 'Planta baja'),
        2 => textoAjuste('pisoAlta', 'Planta alta'),
        _ => 'Piso $piso',
      };

  double get metrosPorMinuto => numeroAjuste('metrosPorMinuto', 80).clamp(20.0, 200.0).toDouble();
  double get accesoLat => numeroAjuste('accesoLat', 18.85472947868148);
  double get accesoLng => numeroAjuste('accesoLng', -97.09831297465401);

  Map<String, dynamic> toJson() => {
        'version': version,
        'salones': [for (final s in salones) s.toJson()],
        'caminos': [for (final c in caminos) _ptsAJson(c)],
        'ajustes': ajustes,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory DatosMapa.fromJson(Map<String, dynamic> j) {
    final salones = <Salon>[];
    final rawSalones = j['salones'];
    // Firebase puede devolver una lista como mapa si faltan índices.
    final itemsS = rawSalones is Map ? rawSalones.values : (rawSalones is List ? rawSalones : const []);
    for (final e in itemsS) {
      if (e is Map) salones.add(Salon.fromJson(Map<String, dynamic>.from(e)));
    }
    final caminos = <List<Offset>>[];
    final rawCaminos = j['caminos'];
    final itemsC = rawCaminos is Map ? rawCaminos.values : (rawCaminos is List ? rawCaminos : const []);
    for (final c in itemsC) {
      final pts = _ptsDeJson(c);
      if (pts.length >= 2) caminos.add(pts);
    }
    final aj = j['ajustes'];
    return DatosMapa(
      version: (j['version'] as num?)?.toInt() ?? 0,
      salones: salones,
      caminos: caminos,
      ajustes: aj is Map ? Map<String, dynamic>.from(aj) : const <String, dynamic>{},
    );
  }

  /// Los datos con los que venía la app antes del modo administrador.
  factory DatosMapa.porDefecto() => DatosMapa(
        version: 0,
        salones: _salonesSemilla,
        caminos: [for (final c in _caminosSemilla) List<Offset>.of(c)],
      );
}

Salon _semilla(String numero, String edificio, int piso, Rect area, Rect mapa) => Salon(
      numero: numero,
      edificio: edificio,
      piso: piso,
      poligonoImagen: _rectAPoligono(area),
      poligonoMapa: [for (final q in _rectAPoligono(mapa)) redondear(rejillaAPlano(q))],
    );

final List<Salon> _salonesSemilla = [
  _semilla('205', 'Edificio A', 2, Rect.fromLTRB(712, 440, 764, 712), Rect.fromLTRB(715, 446, 762, 707)),
  _semilla('202', 'Edificio B', 2, Rect.fromLTRB(826, 440, 872, 712), Rect.fromLTRB(833, 441, 874, 707)),
  _semilla('118', 'Edificio C', 1, Rect.fromLTRB(930, 440, 980, 712), Rect.fromLTRB(940, 436, 1013, 707)),
  _semilla('112', 'Edificio D', 1, Rect.fromLTRB(1034, 440, 1088, 712), Rect.fromLTRB(1034, 439, 1089, 711)),
  _semilla('302', 'Edificio E', 3, Rect.fromLTRB(784, 258, 878, 340), Rect.fromLTRB(748, 255, 861, 347)),
  _semilla('307', 'Edificio F', 3, Rect.fromLTRB(880, 258, 960, 340), Rect.fromLTRB(861, 255, 957, 347)),
  _semilla('103', 'Edificio G', 1, Rect.fromLTRB(1003, 200, 1125, 342), Rect.fromLTRB(1008, 195, 1117, 360)),
  _semilla('214', 'Edificio H', 2, Rect.fromLTRB(706, 120, 835, 168), Rect.fromLTRB(683, 142, 817, 169)),
  _semilla('108', 'Edificio I', 1, Rect.fromLTRB(870, 70, 915, 160), Rect.fromLTRB(870, 70, 916, 159)),
  _semilla('304', 'Edificio J', 3, Rect.fromLTRB(982, 58, 1122, 108), Rect.fromLTRB(982, 57, 1122, 108)),
  _semilla('119', 'Edificio K', 1, Rect.fromLTRB(1158, 75, 1407, 218), Rect.fromLTRB(1145, 72, 1270, 202)),
  _semilla('313', 'Edificio L', 3, Rect.fromLTRB(1218, 376, 1376, 422), Rect.fromLTRB(1238, 375, 1410, 412)),
  _semilla('110', 'Edificio M', 1, Rect.fromLTRB(1362, 227, 1404, 332), Rect.fromLTRB(1311, 214, 1354, 315)),
  _semilla('310', 'Edificio N', 3, Rect.fromLTRB(1315, 462, 1407, 558), Rect.fromLTRB(1352, 451, 1444, 546)),
  _semilla('306', 'Edificio O', 3, Rect.fromLTRB(1110, 470, 1315, 560), Rect.fromLTRB(1120, 465, 1351, 548)),
  _semilla('204', 'Edificio P', 2, Rect.fromLTRB(213, 358, 535, 408), Rect.fromLTRB(239, 349, 552, 401)),
  _semilla('303', 'Edificio Q', 3, Rect.fromLTRB(547, 420, 597, 468), Rect.fromLTRB(547, 420, 598, 469)),
  _semilla('218', 'Edificio R', 2, Rect.fromLTRB(607, 420, 668, 466), Rect.fromLTRB(608, 420, 669, 465)),
  _semilla('211', 'Edificio S', 2, Rect.fromLTRB(385, 520, 502, 592), Rect.fromLTRB(382, 538, 492, 614)),
  _semilla('219', 'Edificio T', 2, Rect.fromLTRB(531, 518, 655, 566), Rect.fromLTRB(533, 532, 659, 572)),
  _semilla('212', 'Edificio U', 2, Rect.fromLTRB(388, 622, 503, 692), Rect.fromLTRB(385, 587, 494, 702)),
  _semilla('208', 'Edificio V', 2, Rect.fromLTRB(517, 620, 558, 730), Rect.fromLTRB(517, 621, 558, 729)),
  _semilla('217', 'Edificio W', 2, Rect.fromLTRB(625, 685, 712, 735), Rect.fromLTRB(626, 686, 711, 736)),
];

const List<List<Offset>> _caminosSemilla = [
  [Offset(700, 175), Offset(700, 260), Offset(700, 350), Offset(700, 430), Offset(700, 475), Offset(700, 600), Offset(700, 680)],
  [Offset(700, 350), Offset(970, 350), Offset(1130, 350)],
  [Offset(700, 430), Offset(1130, 430)],
  [Offset(1130, 100), Offset(1130, 200), Offset(1130, 350), Offset(1130, 400), Offset(1130, 430), Offset(1130, 450), Offset(1130, 470)],
  [Offset(1130, 400), Offset(1216, 400)],
  [Offset(1130, 450), Offset(1400, 450)],
  [Offset(945, 40), Offset(945, 175), Offset(945, 250), Offset(970, 250), Offset(970, 350)],
  [Offset(700, 175), Offset(945, 175)],
  [Offset(700, 475), Offset(515, 475)],
  [Offset(515, 412), Offset(515, 475), Offset(515, 600), Offset(515, 735)],
  [Offset(515, 412), Offset(250, 412)],
  [Offset(700, 600), Offset(515, 600), Offset(465, 600)],
];
