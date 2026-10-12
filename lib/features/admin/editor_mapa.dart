import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:orienta_tec/app/theme/tema_app.dart';
import 'package:orienta_tec/core/mapa_datos.dart';
import 'package:orienta_tec/core/mapa_repositorio.dart';

enum Herramienta { editar, nuevoSalon, nuevaRuta }

enum ResultadoToque { nada, salonTerminado }

const Color _ambar = Color(0xFFFFA000);
const Color _verdeEd = Color(0xFF00C853);
const Color _cianEd = Color(0xFF00E5FF);
const Color _rosaEd = Color(0xFFFF3366);

/// Estado y lógica de edición del mapa. No dibuja nada por sí mismo:
/// la pantalla le pasa los toques (en píxeles del plano) y le pide las capas.
class EditorMapa extends ChangeNotifier {
  EditorMapa(DatosMapa inicial) : _datos = inicial;

  DatosMapa _datos;
  final List<DatosMapa> _deshacer = <DatosMapa>[];
  bool _sucio = false;

  DatosMapa get datos => _datos;
  bool get sucio => _sucio;
  bool get puedeDeshacer => _deshacer.isNotEmpty;

  Herramienta herramienta = Herramienta.editar;

  /// Nuevo salón: true = dos toques (esquinas opuestas), false = polígono libre.
  bool rectangulo = true;

  /// Puntos del salón o la ruta que se están dibujando.
  final List<Offset> trazo = <Offset>[];
  bool _dibujoImagen = false;

  String? salonSel;
  int? caminoSel;
  int? verticeSel;

  Salon? get salonSeleccionado {
    final n = salonSel;
    if (n == null) return null;
    for (final s in _datos.salones) {
      if (s.numero == n) return s;
    }
    return null;
  }

  List<Offset>? get caminoSeleccionado {
    final i = caminoSel;
    if (i == null || i >= _datos.caminos.length) return null;
    return _datos.caminos[i];
  }

  // ------------------------------------------------------------- historial
  void _aplicar(DatosMapa nuevo) {
    _deshacer.add(_datos);
    if (_deshacer.length > 60) _deshacer.removeAt(0);
    _datos = nuevo;
    _sucio = true;
    notifyListeners();
  }

  void deshacer() {
    if (_deshacer.isEmpty) return;
    _datos = _deshacer.removeLast();
    _sucio = true;
    salonSel = null;
    caminoSel = null;
    verticeSel = null;
    trazo.clear();
    notifyListeners();
  }

  /// Reemplaza todo (descartar cambios o importar un JSON).
  void reemplazarDatos(DatosMapa nuevo, {required bool sucio}) {
    _datos = nuevo;
    _deshacer.clear();
    _sucio = sucio;
    salonSel = null;
    caminoSel = null;
    verticeSel = null;
    trazo.clear();
    notifyListeners();
  }

  void marcarPublicado(DatosMapa publicado) {
    _datos = publicado;
    _deshacer.clear();
    _sucio = false;
    notifyListeners();
  }

  // ------------------------------------------------------------ selección
  void elegirHerramienta(Herramienta h) {
    herramienta = h;
    trazo.clear();
    verticeSel = null;
    if (h != Herramienta.editar) {
      salonSel = null;
      caminoSel = null;
    }
    notifyListeners();
  }

  void alternarRectangulo(bool valor) {
    rectangulo = valor;
    trazo.clear();
    notifyListeners();
  }

  void seleccionarSalon(String numero) {
    herramienta = Herramienta.editar;
    salonSel = numero;
    caminoSel = null;
    verticeSel = null;
    trazo.clear();
    notifyListeners();
  }

  void deseleccionar() {
    salonSel = null;
    caminoSel = null;
    verticeSel = null;
    notifyListeners();
  }

  void cancelarVertice() {
    verticeSel = null;
    notifyListeners();
  }

  void quitarUltimoPunto() {
    if (trazo.isEmpty) return;
    trazo.removeLast();
    notifyListeners();
  }

  void cancelarTrazo() {
    trazo.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------- toques
  /// [p] viene en px del plano; [radio] es el equivalente en px del plano de
  /// unos 16 px de pantalla (cambia con el zoom).
  ResultadoToque alTocar(Offset p, {required bool imagen, required double radio}) {
    switch (herramienta) {
      case Herramienta.nuevoSalon:
        return _tocarNuevoSalon(p, imagen);
      case Herramienta.nuevaRuta:
        _tocarNuevaRuta(p, radio);
        return ResultadoToque.nada;
      case Herramienta.editar:
        _tocarEditar(p, imagen, radio);
        return ResultadoToque.nada;
    }
  }

  ResultadoToque _tocarNuevoSalon(Offset p, bool imagen) {
    _dibujoImagen = imagen;
    final q = redondear(p);
    if (!rectangulo) {
      trazo.add(q);
      notifyListeners();
      return ResultadoToque.nada;
    }
    if (trazo.length != 1) {
      trazo
        ..clear()
        ..add(q);
      notifyListeners();
      return ResultadoToque.nada;
    }
    final a = trazo.first;
    final List<Offset> poly;
    if (imagen) {
      final r = Rect.fromPoints(a, q);
      poly = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    } else {
      // En el mapa base el rectángulo se arma sobre la rejilla de las calles
      // y luego se lleva al plano, igual que los contornos originales.
      final r = Rect.fromPoints(planoARejilla(a), planoARejilla(q));
      poly = [
        for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) rejillaAPlano(c),
      ];
    }
    final caja = limitesDe(poly);
    trazo.clear();
    if (caja.width < 4 || caja.height < 4) {
      notifyListeners();
      return ResultadoToque.nada;
    }
    trazo.addAll(poly.map(redondear));
    notifyListeners();
    return ResultadoToque.salonTerminado;
  }

  void _tocarNuevaRuta(Offset p, double radio) {
    final q = _ajustar(p, radio);
    if (trazo.isNotEmpty && trazo.last == q) return;
    trazo.add(q);
    notifyListeners();
  }

  /// Imán: si el toque cae cerca de un punto de ruta existente se usa ese
  /// punto; si cae cerca de un tramo se usa el punto más cercano del tramo.
  /// Así las rutas nuevas quedan conectadas con la red.
  Offset _ajustar(Offset p, double radio, {bool aristas = true, Offset? excluir}) {
    Offset? mejor;
    var dm = radio;
    void probar(Offset n) {
      if (excluir != null && n == excluir) return;
      final d = (n - p).distance;
      if (d < dm) {
        dm = d;
        mejor = n;
      }
    }

    for (final c in _datos.caminos) {
      for (final n in c) {
        probar(n);
      }
    }
    for (final n in trazo) {
      probar(n);
    }
    final nodo = mejor;
    if (nodo != null) return nodo;

    if (aristas) {
      Offset? q;
      var dq = radio;
      for (final c in _datos.caminos) {
        for (var i = 0; i < c.length - 1; i++) {
          final pr = proyectarEnSegmento(p, c[i], c[i + 1]);
          final d = (p - pr).distance;
          if (d < dq) {
            dq = d;
            q = pr;
          }
        }
      }
      if (q != null) return redondear(q);
    }
    return redondear(p);
  }

  void _guardarPoligono(Salon s, bool imagen, List<Offset> pts) {
    final nuevo = imagen ? s.copyWith(poligonoImagen: pts) : s.copyWith(poligonoMapa: pts);
    _aplicar(_datos.copyWith(
      salones: [for (final x in _datos.salones) x.numero == s.numero ? nuevo : x],
    ));
  }

  void _tocarEditar(Offset p, bool imagen, double radio) {
    final rh = radio * 1.2;

    // --- Salón elegido: mover / agregar puntos del contorno.
    final sal = salonSeleccionado;
    if (sal != null) {
      final pts = List<Offset>.of(imagen ? sal.esquinasImagen : sal.esquinasMapa);
      final v = verticeSel;
      if (v != null && v < pts.length) {
        if ((pts[v] - p).distance <= rh) {
          verticeSel = null;
          notifyListeners();
          return;
        }
        pts[v] = redondear(p);
        verticeSel = null;
        _guardarPoligono(sal, imagen, pts);
        return;
      }
      for (var i = 0; i < pts.length; i++) {
        if ((pts[i] - p).distance <= rh) {
          verticeSel = i;
          notifyListeners();
          return;
        }
      }
      for (var i = 0; i < pts.length; i++) {
        final a = pts[i];
        final b = pts[(i + 1) % pts.length];
        final medio = (a + b) / 2;
        if ((medio - p).distance <= rh * 0.8) {
          pts.insert(i + 1, redondear(medio));
          verticeSel = i + 1;
          _guardarPoligono(sal, imagen, pts);
          return;
        }
      }
    }

    // --- Ruta elegida: mover / agregar puntos.
    final idx = caminoSel;
    if (idx != null && idx < _datos.caminos.length) {
      final c = _datos.caminos[idx];
      final v = verticeSel;
      if (v != null && v < c.length) {
        if ((c[v] - p).distance <= rh) {
          verticeSel = null;
          notifyListeners();
          return;
        }
        final viejo = c[v];
        final nuevo = _ajustar(p, radio, aristas: false, excluir: viejo);
        verticeSel = null;
        // Se mueve en todas las rutas que comparten ese punto (el cruce).
        _aplicar(_datos.copyWith(
          caminos: [
            for (final x in _datos.caminos) [for (final n in x) n == viejo ? nuevo : n],
          ],
        ));
        return;
      }
      for (var i = 0; i < c.length; i++) {
        if ((c[i] - p).distance <= rh) {
          verticeSel = i;
          notifyListeners();
          return;
        }
      }
      for (var i = 0; i < c.length - 1; i++) {
        final medio = (c[i] + c[i + 1]) / 2;
        if ((medio - p).distance <= rh * 0.8) {
          final nc = List<Offset>.of(c)..insert(i + 1, redondear(medio));
          verticeSel = i + 1;
          _aplicar(_datos.copyWith(
            caminos: [
              for (var k = 0; k < _datos.caminos.length; k++) k == idx ? nc : _datos.caminos[k],
            ],
          ));
          return;
        }
      }
    }

    // --- Elegir otra cosa.
    verticeSel = null;
    for (final s in _datos.salones) {
      final pts = imagen ? s.esquinasImagen : s.esquinasMapa;
      if (puntoCercaDePoligono(p, pts)) {
        salonSel = s.numero;
        caminoSel = null;
        notifyListeners();
        return;
      }
    }
    var mejorK = -1;
    var mejorD = radio;
    for (var k = 0; k < _datos.caminos.length; k++) {
      final c = _datos.caminos[k];
      for (var i = 0; i < c.length - 1; i++) {
        final d = distanciaASegmento(p, c[i], c[i + 1]);
        if (d < mejorD) {
          mejorD = d;
          mejorK = k;
        }
      }
    }
    salonSel = null;
    caminoSel = mejorK >= 0 ? mejorK : null;
    notifyListeners();
  }

  // ------------------------------------------------------------ acciones
  /// ¿Ya hay contorno suficiente para pedir los datos del salón?
  bool get contornoListo => herramienta == Herramienta.nuevoSalon && trazo.length >= 3;

  String? crearSalon(Salon datos) {
    final numero = datos.numero.trim();
    if (numero.isEmpty) return 'Escribe el número del salón.';
    if (_datos.salones.any((s) => s.numero == numero)) return 'Ya existe un salón con ese número.';
    if (trazo.length < 3) return 'Falta dibujar el contorno.';
    final poly = List<Offset>.of(trazo);
    final nuevo = _dibujoImagen
        ? datos.copyWith(numero: numero, poligonoImagen: poly, poligonoMapa: const <Offset>[])
        : datos.copyWith(numero: numero, poligonoMapa: poly, poligonoImagen: const <Offset>[]);
    trazo.clear();
    herramienta = Herramienta.editar;
    salonSel = numero;
    caminoSel = null;
    verticeSel = null;
    _aplicar(_datos.copyWith(salones: [..._datos.salones, nuevo]));
    return null;
  }

  String? actualizarSalon(String original, Salon nuevo) {
    final numero = nuevo.numero.trim();
    if (numero.isEmpty) return 'Escribe el número del salón.';
    if (numero != original && _datos.salones.any((s) => s.numero == numero)) {
      return 'Ya existe un salón con ese número.';
    }
    if (salonSel == original) salonSel = numero;
    _aplicar(_datos.copyWith(
      salones: [
        for (final s in _datos.salones) s.numero == original ? nuevo.copyWith(numero: numero) : s,
      ],
    ));
    return null;
  }

  void eliminarSalonSeleccionado() {
    final n = salonSel;
    if (n == null) return;
    salonSel = null;
    verticeSel = null;
    _aplicar(_datos.copyWith(salones: [for (final s in _datos.salones) if (s.numero != n) s]));
  }

  void eliminarCaminoSeleccionado() {
    final i = caminoSel;
    if (i == null || i >= _datos.caminos.length) return;
    caminoSel = null;
    verticeSel = null;
    _aplicar(_datos.copyWith(
      caminos: [
        for (var k = 0; k < _datos.caminos.length; k++) if (k != i) _datos.caminos[k],
      ],
    ));
  }

  /// Quita el punto elegido del contorno (mínimo 3) o de la ruta (mínimo 2).
  void quitarVerticeElegido({required bool imagen}) {
    final v = verticeSel;
    if (v == null) return;
    final sal = salonSeleccionado;
    if (sal != null) {
      final pts = List<Offset>.of(imagen ? sal.esquinasImagen : sal.esquinasMapa);
      if (pts.length <= 3 || v >= pts.length) return;
      pts.removeAt(v);
      verticeSel = null;
      _guardarPoligono(sal, imagen, pts);
      return;
    }
    final idx = caminoSel;
    final c = caminoSeleccionado;
    if (idx == null || c == null || c.length <= 2 || v >= c.length) return;
    final nc = List<Offset>.of(c)..removeAt(v);
    verticeSel = null;
    _aplicar(_datos.copyWith(
      caminos: [
        for (var k = 0; k < _datos.caminos.length; k++) k == idx ? nc : _datos.caminos[k],
      ],
    ));
  }

  bool terminarRuta() {
    if (trazo.length < 2) return false;
    final caminos = [for (final c in _datos.caminos) List<Offset>.of(c)];
    // Si la ruta nueva toca un tramo ajeno, se agrega ahí un punto para que
    // ambas rutas queden conectadas.
    for (final p in trazo) {
      _insertarEnTramo(caminos, p);
    }
    caminos.add(List<Offset>.of(trazo));
    trazo.clear();
    _aplicar(_datos.copyWith(caminos: caminos));
    return true;
  }

  void _insertarEnTramo(List<List<Offset>> caminos, Offset p) {
    for (final c in caminos) {
      if (c.contains(p)) return;
    }
    for (final c in caminos) {
      for (var i = 0; i < c.length - 1; i++) {
        if (distanciaASegmento(p, c[i], c[i + 1]) < 0.08) {
          c.insert(i + 1, p);
          return;
        }
      }
    }
  }

  // ----------------------------------------------------------- revisión
  /// Busca problemas que harían fallar las rutas de los usuarios.
  List<String> revisar(Offset origen, double mpp) {
    final out = <String>[];
    if (_datos.caminos.isEmpty) {
      return ['No hay rutas dibujadas: nadie podrá llegar a ningún salón.'];
    }

    final ids = <Offset, int>{};
    final padre = <int>[];
    int idDe(Offset o) => ids.putIfAbsent(o, () {
          padre.add(padre.length);
          return padre.length - 1;
        });
    int raiz(int x) {
      while (padre[x] != x) {
        padre[x] = padre[padre[x]];
        x = padre[x];
      }
      return x;
    }

    for (final c in _datos.caminos) {
      for (var i = 0; i < c.length; i++) {
        final a = idDe(c[i]);
        if (i > 0) padre[raiz(a)] = raiz(idDe(c[i - 1]));
      }
    }
    final grupos = {for (var i = 0; i < padre.length; i++) raiz(i)};
    if (grupos.length > 1) {
      out.add('La red de rutas está partida en ${grupos.length} grupos sin conexión entre sí. '
          'Une las rutas tocando un punto o tramo existente al dibujar.');
    }

    // Tramo más cercano a una zona (punto o rectángulo): distancia y grupo.
    (double, int) cercano(Rect zona) {
      var mejorD = double.infinity;
      var grupo = -1;
      for (final c in _datos.caminos) {
        for (var i = 0; i < c.length - 1; i++) {
          final largo = (c[i + 1] - c[i]).distance;
          final n = math.max(1, (largo / 5).ceil());
          for (var k = 0; k <= n; k++) {
            final q = Offset.lerp(c[i], c[i + 1], k / n)!;
            final lim = Offset(q.dx.clamp(zona.left, zona.right).toDouble(), q.dy.clamp(zona.top, zona.bottom).toDouble());
            final d = (q - lim).distance;
            if (d < mejorD) {
              mejorD = d;
              grupo = raiz(idDe(c[i]));
            }
          }
        }
      }
      return (mejorD, grupo);
    }

    final (dOrigen, gOrigen) = cercano(Rect.fromLTWH(origen.dx, origen.dy, 0, 0));
    if (dOrigen * mpp > 15) {
      out.add('El acceso principal queda a ${(dOrigen * mpp).round()} m de la red de rutas.');
    }
    for (final s in _datos.salones) {
      if (s.esquinasImagen.length < 3) {
        out.add('${s.nombre} no tiene contorno dibujado.');
        continue;
      }
      final (d, g) = cercano(s.area);
      if (g != gOrigen) {
        out.add('${s.nombre}: la ruta más cercana no está conectada con el acceso principal.');
      } else if (d * mpp > 25) {
        out.add('${s.nombre} queda a ${(d * mpp).round()} m de la ruta más cercana.');
      }
    }
    return out;
  }

  // -------------------------------------------------------------- capas
  Widget _punto(double d, Color relleno, Color borde, {double grosor = 2}) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: relleno,
          border: Border.all(color: borde, width: grosor),
        ),
      );

  Marker _marcador(LatLng pos, double d, Color relleno, Color borde, {double grosor = 2}) => Marker(
        point: pos,
        width: d,
        height: d,
        child: IgnorePointer(child: _punto(d, relleno, borde, grosor: grosor)),
      );

  /// Capas que se dibujan encima del mapa en modo administrador.
  List<Widget> capas({required LatLng Function(Offset) aLatLng, required bool imagen}) {
    final lineas = <Polyline>[];
    for (var k = 0; k < _datos.caminos.length; k++) {
      final c = _datos.caminos[k];
      if (c.length < 2) continue;
      final sel = k == caminoSel;
      lineas.add(Polyline(
        points: c.map(aLatLng).toList(),
        color: sel ? _cianEd : _ambar.withValues(alpha: 0.9),
        strokeWidth: sel ? 6 : 4,
        borderColor: Colors.black54,
        borderStrokeWidth: 1,
      ));
    }

    final poligonos = <Polygon>[];
    if (trazo.length >= 2) {
      if (herramienta == Herramienta.nuevaRuta) {
        lineas.add(Polyline(points: trazo.map(aLatLng).toList(), color: _verdeEd, strokeWidth: 5, borderColor: Colors.black54, borderStrokeWidth: 1));
      } else if (herramienta == Herramienta.nuevoSalon) {
        if (trazo.length >= 3) {
          poligonos.add(Polygon(
            points: trazo.map(aLatLng).toList(),
            color: _verdeEd.withValues(alpha: 0.25),
            borderColor: _verdeEd,
            borderStrokeWidth: 3,
          ));
        } else {
          lineas.add(Polyline(points: trazo.map(aLatLng).toList(), color: _verdeEd, strokeWidth: 4));
        }
      }
    }

    final marcas = <Marker>[];

    // Puntos de todas las rutas (los cruces se ven más grandes).
    final conteo = <Offset, int>{};
    for (final c in _datos.caminos) {
      for (final n in c) {
        conteo[n] = (conteo[n] ?? 0) + 1;
      }
    }
    conteo.forEach((n, veces) {
      marcas.add(_marcador(aLatLng(n), veces > 1 ? 13 : 9, Colors.white, _ambar, grosor: veces > 1 ? 3 : 2));
    });

    // Ruta elegida: puntos grandes y puntos medios para agregar.
    final cam = caminoSeleccionado;
    if (cam != null) {
      for (var i = 0; i < cam.length - 1; i++) {
        marcas.add(_marcador(aLatLng((cam[i] + cam[i + 1]) / 2), 10, Colors.transparent, _cianEd));
      }
      for (var i = 0; i < cam.length; i++) {
        final elegido = i == verticeSel;
        marcas.add(_marcador(aLatLng(cam[i]), 20, elegido ? _rosaEd : _cianEd, Colors.white, grosor: 3));
      }
    }

    // Salón elegido: esquinas grandes y puntos medios.
    final sal = salonSeleccionado;
    if (sal != null) {
      final pts = imagen ? sal.esquinasImagen : sal.esquinasMapa;
      for (var i = 0; i < pts.length; i++) {
        marcas.add(_marcador(aLatLng((pts[i] + pts[(i + 1) % pts.length]) / 2), 10, Colors.transparent, _cianEd));
      }
      for (var i = 0; i < pts.length; i++) {
        final elegido = i == verticeSel;
        marcas.add(_marcador(aLatLng(pts[i]), 20, elegido ? _rosaEd : _cianEd, Colors.white, grosor: 3));
      }
    }

    // Puntos del trazo en curso.
    for (final t in trazo) {
      marcas.add(_marcador(aLatLng(t), 16, _verdeEd, Colors.white, grosor: 3));
    }

    return [
      if (poligonos.isNotEmpty) PolygonLayer(polygons: poligonos),
      if (lineas.isNotEmpty) PolylineLayer(polylines: lineas),
      MarkerLayer(rotate: true, markers: marcas),
    ];
  }
}

// ---------------------------------------------------------------------------
// Diálogos
// ---------------------------------------------------------------------------

/// Pide los datos de un salón. Devuelve null si se cancela. Los contornos
/// del resultado son los de [base] (o vacíos si es un salón nuevo).
Future<Salon?> pedirDatosSalon(BuildContext context, {Salon? base}) {
  return showDialog<Salon>(
    context: context,
    builder: (ctx) => _DialogoSalon(base: base),
  );
}

class _DialogoSalon extends StatefulWidget {
  const _DialogoSalon({this.base});
  final Salon? base;

  @override
  State<_DialogoSalon> createState() => _DialogoSalonState();
}

class _DialogoSalonState extends State<_DialogoSalon> {
  late final TextEditingController _numero = TextEditingController(text: widget.base?.numero ?? '');
  late final TextEditingController _edificio = TextEditingController(text: widget.base?.edificio ?? '');
  late final TextEditingController _piso = TextEditingController(text: '${widget.base?.piso ?? 1}');
  late final TextEditingController _tipo = TextEditingController(text: widget.base?.tipo ?? 'Aula');
  late final TextEditingController _desc = TextEditingController(text: widget.base?.descripcion ?? '');

  @override
  void dispose() {
    _numero.dispose();
    _edificio.dispose();
    _piso.dispose();
    _tipo.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _guardar() {
    final b = widget.base;
    final tipo = _tipo.text.trim();
    Navigator.pop(
      context,
      Salon(
        numero: _numero.text.trim(),
        edificio: _edificio.text.trim(),
        piso: int.tryParse(_piso.text.trim()) ?? 1,
        tipo: tipo.isEmpty ? 'Aula' : tipo,
        descripcion: _desc.text.trim(),
        poligonoImagen: b?.poligonoImagen ?? const <Offset>[],
        poligonoMapa: b?.poligonoMapa ?? const <Offset>[],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.base == null ? 'Nuevo salón' : 'Datos del salón'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _numero, decoration: const InputDecoration(labelText: 'Número (ej. 205)')),
            TextField(controller: _edificio, decoration: const InputDecoration(labelText: 'Edificio (ej. Edificio A)')),
            TextField(
              controller: _piso,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Piso'),
            ),
            TextField(controller: _tipo, decoration: const InputDecoration(labelText: 'Tipo (Aula, Laboratorio…)')),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Pide los datos del salón recién dibujado y lo agrega. Si el número ya
/// existe vuelve a preguntar; si se cancela, el contorno se conserva.
Future<void> crearSalonDibujado(BuildContext context, EditorMapa editor) async {
  var datos = await pedirDatosSalon(context);
  while (datos != null) {
    final error = editor.crearSalon(datos);
    if (error == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    datos = await pedirDatosSalon(context, base: datos);
  }
}

class _DialogoImportar extends StatefulWidget {
  const _DialogoImportar();

  @override
  State<_DialogoImportar> createState() => _DialogoImportarState();
}

class _DialogoImportarState extends State<_DialogoImportar> {
  final TextEditingController _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar JSON'),
      content: TextField(
        controller: _texto,
        maxLines: 8,
        decoration: const InputDecoration(hintText: 'Pega aquí el JSON exportado'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _texto.text), child: const Text('Importar')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panel inferior del administrador
// ---------------------------------------------------------------------------
class PanelEditor extends StatelessWidget {
  const PanelEditor({
    super.key,
    required this.editor,
    required this.imagen,
    required this.origen,
    required this.metrosPorPixel,
  });

  final EditorMapa editor;
  final bool imagen;
  final Offset origen;
  final double metrosPorPixel;

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: p.superficie,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.oscuro ? 0.5 : 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _herramientas(context),
            const SizedBox(height: 6),
            _contexto(context, p),
            const SizedBox(height: 8),
            _pie(context, p),
          ],
        ),
      ),
    );
  }

  Widget _chipHerramienta(Herramienta h, IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icono, size: 18),
        label: Text(texto),
        selected: editor.herramienta == h,
        onSelected: (_) => editor.elegirHerramienta(h),
      ),
    );
  }

  Widget _herramientas(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipHerramienta(Herramienta.editar, Icons.edit_location_alt_outlined, 'Editar'),
                _chipHerramienta(Herramienta.nuevoSalon, Icons.crop_square, 'Nuevo salón'),
                _chipHerramienta(Herramienta.nuevaRuta, Icons.timeline, 'Nueva ruta'),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Deshacer',
          onPressed: editor.puedeDeshacer ? editor.deshacer : null,
          icon: const Icon(Icons.undo),
        ),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (v) => _menu(context, v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'revisar', child: Text('Revisar rutas y salones')),
            PopupMenuItem(value: 'exportar', child: Text('Copiar JSON')),
            PopupMenuItem(value: 'importar', child: Text('Importar JSON')),
            PopupMenuItem(value: 'descartar', child: Text('Descartar cambios y cargar lo publicado')),
          ],
        ),
      ],
    );
  }

  Widget _contexto(BuildContext context, Paleta p) {
    final estilo = TextStyle(color: p.textoSec, fontSize: 13);
    switch (editor.herramienta) {
      case Herramienta.nuevoSalon:
        final n = editor.trazo.length;
        final String pista;
        if (editor.rectangulo) {
          pista = n == 0
              ? 'Toca una esquina del salón.'
              : (n == 1 ? 'Toca la esquina opuesta.' : 'Contorno listo.');
        } else {
          pista = '$n punto${n == 1 ? '' : 's'}: toca cada esquina del salón.';
        }
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Rectángulo'),
              selected: editor.rectangulo,
              onSelected: (_) => editor.alternarRectangulo(true),
            ),
            ChoiceChip(
              label: const Text('Polígono'),
              selected: !editor.rectangulo,
              onSelected: (_) => editor.alternarRectangulo(false),
            ),
            Text('$pista (vista ${imagen ? 'satélite' : 'mapa'})', style: estilo),
            if (!editor.rectangulo && n > 0)
              TextButton.icon(onPressed: editor.quitarUltimoPunto, icon: const Icon(Icons.backspace_outlined, size: 18), label: const Text('Quitar punto')),
            if (editor.contornoListo)
              FilledButton.tonalIcon(
                onPressed: () => crearSalonDibujado(context, editor),
                icon: const Icon(Icons.check),
                label: const Text('Terminar'),
              ),
            if (n > 0) TextButton(onPressed: editor.cancelarTrazo, child: const Text('Cancelar')),
          ],
        );
      case Herramienta.nuevaRuta:
        final n = editor.trazo.length;
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              n == 0
                  ? 'Toca el mapa para marcar el inicio. Si tocas cerca de otra ruta se conecta sola.'
                  : '$n punto${n == 1 ? '' : 's'}. Sigue tocando; termina en otra ruta para conectarla.',
              style: estilo,
            ),
            if (n > 0)
              TextButton.icon(onPressed: editor.quitarUltimoPunto, icon: const Icon(Icons.backspace_outlined, size: 18), label: const Text('Quitar punto')),
            if (n >= 2)
              FilledButton.tonalIcon(
                onPressed: editor.terminarRuta,
                icon: const Icon(Icons.check),
                label: const Text('Terminar ruta'),
              ),
            if (n > 0) TextButton(onPressed: editor.cancelarTrazo, child: const Text('Cancelar')),
          ],
        );
      case Herramienta.editar:
        final sal = editor.salonSeleccionado;
        if (sal != null) return _contextoSalon(context, sal, estilo);
        final cam = editor.caminoSeleccionado;
        if (cam != null) return _contextoRuta(cam, estilo);
        return Text('Toca un salón o una ruta para editarla.', style: estilo);
    }
  }

  Widget _contextoSalon(BuildContext context, Salon sal, TextStyle estilo) {
    final propio = imagen ? sal.tieneImagen : sal.tieneMapa;
    final v = editor.verticeSel;
    final pts = imagen ? sal.esquinasImagen : sal.esquinasMapa;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${sal.nombre} · ${sal.edificio}', style: estilo.copyWith(fontWeight: FontWeight.w700)),
        if (!propio) Text('(usa el contorno de la otra vista; al moverlo se crea el de esta)', style: estilo),
        if (v != null) ...[
          Text('Toca el mapa para mover el punto.', style: estilo),
          TextButton.icon(
            onPressed: pts.length > 3 ? () => editor.quitarVerticeElegido(imagen: imagen) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Quitar punto'),
          ),
          TextButton(onPressed: editor.cancelarVertice, child: const Text('Cancelar')),
        ] else ...[
          Text('Toca un punto para moverlo o un círculo vacío para agregar uno.', style: estilo),
          TextButton.icon(
            onPressed: () async {
              final nuevo = await pedirDatosSalon(context, base: sal);
              if (nuevo == null || !context.mounted) return;
              final error = editor.actualizarSalon(sal.numero, nuevo);
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
              }
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Datos'),
          ),
          TextButton.icon(
            onPressed: () => _confirmar(
              context,
              '¿Eliminar el ${sal.nombre}?',
              editor.eliminarSalonSeleccionado,
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Eliminar salón'),
          ),
        ],
      ],
    );
  }

  Widget _contextoRuta(List<Offset> cam, TextStyle estilo) {
    final v = editor.verticeSel;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Ruta de ${cam.length} puntos', style: estilo.copyWith(fontWeight: FontWeight.w700)),
        if (v != null) ...[
          Text('Toca el mapa para mover el punto (se mueve también en las rutas que cruzan ahí).', style: estilo),
          TextButton.icon(
            onPressed: cam.length > 2 ? () => editor.quitarVerticeElegido(imagen: imagen) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Quitar punto'),
          ),
          TextButton(onPressed: editor.cancelarVertice, child: const Text('Cancelar')),
        ] else ...[
          Text('Toca un punto para moverlo o un círculo vacío para agregar uno.', style: estilo),
          Builder(
            builder: (context) => TextButton.icon(
              onPressed: () => _confirmar(context, '¿Eliminar esta ruta completa?', editor.eliminarCaminoSeleccionado),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Eliminar ruta'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pie(BuildContext context, Paleta p) {
    final String estado;
    if (editor.sucio) {
      estado = 'Cambios sin publicar';
    } else if (repositorioMapa.remotoConfigurado) {
      estado = 'Todo publicado';
    } else {
      estado = 'Sin servidor configurado (solo local)';
    }
    return Row(
      children: [
        Icon(editor.sucio ? Icons.circle : Icons.check_circle_outline, size: 14, color: editor.sucio ? _ambar : p.verde),
        const SizedBox(width: 6),
        Expanded(child: Text(estado, style: TextStyle(color: p.textoSec, fontSize: 12))),
        FilledButton.icon(
          onPressed: editor.sucio ? () => _publicar(context) : null,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Publicar'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- acciones
  Future<void> _confirmar(BuildContext context, String pregunta, VoidCallback alAceptar) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pregunta),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceptar')),
        ],
      ),
    );
    if (ok == true) alAceptar();
  }

  Future<void> _publicar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!repositorioMapa.remotoConfigurado) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Falta configurar el servidor'),
          content: const Text(
            'Para que los cambios lleguen a Orienta-Tec hay que poner la URL de la base de datos en '
            'lib/core/config_sync.dart (ver README). Mientras tanto puedes usar "Copiar JSON" para guardar tu trabajo.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Publicar cambios?'),
        content: const Text('Los usuarios de Orienta-Tec verán el mapa nuevo en unos segundos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publicar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repositorioMapa.publicar(editor.datos);
      editor.marcarPublicado(repositorioMapa.value);
      messenger.showSnackBar(const SnackBar(content: Text('Publicado. Los usuarios verán los cambios en unos segundos.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo publicar: $e')));
    }
  }

  Future<void> _menu(BuildContext context, String accion) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (accion) {
      case 'revisar':
        final avisos = editor.revisar(origen, metrosPorPixel);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(avisos.isEmpty ? 'Todo en orden' : 'Revisión'),
            content: SizedBox(
              width: double.maxFinite,
              child: avisos.isEmpty
                  ? const Text('Todos los salones tienen contorno y llegan por una ruta conectada al acceso principal.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final a in avisos)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.warning_amber_rounded, color: _ambar),
                            title: Text(a),
                          ),
                      ],
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
          ),
        );
      case 'exportar':
        await Clipboard.setData(ClipboardData(text: editor.datos.toJsonString()));
        messenger.showSnackBar(const SnackBar(content: Text('JSON copiado al portapapeles.')));
      case 'importar':
        final texto = await showDialog<String>(context: context, builder: (_) => const _DialogoImportar());
        if (texto == null || texto.trim().isEmpty) return;
        try {
          final json = jsonDecode(texto);
          if (json is! Map<String, dynamic>) throw const FormatException('No es un objeto JSON');
          final datos = DatosMapa.fromJson(json);
          if (datos.salones.isEmpty) throw const FormatException('No trae salones');
          editor.reemplazarDatos(datos, sucio: true);
          messenger.showSnackBar(const SnackBar(content: Text('JSON importado. Revisa y publica.')));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('JSON no válido: $e')));
        }
      case 'descartar':
        if (!context.mounted) return;
        await _confirmar(context, '¿Descartar los cambios y cargar lo publicado?', () async {
          await repositorioMapa.sincronizar();
          editor.reemplazarDatos(repositorioMapa.value, sucio: false);
        });
    }
  }
}
