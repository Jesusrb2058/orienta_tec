import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:orienta_tec/app/theme/tema_app.dart';
import 'package:orienta_tec/core/catalogo_campus.dart';
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
///
/// Un "bloque" es un edificio con todos sus salones: su contorno se dibuja una
/// sola vez y los salones se reparten dentro de él por columnas.
class EditorMapa extends ChangeNotifier {
  EditorMapa(DatosMapa inicial) : _datos = inicial;

  DatosMapa _datos;
  final List<DatosMapa> _deshacer = <DatosMapa>[];
  bool _sucio = false;

  DatosMapa get datos => _datos;
  bool get sucio => _sucio;
  bool get puedeDeshacer => _deshacer.isNotEmpty;

  Herramienta herramienta = Herramienta.editar;

  /// Nuevo bloque: true = dos toques (esquinas opuestas), false = polígono libre.
  bool rectangulo = true;

  /// Puntos del bloque o la ruta que se están dibujando.
  final List<Offset> trazo = <Offset>[];
  bool _dibujoImagen = false;

  /// Nombre del bloque (edificio) elegido.
  String? bloqueSel;
  int? caminoSel;
  int? verticeSel;

  List<Salon> get salonesSel {
    final b = bloqueSel;
    return b == null ? const <Salon>[] : _datos.salonesDe(b);
  }

  bool get hayBloqueSel => salonesSel.isNotEmpty;

  /// Contorno del bloque elegido en la vista [imagen] (el de la otra vista si
  /// todavía no se dibujó el de esta).
  List<Offset> contornoSel(bool imagen) => contornoDeBloque(salonesSel, imagen);

  /// ¿El bloque elegido tiene contorno propio en esa vista?
  bool contornoPropio(bool imagen) => contornoDeBloque(salonesSel, imagen, propio: true).length >= 3;

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
    bloqueSel = null;
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
    bloqueSel = null;
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
      bloqueSel = null;
      caminoSel = null;
    }
    notifyListeners();
  }

  void alternarRectangulo(bool valor) {
    rectangulo = valor;
    trazo.clear();
    notifyListeners();
  }

  void seleccionarBloque(String nombre) {
    herramienta = Herramienta.editar;
    bloqueSel = nombre;
    caminoSel = null;
    verticeSel = null;
    trazo.clear();
    notifyListeners();
  }

  void deseleccionar() {
    bloqueSel = null;
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

  /// Guarda el contorno del bloque elegido en todos sus salones.
  void _guardarPoligono(bool imagen, List<Offset> pts) {
    final b = bloqueSel;
    if (b == null) return;
    _aplicar(_datos.copyWith(
      salones: [
        for (final x in _datos.salones)
          x.edificio == b
              ? (imagen ? x.copyWith(poligonoImagen: pts) : x.copyWith(poligonoMapa: pts))
              : x,
      ],
    ));
  }

  void _tocarEditar(Offset p, bool imagen, double radio) {
    final rh = radio * 1.2;

    // --- Bloque elegido: mover / agregar puntos del contorno.
    if (hayBloqueSel) {
      final pts = List<Offset>.of(contornoSel(imagen));
      final v = verticeSel;
      if (v != null && v < pts.length) {
        if ((pts[v] - p).distance <= rh) {
          verticeSel = null;
          notifyListeners();
          return;
        }
        pts[v] = redondear(p);
        verticeSel = null;
        _guardarPoligono(imagen, pts);
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
          _guardarPoligono(imagen, pts);
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
        bloqueSel = s.edificio;
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
    bloqueSel = null;
    caminoSel = mejorK >= 0 ? mejorK : null;
    notifyListeners();
  }

  // ------------------------------------------------------------ acciones
  /// ¿Ya hay contorno suficiente para pedir los datos del bloque?
  bool get contornoListo => herramienta == Herramienta.nuevoSalon && trazo.length >= 3;

  /// Crea un bloque con el contorno dibujado y todos sus salones.
  String? crearBloque(String nombre, List<Salon> salones) {
    final b = nombre.trim();
    if (b.isEmpty) return 'Escribe el nombre del bloque.';
    if (_datos.bloques.any((x) => x.toLowerCase() == b.toLowerCase())) {
      return 'Ya existe un bloque con ese nombre.';
    }
    if (salones.isEmpty) return 'Agrega al menos un salón.';
    if (trazo.length < 3) return 'Falta dibujar el contorno.';
    final vistos = <String>{};
    for (final s in salones) {
      if (!vistos.add(s.numero.toLowerCase())) return 'El salón "${s.numero}" está repetido en el bloque.';
    }
    final poly = List<Offset>.of(trazo);
    final nuevos = [
      for (final s in salones)
        s.copyWith(
          edificio: b,
          poligonoImagen: _dibujoImagen ? poly : const <Offset>[],
          poligonoMapa: _dibujoImagen ? const <Offset>[] : poly,
        ),
    ];
    trazo.clear();
    herramienta = Herramienta.editar;
    bloqueSel = b;
    caminoSel = null;
    verticeSel = null;
    _aplicar(_datos.copyWith(salones: [..._datos.salones, ...nuevos]));
    return null;
  }

  /// Si el bloque tiene salones sin columna, se la asigna según su piso.
  /// Devuelve true si hizo cambios.
  bool normalizarColumnas(String bloque) {
    final lista = _datos.salonesDe(bloque);
    if (lista.isEmpty || !lista.any((s) => s.columna < 0)) return false;
    final cols = columnasDeBloque(lista);
    final asignada = <String, int>{};
    for (var k = 0; k < cols.length; k++) {
      for (final s in cols[k]) {
        asignada[s.clave] = k;
      }
    }
    _aplicar(_datos.copyWith(
      salones: [
        for (final s in _datos.salones)
          s.edificio == bloque ? s.copyWith(columna: asignada[s.clave]) : s,
      ],
    ));
    return true;
  }

  /// Número de la próxima columna libre del bloque.
  int siguienteColumna(String bloque) {
    var m = -1;
    for (final s in _datos.salonesDe(bloque)) {
      if (s.columna > m) m = s.columna;
    }
    return m + 1;
  }

  /// Agrega salones al final de una columna del bloque. Los que ya existen se omiten.
  ({int agregados, int omitidos}) agregarSalones(String bloque, int piso, int columna, List<String> nombres) {
    final ref = _datos.salonesDe(bloque);
    final existentes = {for (final s in ref) s.numero.toLowerCase()};
    final polImagen = contornoDeBloque(ref, true, propio: true);
    final polMapa = contornoDeBloque(ref, false, propio: true);
    final nuevos = <Salon>[];
    var omitidos = 0;
    for (final n in nombres) {
      if (!existentes.add(n.toLowerCase())) {
        omitidos++;
        continue;
      }
      nuevos.add(Salon(
        numero: n,
        edificio: bloque,
        piso: piso,
        columna: columna,
        tipo: tipoSugerido(n),
        poligonoImagen: List<Offset>.of(polImagen),
        poligonoMapa: List<Offset>.of(polMapa),
      ));
    }
    if (nuevos.isNotEmpty) _aplicar(_datos.copyWith(salones: [..._datos.salones, ...nuevos]));
    return (agregados: nuevos.length, omitidos: omitidos);
  }

  String? actualizarSalon(String claveOriginal, Salon nuevo) {
    final numero = nuevo.numero.trim();
    if (numero.isEmpty) return 'Escribe el nombre o número del salón.';
    final cambio = nuevo.copyWith(numero: numero);
    if (cambio.clave != claveOriginal && _datos.salones.any((s) => s.clave == cambio.clave)) {
      return 'Ya existe "$numero" en este bloque.';
    }
    _aplicar(_datos.copyWith(
      salones: [for (final s in _datos.salones) s.clave == claveOriginal ? cambio : s],
    ));
    return null;
  }

  void eliminarSalon(String clave) {
    verticeSel = null;
    final restantes = [for (final s in _datos.salones) if (s.clave != clave) s];
    final b = bloqueSel;
    if (b != null && !restantes.any((s) => s.edificio == b)) bloqueSel = null;
    _aplicar(_datos.copyWith(salones: restantes));
  }

  void eliminarBloqueSeleccionado() {
    final b = bloqueSel;
    if (b == null) return;
    bloqueSel = null;
    verticeSel = null;
    _aplicar(_datos.copyWith(salones: [for (final s in _datos.salones) if (s.edificio != b) s]));
  }

  /// Cambia el orden de un salón dentro de su columna (de arriba hacia abajo).
  void reordenarEnColumna(String bloque, int k, int viejo, int nuevo) {
    final cols = columnasDeBloque(_datos.salonesDe(bloque));
    if (k < 0 || k >= cols.length) return;
    final col = List<Salon>.of(cols[k]);
    if (viejo < 0 || viejo >= col.length || nuevo < 0 || nuevo >= col.length || viejo == nuevo) return;
    final claves = {for (final s in col) s.clave};
    final item = col.removeAt(viejo);
    col.insert(nuevo, item);
    final todos = List<Salon>.of(_datos.salones);
    final posiciones = [
      for (var i = 0; i < todos.length; i++)
        if (claves.contains(todos[i].clave)) i,
    ];
    for (var j = 0; j < posiciones.length; j++) {
      todos[posiciones[j]] = col[j];
    }
    _aplicar(_datos.copyWith(salones: todos));
  }

  String? renombrarBloque(String viejo, String nuevo) {
    final n = nuevo.trim();
    if (n.isEmpty) return 'Escribe el nombre del bloque.';
    if (n != viejo && _datos.bloques.any((b) => b.toLowerCase() == n.toLowerCase())) {
      return 'Ya existe un bloque con ese nombre.';
    }
    if (bloqueSel == viejo) bloqueSel = n;
    _aplicar(_datos.copyWith(
      salones: [for (final s in _datos.salones) s.edificio == viejo ? s.copyWith(edificio: n) : s],
    ));
    return null;
  }

  /// Guarda textos y valores de la app (título, pisos, velocidad, acceso…).
  void fijarAjustes(Map<String, dynamic> cambios) {
    _aplicar(_datos.copyWith(ajustes: {..._datos.ajustes, ...cambios}));
  }

  /// Carga los salones del catálogo inicial. Devuelve los bloques cargados.
  List<String> cargarCatalogo() {
    final r = catalogoInicial(_datos);
    if (r.aplicados.isNotEmpty) {
      verticeSel = null;
      _aplicar(r.datos);
    }
    return r.aplicados;
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
    if (hayBloqueSel) {
      final pts = List<Offset>.of(contornoSel(imagen));
      if (pts.length <= 3 || v >= pts.length) return;
      pts.removeAt(v);
      verticeSel = null;
      _guardarPoligono(imagen, pts);
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
    for (final b in _datos.bloques) {
      final cont = contornoDeBloque(_datos.salonesDe(b), true);
      if (cont.length < 3) {
        out.add('El bloque $b no tiene contorno dibujado.');
        continue;
      }
      final (d, g) = cercano(limitesDe(cont));
      if (g != gOrigen) {
        out.add('El bloque $b: la ruta más cercana no está conectada con el acceso principal.');
      } else if (d * mpp > 25) {
        out.add('El bloque $b queda a ${(d * mpp).round()} m de la ruta más cercana.');
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

    // Bloque elegido: esquinas grandes y puntos medios.
    if (hayBloqueSel) {
      final pts = contornoSel(imagen);
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

/// Datos de un salón ya creado (nombre, piso, columna, tipo, descripción y el
/// "Cómo llegar"). Devuelve null si se cancela; el contorno es el mismo.
Future<Salon?> pedirDatosSalon(BuildContext context, {required Salon base}) {
  return showDialog<Salon>(
    context: context,
    builder: (ctx) => _DialogoSalon(base: base),
  );
}

class _DialogoSalon extends StatefulWidget {
  const _DialogoSalon({required this.base});
  final Salon base;

  @override
  State<_DialogoSalon> createState() => _DialogoSalonState();
}

class _DialogoSalonState extends State<_DialogoSalon> {
  late final TextEditingController _numero = TextEditingController(text: widget.base.numero);
  late final TextEditingController _piso = TextEditingController(text: '${widget.base.piso}');
  late final TextEditingController _columna =
      TextEditingController(text: widget.base.columna >= 0 ? '${widget.base.columna + 1}' : '');
  late final TextEditingController _tipo = TextEditingController(text: widget.base.tipo);
  late final TextEditingController _desc = TextEditingController(text: widget.base.descripcion);
  late final TextEditingController _ind = TextEditingController(text: widget.base.indicaciones.join('\n'));

  @override
  void dispose() {
    _numero.dispose();
    _piso.dispose();
    _columna.dispose();
    _tipo.dispose();
    _desc.dispose();
    _ind.dispose();
    super.dispose();
  }

  void _guardar() {
    final b = widget.base;
    final tipo = _tipo.text.trim();
    final col = int.tryParse(_columna.text.trim());
    Navigator.pop(
      context,
      b.copyWith(
        numero: _numero.text.trim(),
        piso: int.tryParse(_piso.text.trim()) ?? b.piso,
        columna: col == null ? b.columna : math.max(0, col - 1),
        tipo: tipo.isEmpty ? 'Aula' : tipo,
        descripcion: _desc.text.trim(),
        indicaciones: [
          for (final l in _ind.text.split('\n'))
            if (l.trim().isNotEmpty) l.trim(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Salón de ${widget.base.edificio}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _numero, decoration: const InputDecoration(labelText: 'Nombre o número (ej. 205, L03, Room 1)')),
            TextField(
              controller: _piso,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Piso (1 = planta baja, 2 = planta alta)'),
            ),
            TextField(
              controller: _columna,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Columna dentro del bloque (1, 2, 3…)'),
            ),
            TextField(controller: _tipo, decoration: const InputDecoration(labelText: 'Tipo (Aula, Laboratorio, Oficina…)')),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
            TextField(
              controller: _ind,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Cómo llegar (una indicación por renglón)',
                helperText: 'Si lo dejas vacío, la app genera las indicaciones sola.',
                helperMaxLines: 2,
              ),
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

// ----------------------------------------------------------------- nuevo bloque
class ColumnaForm {
  ColumnaForm({this.piso = 1, this.texto = ''});
  int piso;
  String texto;
}

class FormBloque {
  FormBloque({this.nombre = '', List<ColumnaForm>? columnas}) : columnas = columnas ?? [ColumnaForm()];
  String nombre;
  List<ColumnaForm> columnas;
}

Future<FormBloque?> pedirFormBloque(
  BuildContext context, {
  required String Function(int) nombrePiso,
  FormBloque? inicial,
}) {
  return showDialog<FormBloque>(
    context: context,
    builder: (_) => _DialogoBloque(nombrePiso: nombrePiso, inicial: inicial),
  );
}

class _DialogoBloque extends StatefulWidget {
  const _DialogoBloque({required this.nombrePiso, this.inicial});
  final String Function(int) nombrePiso;
  final FormBloque? inicial;

  @override
  State<_DialogoBloque> createState() => _DialogoBloqueState();
}

class _DialogoBloqueState extends State<_DialogoBloque> {
  late final TextEditingController _nombre = TextEditingController(text: widget.inicial?.nombre ?? '');
  final List<TextEditingController> _textos = <TextEditingController>[];
  final List<TextEditingController> _descartados = <TextEditingController>[];
  final List<int> _pisos = <int>[];

  @override
  void initState() {
    super.initState();
    final cols = widget.inicial?.columnas ?? [ColumnaForm()];
    for (final c in cols) {
      _textos.add(TextEditingController(text: c.texto));
      _pisos.add(c.piso);
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    for (final c in [..._textos, ..._descartados]) {
      c.dispose();
    }
    super.dispose();
  }

  void _agregarColumna() {
    setState(() {
      _textos.add(TextEditingController());
      _pisos.add(_pisos.isEmpty ? 1 : _pisos.last);
    });
  }

  void _quitarColumna(int i) {
    if (_textos.length <= 1) return;
    setState(() {
      _descartados.add(_textos.removeAt(i));
      _pisos.removeAt(i);
    });
  }

  void _guardar() {
    Navigator.pop(
      context,
      FormBloque(
        nombre: _nombre.text.trim(),
        columnas: [
          for (var i = 0; i < _textos.length; i++) ColumnaForm(piso: _pisos[i], texto: _textos[i].text),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Nuevo bloque'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre del bloque (ej. Centro de Cómputo)'),
              ),
              const SizedBox(height: 14),
              Text('Columnas de salones', style: tema.titleSmall),
              const SizedBox(height: 2),
              Text(
                'Cada columna es una fila de salones a lo largo del edificio, de arriba hacia abajo. '
                'Sepáralos con comas; acepta rangos como 101-106 o E01-E03.',
                style: tema.bodySmall,
              ),
              for (var i = 0; i < _textos.length; i++) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Columna ${i + 1} · ', style: tema.labelLarge),
                    DropdownButton<int>(
                      value: _pisos[i],
                      onChanged: (v) => setState(() => _pisos[i] = v ?? 1),
                      items: [
                        for (final p in const [1, 2]) DropdownMenuItem(value: p, child: Text(widget.nombrePiso(p))),
                      ],
                    ),
                    const Spacer(),
                    if (_textos.length > 1)
                      IconButton(
                        tooltip: 'Quitar columna',
                        onPressed: () => _quitarColumna(i),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                TextField(
                  controller: _textos[i],
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Ej. L01, L02, L03  o  1-4, E17, Baños',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _agregarColumna,
                icon: const Icon(Icons.add),
                label: const Text('Agregar otra columna'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Crear bloque')),
      ],
    );
  }
}

/// Pide los datos del bloque recién dibujado y lo crea con todos sus salones.
/// Si hay un error (nombre repetido, sin salones…) vuelve a preguntar con lo
/// que ya se escribió; si se cancela, el contorno se conserva.
Future<void> crearSalonDibujado(BuildContext context, EditorMapa editor) async {
  var form = await pedirFormBloque(context, nombrePiso: editor.datos.nombrePiso);
  while (form != null) {
    final nombre = form.nombre.trim();
    final salones = <Salon>[];
    for (var k = 0; k < form.columnas.length; k++) {
      final c = form.columnas[k];
      for (final n in expandirSalones(c.texto)) {
        salones.add(Salon(numero: n, edificio: nombre, piso: c.piso, columna: k, tipo: tipoSugerido(n)));
      }
    }
    final error = editor.crearBloque(nombre, salones);
    if (error == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    form = await pedirFormBloque(context, nombrePiso: editor.datos.nombrePiso, inicial: form);
  }
}

// ------------------------------------------------------------ nombre del bloque
Future<void> editarNombreBloque(BuildContext context, EditorMapa editor, String actual) async {
  var texto = actual;
  while (true) {
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoNombre(inicial: texto),
    );
    if (nuevo == null || nuevo.trim() == actual) return;
    final error = editor.renombrarBloque(actual, nuevo);
    if (error == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    texto = nuevo;
  }
}

class _DialogoNombre extends StatefulWidget {
  const _DialogoNombre({required this.inicial});
  final String inicial;

  @override
  State<_DialogoNombre> createState() => _DialogoNombreState();
}

class _DialogoNombreState extends State<_DialogoNombre> {
  late final TextEditingController _c = TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nombre del bloque'),
      content: TextField(
        controller: _c,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre (ej. Edificio 1)'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Guardar')),
      ],
    );
  }
}

// ------------------------------------------------------------ salones del bloque
Future<void> gestionarSalones(BuildContext context, EditorMapa editor, String bloque) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoSalones(editor: editor, bloque: bloque),
  );
}

class _DialogoSalones extends StatefulWidget {
  const _DialogoSalones({required this.editor, required this.bloque});
  final EditorMapa editor;
  final String bloque;

  @override
  State<_DialogoSalones> createState() => _DialogoSalonesState();
}

class _DialogoSalonesState extends State<_DialogoSalones> {
  final Map<int, TextEditingController> _campos = <int, TextEditingController>{};
  final TextEditingController _nuevoTexto = TextEditingController();
  int _nuevoPiso = 1;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    // Los bloques viejos no tienen columnas: se les asigna una por piso.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.editor.normalizarColumnas(widget.bloque));
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    _nuevoTexto.dispose();
    super.dispose();
  }

  TextEditingController _campo(int k) => _campos.putIfAbsent(k, () => TextEditingController());

  void _agregar(TextEditingController c, int piso, int columna) {
    final nombres = expandirSalones(c.text);
    if (nombres.isEmpty) return;
    final r = widget.editor.agregarSalones(widget.bloque, piso, columna, nombres);
    c.clear();
    setState(() {
      _mensaje = r.omitidos == 0
          ? 'Se agregaron ${r.agregados} salones.'
          : 'Se agregaron ${r.agregados}; ${r.omitidos} ya existían.';
    });
  }

  Future<void> _editar(Salon s) async {
    final nuevo = await pedirDatosSalon(context, base: s);
    if (nuevo == null) return;
    final error = widget.editor.actualizarSalon(s.clave, nuevo);
    if (error != null) setState(() => _mensaje = error);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Salones de ${widget.bloque}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListenableBuilder(
          listenable: widget.editor,
          builder: (context, _) {
            final salones = widget.editor.datos.salonesDe(widget.bloque);
            if (salones.isEmpty) return const Text('Este bloque ya no tiene salones.');
            final cols = columnasDeBloque(salones);
            return ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Arrastra para cambiar el orden: el primero queda arriba en el mapa.',
                  style: tema.bodySmall,
                ),
                for (var k = 0; k < cols.length; k++) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 4),
                    child: Text(
                      'Columna ${k + 1} · ${widget.editor.datos.nombrePiso(cols[k].first.piso)} · ${cols[k].length} salones',
                      style: tema.titleSmall,
                    ),
                  ),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (a, b) {
                      if (b > a) b -= 1;
                      widget.editor.reordenarEnColumna(widget.bloque, k, a, b);
                    },
                    children: [
                      for (final s in cols[k])
                        ListTile(
                          key: ValueKey(s.clave),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.numero),
                          subtitle: Text(
                            s.indicaciones.isEmpty ? s.tipo : '${s.tipo} · con indicaciones propias',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _editar(s),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                onPressed: () => widget.editor.eliminarSalon(s.clave),
                                icon: const Icon(Icons.delete_outline, size: 20),
                              ),
                              const SizedBox(width: 28),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _campo(k),
                          decoration: const InputDecoration(hintText: 'Agregar a esta columna (ej. 101-106, Baños)'),
                          onSubmitted: (_) => _agregar(
                            _campo(k),
                            cols[k].first.piso,
                            cols[k].first.columna >= 0 ? cols[k].first.columna : k,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Agregar',
                        onPressed: () => _agregar(
                          _campo(k),
                          cols[k].first.piso,
                          cols[k].first.columna >= 0 ? cols[k].first.columna : k,
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 28),
                Text('Nueva columna', style: tema.titleSmall),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: _nuevoPiso,
                      onChanged: (v) => setState(() => _nuevoPiso = v ?? 1),
                      items: [
                        for (final p in const [1, 2])
                          DropdownMenuItem(value: p, child: Text(widget.editor.datos.nombrePiso(p))),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _nuevoTexto,
                        decoration: const InputDecoration(hintText: 'Salones (ej. 9-12, Baños)'),
                        onSubmitted: (_) => _agregar(_nuevoTexto, _nuevoPiso, widget.editor.siguienteColumna(widget.bloque)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Agregar columna',
                      onPressed: () => _agregar(_nuevoTexto, _nuevoPiso, widget.editor.siguienteColumna(widget.bloque)),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                if (_mensaje != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_mensaje!, style: tema.bodySmall),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
    );
  }
}

// ------------------------------------------------------------------- ajustes
/// Textos y valores de la app. Devuelve solo los campos que se pudieron leer.
Future<Map<String, dynamic>?> pedirAjustes(BuildContext context, DatosMapa datos) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _DialogoAjustes(datos: datos),
  );
}

class _DialogoAjustes extends StatefulWidget {
  const _DialogoAjustes({required this.datos});
  final DatosMapa datos;

  @override
  State<_DialogoAjustes> createState() => _DialogoAjustesState();
}

class _DialogoAjustesState extends State<_DialogoAjustes> {
  late final TextEditingController _titulo = TextEditingController(text: widget.datos.titulo);
  late final TextEditingController _subtitulo = TextEditingController(text: widget.datos.subtitulo);
  late final TextEditingController _baja = TextEditingController(text: widget.datos.nombrePiso(1));
  late final TextEditingController _alta = TextEditingController(text: widget.datos.nombrePiso(2));
  late final TextEditingController _velocidad =
      TextEditingController(text: widget.datos.metrosPorMinuto.toStringAsFixed(0));
  late final TextEditingController _lat = TextEditingController(text: widget.datos.accesoLat.toString());
  late final TextEditingController _lng = TextEditingController(text: widget.datos.accesoLng.toString());

  @override
  void dispose() {
    for (final c in [_titulo, _subtitulo, _baja, _alta, _velocidad, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _guardar() {
    final r = <String, dynamic>{
      'titulo': _titulo.text.trim(),
      'subtitulo': _subtitulo.text.trim(),
      'pisoBaja': _baja.text.trim(),
      'pisoAlta': _alta.text.trim(),
    };
    final v = _num(_velocidad);
    final la = _num(_lat);
    final ln = _num(_lng);
    if (v != null) r['metrosPorMinuto'] = v;
    if (la != null) r['accesoLat'] = la;
    if (ln != null) r['accesoLng'] = ln;
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Textos y ajustes de la app'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _titulo, decoration: const InputDecoration(labelText: 'Título de la pantalla de inicio')),
            TextField(controller: _subtitulo, decoration: const InputDecoration(labelText: 'Subtítulo')),
            TextField(controller: _baja, decoration: const InputDecoration(labelText: 'Nombre del piso 1')),
            TextField(controller: _alta, decoration: const InputDecoration(labelText: 'Nombre del piso 2')),
            TextField(
              controller: _velocidad,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Velocidad al caminar (metros por minuto)'),
            ),
            const SizedBox(height: 14),
            Text('Acceso principal (donde empiezan las rutas)', style: tema.titleSmall),
            TextField(
              controller: _lat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Latitud'),
            ),
            TextField(
              controller: _lng,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Longitud'),
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
                _chipHerramienta(Herramienta.nuevoSalon, Icons.crop_square, 'Nuevo bloque'),
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
            PopupMenuItem(value: 'ajustes', child: Text('Textos y ajustes de la app')),
            PopupMenuItem(value: 'catalogo', child: Text('Cargar catálogo inicial (Cómputo, Idiomas, Industrial)')),
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
              ? 'Toca una esquina del bloque.'
              : (n == 1 ? 'Toca la esquina opuesta.' : 'Contorno listo.');
        } else {
          pista = '$n punto${n == 1 ? '' : 's'}: toca cada esquina del bloque.';
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
        if (editor.hayBloqueSel) return _contextoBloque(context, estilo);
        final cam = editor.caminoSeleccionado;
        if (cam != null) return _contextoRuta(cam, estilo);
        return Text('Toca un bloque o una ruta para editarlo.', style: estilo);
    }
  }

  Widget _contextoBloque(BuildContext context, TextStyle estilo) {
    final nombre = editor.bloqueSel!;
    final salones = editor.salonesSel;
    final propio = editor.contornoPropio(imagen);
    final v = editor.verticeSel;
    final pts = editor.contornoSel(imagen);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$nombre · ${salones.length} salones', style: estilo.copyWith(fontWeight: FontWeight.w700)),
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
          FilledButton.tonalIcon(
            onPressed: () => gestionarSalones(context, editor, nombre),
            icon: const Icon(Icons.meeting_room_outlined, size: 18),
            label: const Text('Salones'),
          ),
          TextButton.icon(
            onPressed: () => editarNombreBloque(context, editor, nombre),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Nombre'),
          ),
          TextButton.icon(
            onPressed: () => _confirmar(
              context,
              '¿Eliminar el bloque $nombre y sus ${salones.length} salones?',
              editor.eliminarBloqueSeleccionado,
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Eliminar bloque'),
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
      case 'ajustes':
        final aj = await pedirAjustes(context, editor.datos);
        if (aj == null) return;
        editor.fijarAjustes(aj);
        messenger.showSnackBar(
          const SnackBar(content: Text('Ajustes guardados. Publica para que lleguen a los usuarios.')),
        );
      case 'catalogo':
        if (!context.mounted) return;
        await _confirmar(
          context,
          '¿Cargar los salones del catálogo (Centro de Cómputo, Centro de Idiomas y Edificio Industrial)? '
          'Reemplaza los salones registrados de esos edificios.',
          () {
            final aplicados = editor.cargarCatalogo();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  aplicados.isEmpty
                      ? 'No encontré esos edificios. Su nombre registrado debe incluir "cómputo", "idiomas" o "industrial".'
                      : 'Cargado: ${aplicados.join(', ')}. Revisa y publica.',
                ),
              ),
            );
          },
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
