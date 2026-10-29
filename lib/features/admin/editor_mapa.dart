import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:orienta_tec/app/theme/tema_app.dart';
import 'package:orienta_tec/core/catalogo_campus.dart';
import 'package:orienta_tec/core/iconos_salon.dart';
import 'package:orienta_tec/core/mapa_datos.dart';
import 'package:orienta_tec/core/mapa_repositorio.dart';

enum Herramienta { editar, nuevoSalon, nuevoPin, nuevaRuta }

enum ResultadoToque { nada, salonTerminado, pinColocado }

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

  /// Llave del bloque elegido (no su nombre: varios bloques pueden llamarse igual).
  String? bloqueSel;

  /// Lugar donde se tocó para un pin nuevo (falta pedir su nombre y tipo).
  Offset? pinPendiente;

  /// true = el próximo toque en el mapa mueve el pin elegido.
  bool moviendoPin = false;
  int? caminoSel;
  int? verticeSel;

  List<Salon> get salonesSel {
    final b = bloqueSel;
    return b == null ? const <Salon>[] : _datos.salonesDe(b);
  }

  bool get hayBloqueSel => salonesSel.isNotEmpty;

  /// ¿Lo elegido es un pin (y no un bloque)?
  bool get pinSel => salonesSel.length == 1 && salonesSel.first.pin;

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
    pinPendiente = null;
    moviendoPin = false;
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
    moviendoPin = false;
    bloqueSel = nombre;
    caminoSel = null;
    verticeSel = null;
    trazo.clear();
    notifyListeners();
  }

  void deseleccionar() {
    moviendoPin = false;
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
      case Herramienta.nuevoPin:
        pinPendiente = redondear(p);
        notifyListeners();
        return ResultadoToque.pinColocado;
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
          x.bloque == b
              ? (imagen ? x.copyWith(poligonoImagen: pts) : x.copyWith(poligonoMapa: pts))
              : x,
      ],
    ));
  }

  void _tocarEditar(Offset p, bool imagen, double radio) {
    final rh = radio * 1.2;

    // --- Pin elegido y en modo "mover": el toque es su nuevo lugar.
    if (pinSel && moviendoPin) {
      final b = bloqueSel!;
      final cuadro = cuadroDePin(p);
      moviendoPin = false;
      _aplicar(_datos.copyWith(
        salones: [
          for (final x in _datos.salones)
            x.bloque == b ? x.copyWith(poligonoImagen: cuadro, poligonoMapa: cuadro) : x,
        ],
      ));
      return;
    }

    // --- Bloque elegido: mover / agregar puntos del contorno.
    if (hayBloqueSel && !pinSel) {
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
    moviendoPin = false;
    for (final s in _datos.salones) {
      if (s.pin && (s.centro - p).distance <= rh) {
        bloqueSel = s.bloque;
        caminoSel = null;
        notifyListeners();
        return;
      }
    }
    for (final s in _datos.salones) {
      if (s.pin) continue;
      final pts = imagen ? s.esquinasImagen : s.esquinasMapa;
      if (puntoCercaDePoligono(p, pts)) {
        bloqueSel = s.bloque;
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
    if (salones.isEmpty) return 'Agrega al menos un salón.';
    if (trazo.length < 3) return 'Falta dibujar el contorno.';
    final poly = List<Offset>.of(trazo);
    // Llave propia: así puede haber varios bloques con el mismo nombre.
    final bid = nuevoBid();
    final nuevos = [
      for (final s in salones)
        s.copyWith(
          edificio: b,
          bid: bid,
          sid: s.sid.isEmpty ? nuevoBid() : s.sid,
          poligonoImagen: _dibujoImagen ? poly : const <Offset>[],
          poligonoMapa: _dibujoImagen ? const <Offset>[] : poly,
        ),
    ];
    trazo.clear();
    herramienta = Herramienta.editar;
    bloqueSel = bid;
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
          s.bloque == bloque ? s.copyWith(columna: asignada[s.clave]) : s,
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
    // Un mismo nombre puede repetirse en otro piso o columna del bloque
    // (ej. Baños en planta baja y en planta alta); solo se omite si ya está
    // en ese mismo piso y esa misma columna.
    final existentes = {
      for (final s in ref)
        if (s.piso == piso && s.columna == columna) s.numero.toLowerCase(),
    };
    final polImagen = contornoDeBloque(ref, true, propio: true);
    final polMapa = contornoDeBloque(ref, false, propio: true);
    final nombreB = _datos.nombreBloque(bloque);
    final bidRef = ref.isNotEmpty ? ref.first.bid : '';
    final soloRef = ref.isNotEmpty && ref.first.soloNombre;
    final nuevos = <Salon>[];
    var omitidos = 0;
    for (final n in nombres) {
      if (!existentes.add(n.toLowerCase())) {
        omitidos++;
        continue;
      }
      nuevos.add(Salon(
        numero: n,
        edificio: nombreB,
        bid: bidRef,
        sid: nuevoBid(),
        soloNombre: soloRef,
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
    // Los salones viejos se identificaban por su nombre; al renombrarlos reciben
    // un identificador propio para no chocar con otro salón del mismo nombre.
    final original = _datos.salones.firstWhere((s) => s.clave == claveOriginal, orElse: () => nuevo);
    final cambio = nuevo.copyWith(
      numero: numero,
      sid: nuevo.sid.isEmpty && numero != original.numero ? nuevoBid() : nuevo.sid,
    );
    _aplicar(_datos.copyWith(
      salones: [for (final s in _datos.salones) s.clave == claveOriginal ? cambio : s],
    ));
    return null;
  }

  void eliminarSalon(String clave) {
    verticeSel = null;
    final restantes = [for (final s in _datos.salones) if (s.clave != clave) s];
    final b = bloqueSel;
    if (b != null && !restantes.any((s) => s.bloque == b)) bloqueSel = null;
    _aplicar(_datos.copyWith(salones: restantes));
  }

  void eliminarBloqueSeleccionado() {
    final b = bloqueSel;
    if (b == null) return;
    bloqueSel = null;
    verticeSel = null;
    _aplicar(_datos.copyWith(salones: [for (final s in _datos.salones) if (s.bloque != b) s]));
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

  /// Cambia el nombre que se muestra del bloque con la llave [llave].
  /// La llave no cambia, así que las fotos y rutas de sus salones se conservan.
  String? renombrarBloque(String llave, String nuevo) {
    final n = nuevo.trim();
    if (n.isEmpty) return 'Escribe el nombre del bloque.';
    _aplicar(_datos.copyWith(
      salones: [
        for (final s in _datos.salones)
          s.bloque == llave ? s.copyWith(edificio: n, bid: s.bid.isEmpty ? llave : s.bid) : s,
      ],
    ));
    return null;
  }

  /// Muestra todos los salones del bloque solo con su nombre (sin "Salón").
  void fijarSoloNombre(String llave, bool valor) {
    _aplicar(_datos.copyWith(
      salones: [
        for (final s in _datos.salones) s.bloque == llave ? s.copyWith(soloNombre: valor) : s,
      ],
    ));
  }

  // ------------------------------------------------------------------ pines
  void cancelarPin() {
    pinPendiente = null;
    notifyListeners();
  }

  /// Crea el pin en el lugar que se tocó.
  String? agregarPin(String nombre, String tipo) {
    final n = nombre.trim();
    final pos = pinPendiente;
    if (n.isEmpty) return 'Escribe el nombre del pin.';
    if (pos == null) return 'Toca el mapa para colocar el pin.';
    final pin = crearPin(n, tipo, pos);
    pinPendiente = null;
    herramienta = Herramienta.editar;
    bloqueSel = pin.bloque;
    caminoSel = null;
    verticeSel = null;
    _aplicar(_datos.copyWith(salones: [..._datos.salones, pin]));
    return null;
  }

  String? editarPin(String llave, String nombre, String tipo) {
    final n = nombre.trim();
    if (n.isEmpty) return 'Escribe el nombre del pin.';
    _aplicar(_datos.copyWith(
      salones: [
        for (final s in _datos.salones) s.bloque == llave ? s.copyWith(numero: n, edificio: n, tipo: tipo) : s,
      ],
    ));
    return null;
  }

  void iniciarMoverPin() {
    moviendoPin = true;
    notifyListeners();
  }

  void cancelarMoverPin() {
    moviendoPin = false;
    notifyListeners();
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
      final nb = _datos.nombreBloque(b);
      final cont = contornoDeBloque(_datos.salonesDe(b), true);
      if (cont.length < 3) {
        out.add('El bloque $nb no tiene contorno dibujado.');
        continue;
      }
      final (d, g) = cercano(limitesDe(cont));
      if (g != gOrigen) {
        out.add('El bloque $nb: la ruta más cercana no está conectada con el acceso principal.');
      } else if (d * mpp > 25) {
        out.add('El bloque $nb queda a ${(d * mpp).round()} m de la ruta más cercana.');
      }
    }
    for (final pin in _datos.pines) {
      final (d, g) = cercano(Rect.fromLTWH(pin.centro.dx, pin.centro.dy, 0, 0));
      if (g != gOrigen) {
        out.add('El pin ${pin.numero}: la ruta más cercana no está conectada con el acceso principal.');
      } else if (d * mpp > 25) {
        out.add('El pin ${pin.numero} queda a ${(d * mpp).round()} m de la ruta más cercana.');
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

    // Pin nuevo (esperando nombre) y pin elegido.
    final pend = pinPendiente;
    if (pend != null) marcas.add(_marcador(aLatLng(pend), 22, _verdeEd, Colors.white, grosor: 3));
    if (pinSel) {
      marcas.add(_marcador(aLatLng(salonesSel.first.centro), 40, Colors.transparent, moviendoPin ? _rosaEd : _cianEd, grosor: 4));
    }

    // Bloque elegido: esquinas grandes y puntos medios.
    if (hayBloqueSel && !pinSel) {
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
  late bool _solo = widget.base.soloNombre;
  late String _icono = widget.base.icono;
  late String _iconoMapa = widget.base.iconoMapa;

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

  List<DropdownMenuItem<String>> _itemsIcono(String auto, String ninguno) => [
        DropdownMenuItem(value: '', child: Text(auto)),
        DropdownMenuItem(value: iconoSoloTexto, child: Text(ninguno)),
        for (final o in opcionesIcono)
          DropdownMenuItem(
            value: o.clave,
            child: Row(children: [Icon(o.icono, size: 20), const SizedBox(width: 10), Text(o.nombre)]),
          ),
      ];

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
        soloNombre: _solo,
        icono: _icono,
        iconoMapa: _iconoMapa,
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
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _icono,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ícono de la miniatura',
                helperText: 'Se ve en el buscador, en las listas y en la ficha del salón.',
                helperMaxLines: 2,
              ),
              items: _itemsIcono('Automático (según el tipo)', 'Sin ícono (mostrar el nombre o número)'),
              onChanged: (v) => setState(() => _icono = v ?? ''),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _iconoMapa,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ícono sobre el mapa',
                helperText: 'Se ve dentro de la cajita al acercar el mapa. Automático: solo oficinas, cafetería, biblioteca, auditorio y baños.',
                helperMaxLines: 3,
              ),
              items: _itemsIcono('Automático', 'Número o nombre (sin ícono)'),
              onChanged: (v) => setState(() => _iconoMapa = v ?? ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar solo el nombre'),
              subtitle: const Text('Sin la palabra "Salón" (ej. Biblioteca, Baños)'),
              value: _solo,
              onChanged: (v) => setState(() => _solo = v),
            ),
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
  FormBloque({this.nombre = '', this.soloNombre = false, List<ColumnaForm>? columnas})
      : columnas = columnas ?? [ColumnaForm()];
  String nombre;
  bool soloNombre;
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
  late bool _solo = widget.inicial?.soloNombre ?? false;

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
        soloNombre: _solo,
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar solo el nombre'),
                subtitle: const Text('Para lugares que no son un salón (Biblioteca, Cafetería, Baños). Puede repetirse el nombre.'),
                value: _solo,
                onChanged: (v) => setState(() => _solo = v),
              ),
              const SizedBox(height: 8),
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
        salones.add(Salon(numero: n, edificio: nombre, piso: c.piso, columna: k, tipo: tipoSugerido(n), soloNombre: form.soloNombre));
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
Future<void> editarNombreBloque(BuildContext context, EditorMapa editor, String llave) async {
  final actual = editor.datos.nombreBloque(llave);
  final nuevo = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoNombre(inicial: actual),
  );
  if (nuevo == null || nuevo.trim() == actual) return;
  final error = editor.renombrarBloque(llave, nuevo);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
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
      title: Text('Salones de ${widget.editor.datos.nombreBloque(widget.bloque)}'),
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

// ------------------------------------------------------------------- pines
/// Pide nombre y tipo del pin que se acaba de tocar en el mapa.
Future<void> colocarPin(BuildContext context, EditorMapa editor) async {
  var inicial = ('', tiposPin.first);
  while (true) {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _DialogoPin(titulo: 'Nuevo pin', nombre: inicial.$1, tipo: inicial.$2),
    );
    if (r == null) {
      editor.cancelarPin();
      return;
    }
    final error = editor.agregarPin(r.$1, r.$2);
    if (error == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    inicial = r;
  }
}

Future<void> editarPinDialogo(BuildContext context, EditorMapa editor, Salon pin) async {
  final r = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _DialogoPin(titulo: 'Editar pin', nombre: pin.numero, tipo: pin.tipo),
  );
  if (r == null) return;
  final error = editor.editarPin(pin.bloque, r.$1, r.$2);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}

class _DialogoPin extends StatefulWidget {
  const _DialogoPin({required this.titulo, required this.nombre, required this.tipo});
  final String titulo;
  final String nombre;
  final String tipo;

  @override
  State<_DialogoPin> createState() => _DialogoPinState();
}

class _DialogoPinState extends State<_DialogoPin> {
  late final TextEditingController _nombre = TextEditingController(text: widget.nombre);
  late String _tipo = widget.tipo;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tipos = tiposPin.contains(_tipo) ? tiposPin : [...tiposPin, _tipo];
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nombre,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre (ej. Entrada principal, Cancha de futbol)'),
          ),
          const SizedBox(height: 14),
          DropdownButton<String>(
            value: _tipo,
            isExpanded: true,
            onChanged: (v) => setState(() => _tipo = v ?? _tipo),
            items: [for (final t in tipos) DropdownMenuItem(value: t, child: Text(t))],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, (_nombre.text, _tipo)), child: const Text('Guardar')),
      ],
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
  late final TextEditingController _aviso = TextEditingController(text: widget.datos.aviso);
  late final TextEditingController _lat = TextEditingController(text: widget.datos.accesoLat.toString());
  late final TextEditingController _lng = TextEditingController(text: widget.datos.accesoLng.toString());

  @override
  void dispose() {
    for (final c in [_titulo, _subtitulo, _aviso, _baja, _alta, _velocidad, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _guardar() {
    final r = <String, dynamic>{
      'titulo': _titulo.text.trim(),
      'subtitulo': _subtitulo.text.trim(),
      'aviso': _aviso.text.trim(),
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
            TextField(
              controller: _aviso,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Aviso para los usuarios (opcional)',
                helperText: 'Ej. "Baños del edificio E cerrados hoy". Déjalo vacío para quitarlo.',
                helperMaxLines: 2,
              ),
            ),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        decoration: BoxDecoration(
          color: p.superficie,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26), bottom: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.oscuro ? 0.5 : 0.2),
              blurRadius: 26,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: p.divisor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            _encabezado(context, p),
            const SizedBox(height: 10),
            _herramientas(p),
            const SizedBox(height: 10),
            _contexto(context, p),
            const SizedBox(height: 10),
            _pie(context, p),
          ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ encabezado
  Widget _encabezado(BuildContext context, Paleta p) {
    final sucio = editor.sucio;
    final Color colorEstado = sucio ? _ambar : p.verde;
    final String estado = sucio
        ? 'Cambios sin publicar'
        : (repositorioMapa.remotoConfigurado ? 'Todo publicado' : 'Solo local (sin servidor)');
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: p.primario.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.admin_panel_settings_outlined, color: p.acento, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modo administrador', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.acento)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(sucio ? Icons.circle : Icons.check_circle, size: 11, color: colorEstado),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(estado, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.textoSec)),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '¿Cómo funciona?',
          onPressed: () => _ayuda(context),
          icon: const Icon(Icons.help_outline),
        ),
        IconButton(
          tooltip: 'Deshacer el último cambio',
          onPressed: editor.puedeDeshacer ? editor.deshacer : null,
          icon: const Icon(Icons.undo),
        ),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (v) => _menu(context, v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'revisar', child: _ItemMenu(Icons.fact_check_outlined, 'Revisar rutas y salones')),
            PopupMenuItem(value: 'ajustes', child: _ItemMenu(Icons.tune, 'Textos y ajustes de la app')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'catalogo', child: _ItemMenu(Icons.library_add_outlined, 'Cargar catálogo inicial')),
            PopupMenuItem(value: 'exportar', child: _ItemMenu(Icons.copy_all_outlined, 'Copiar respaldo (JSON)')),
            PopupMenuItem(value: 'importar', child: _ItemMenu(Icons.file_download_outlined, 'Importar respaldo (JSON)')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'descartar', child: _ItemMenu(Icons.restore, 'Descartar cambios y cargar lo publicado')),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------------- herramientas
  Widget _botonHerramienta(Paleta p, Herramienta h, IconData icono, String texto, String ayuda) {
    final sel = editor.herramienta == h;
    return Expanded(
      child: Tooltip(
        message: ayuda,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: sel ? p.primario.withValues(alpha: 0.16) : p.chip,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => editor.elegirHerramienta(h),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? p.primario : Colors.transparent, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icono, size: 22, color: sel ? p.acento : p.textoSec),
                    const SizedBox(height: 3),
                    Text(
                      texto,
                      style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? p.acento : p.textoSec),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _herramientas(Paleta p) {
    return Row(
      children: [
        _botonHerramienta(p, Herramienta.editar, Icons.touch_app_outlined, 'Editar', 'Elegir y modificar lo que ya existe'),
        _botonHerramienta(p, Herramienta.nuevoSalon, Icons.add_box_outlined, 'Bloque', 'Dibujar un edificio o bloque nuevo'),
        _botonHerramienta(p, Herramienta.nuevoPin, Icons.add_location_alt_outlined, 'Pin', 'Marcar una entrada, cancha, estacionamiento, área verde o punto de reunión'),
        _botonHerramienta(p, Herramienta.nuevaRuta, Icons.timeline, 'Ruta', 'Trazar un camino peatonal'),
      ],
    );
  }

  // ------------------------------------------------- tarjeta "qué hago ahora"
  Widget _tarjeta(
    Paleta p, {
    required IconData icono,
    required String titulo,
    required String texto,
    Widget? extra,
    List<Widget> acciones = const [],
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.primario.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(icono, size: 19, color: p.acento),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.texto)),
                    const SizedBox(height: 2),
                    Text(texto, style: TextStyle(fontSize: 13, height: 1.3, color: p.textoSec)),
                  ],
                ),
              ),
            ],
          ),
          if (extra != null) ...[const SizedBox(height: 8), extra],
          if (acciones.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: acciones),
          ],
        ],
      ),
    );
  }

  Widget _botonPeligro(BuildContext context, String texto, VoidCallback alPulsar) {
    final c = Theme.of(context).colorScheme.error;
    return TextButton.icon(
      onPressed: alPulsar,
      style: TextButton.styleFrom(foregroundColor: c),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text(texto),
    );
  }

  Widget _contexto(BuildContext context, Paleta p) {
    switch (editor.herramienta) {
      case Herramienta.nuevoSalon:
        final n = editor.trazo.length;
        final String paso;
        if (editor.rectangulo) {
          paso = n == 0
              ? 'Paso 1 de 2 · Toca una esquina del bloque.'
              : (n == 1 ? 'Paso 2 de 2 · Toca la esquina opuesta.' : 'Contorno listo · pulsa «Terminar» para escribir sus salones.');
        } else {
          paso = n < 3
              ? 'Toca cada esquina del bloque ($n de mínimo 3).'
              : '$n puntos · sigue tocando esquinas o pulsa «Terminar».';
        }
        return _tarjeta(
          p,
          icono: Icons.add_box_outlined,
          titulo: 'Dibujar un bloque nuevo',
          texto: '$paso\nDibujas sobre la vista ${imagen ? 'satélite' : 'de mapa'}.',
          extra: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Rectángulo (2 toques)'),
                selected: editor.rectangulo,
                onSelected: (_) => editor.alternarRectangulo(true),
              ),
              ChoiceChip(
                label: const Text('Polígono (varias esquinas)'),
                selected: !editor.rectangulo,
                onSelected: (_) => editor.alternarRectangulo(false),
              ),
            ],
          ),
          acciones: [
            if (editor.contornoListo)
              FilledButton.icon(
                onPressed: () => crearSalonDibujado(context, editor),
                icon: const Icon(Icons.check),
                label: const Text('Terminar'),
              ),
            if (!editor.rectangulo && n > 0)
              TextButton.icon(onPressed: editor.quitarUltimoPunto, icon: const Icon(Icons.backspace_outlined, size: 18), label: const Text('Quitar punto')),
            if (n > 0) TextButton(onPressed: editor.cancelarTrazo, child: const Text('Cancelar')),
          ],
        );
      case Herramienta.nuevoPin:
        return _tarjeta(
          p,
          icono: Icons.add_location_alt_outlined,
          titulo: 'Colocar un pin',
          texto: 'Toca en el mapa el punto exacto (entrada, cancha, estacionamiento…). Después te pediré su nombre y tipo.',
        );
      case Herramienta.nuevaRuta:
        final n = editor.trazo.length;
        return _tarjeta(
          p,
          icono: Icons.timeline,
          titulo: 'Trazar una ruta (camino peatonal)',
          texto: n == 0
              ? 'Paso 1 · Toca el mapa para marcar el inicio. Si tocas cerca de otra ruta, se conecta sola.'
              : '$n punto${n == 1 ? '' : 's'} · sigue tocando por donde se camina. Termina sobre otra ruta para conectarla.',
          acciones: [
            if (n >= 2)
              FilledButton.icon(onPressed: editor.terminarRuta, icon: const Icon(Icons.check), label: const Text('Terminar ruta')),
            if (n > 0)
              TextButton.icon(onPressed: editor.quitarUltimoPunto, icon: const Icon(Icons.backspace_outlined, size: 18), label: const Text('Quitar punto')),
            if (n > 0) TextButton(onPressed: editor.cancelarTrazo, child: const Text('Cancelar')),
          ],
        );
      case Herramienta.editar:
        if (editor.hayBloqueSel) return _contextoBloque(context, p);
        final cam = editor.caminoSeleccionado;
        if (cam != null) return _contextoRuta(context, p, cam);
        return _tarjeta(
          p,
          icono: Icons.touch_app_outlined,
          titulo: 'Toca algo para editarlo',
          texto: 'Un bloque (renombrarlo, editar sus salones o mover sus esquinas), un pin, o la línea de una ruta. '
              'Para agregar algo nuevo usa Bloque, Pin o Ruta.',
        );
    }
  }

  Widget _contextoPin(BuildContext context, Paleta p) {
    final pin = editor.salonesSel.first;
    if (editor.moviendoPin) {
      return _tarjeta(
        p,
        icono: Icons.open_with,
        titulo: 'Mover «${pin.numero}»',
        texto: 'Toca el mapa donde quieres colocarlo.',
        acciones: [TextButton(onPressed: editor.cancelarMoverPin, child: const Text('Cancelar'))],
      );
    }
    return _tarjeta(
      p,
      icono: Icons.place_outlined,
      titulo: 'Pin · ${pin.numero}',
      texto: 'Tipo: ${pin.tipo}.',
      acciones: [
        FilledButton.tonalIcon(
          onPressed: () => editarPinDialogo(context, editor, pin),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Editar'),
        ),
        TextButton.icon(onPressed: editor.iniciarMoverPin, icon: const Icon(Icons.open_with, size: 18), label: const Text('Mover')),
        _botonPeligro(
          context,
          'Eliminar',
          () => _confirmar(context, '¿Eliminar el pin ${pin.numero}?', editor.eliminarBloqueSeleccionado),
        ),
      ],
    );
  }

  Widget _contextoBloque(BuildContext context, Paleta p) {
    if (editor.pinSel) return _contextoPin(context, p);
    final llave = editor.bloqueSel!;
    final nombre = editor.datos.nombreBloque(llave);
    final salones = editor.salonesSel;
    final propio = editor.contornoPropio(imagen);
    final v = editor.verticeSel;
    final pts = editor.contornoSel(imagen);
    if (v != null) {
      return _tarjeta(
        p,
        icono: Icons.adjust,
        titulo: 'Moviendo una esquina de $nombre',
        texto: 'Toca el mapa donde debe quedar el punto.',
        acciones: [
          TextButton.icon(
            onPressed: pts.length > 3 ? () => editor.quitarVerticeElegido(imagen: imagen) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Quitar punto'),
          ),
          TextButton(onPressed: editor.cancelarVertice, child: const Text('Cancelar')),
        ],
      );
    }
    return _tarjeta(
      p,
      icono: Icons.apartment_outlined,
      titulo: '$nombre · ${salones.length} salones',
      texto: 'Toca un punto del contorno para moverlo, o un círculo vacío para agregar una esquina.'
          '${propio ? '' : '\nUsa el contorno de la otra vista; al moverlo se crea el de esta.'}',
      acciones: [
        FilledButton.icon(
          onPressed: () => gestionarSalones(context, editor, llave),
          icon: const Icon(Icons.meeting_room_outlined, size: 18),
          label: const Text('Salones'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => editarNombreBloque(context, editor, llave),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Nombre'),
        ),
        FilterChip(
          label: const Text('Solo nombre'),
          tooltip: 'Muestra "Biblioteca" en vez de "Salón Biblioteca"',
          selected: salones.every((s) => s.soloNombre),
          onSelected: (v) => editor.fijarSoloNombre(llave, v),
        ),
        _botonPeligro(
          context,
          'Eliminar bloque',
          () => _confirmar(context, '¿Eliminar el bloque $nombre y sus ${salones.length} salones?', editor.eliminarBloqueSeleccionado),
        ),
      ],
    );
  }

  Widget _contextoRuta(BuildContext context, Paleta p, List<Offset> cam) {
    final v = editor.verticeSel;
    if (v != null) {
      return _tarjeta(
        p,
        icono: Icons.adjust,
        titulo: 'Moviendo un punto de la ruta',
        texto: 'Toca el mapa donde debe quedar. También se mueve en las rutas que cruzan por ahí.',
        acciones: [
          TextButton.icon(
            onPressed: cam.length > 2 ? () => editor.quitarVerticeElegido(imagen: imagen) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Quitar punto'),
          ),
          TextButton(onPressed: editor.cancelarVertice, child: const Text('Cancelar')),
        ],
      );
    }
    return _tarjeta(
      p,
      icono: Icons.timeline,
      titulo: 'Ruta de ${cam.length} puntos',
      texto: 'Toca un punto para moverlo o un círculo vacío para agregar uno.',
      acciones: [
        _botonPeligro(context, 'Eliminar ruta', () => _confirmar(context, '¿Eliminar esta ruta completa?', editor.eliminarCaminoSeleccionado)),
      ],
    );
  }

  // ------------------------------------------------------------------- pie
  Widget _pie(BuildContext context, Paleta p) {
    final sucio = editor.sucio;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: sucio ? () => _publicar(context) : null,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
        icon: const Icon(Icons.cloud_upload_outlined),
        label: Text(sucio ? 'Publicar cambios para los usuarios' : 'Todo publicado'),
      ),
    );
  }

  // ------------------------------------------------------------------ ayuda
  Future<void> _ayuda(BuildContext context) {
    final p = Paleta.of(context);
    Widget item(IconData icono, String titulo, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: p.primario.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icono, size: 21, color: p.acento),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.texto)),
                    const SizedBox(height: 2),
                    Text(texto, style: TextStyle(fontSize: 13.5, height: 1.35, color: p.textoSec)),
                  ],
                ),
              ),
            ],
          ),
        );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.superficie,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: p.divisor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('¿Cómo funciona?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.acento)),
            const SizedBox(height: 4),
            Text(
              'Todo lo que hagas aquí se guarda en tu equipo. Los usuarios solo lo ven cuando pulses «Publicar».',
              style: TextStyle(fontSize: 13.5, height: 1.35, color: p.textoSec),
            ),
            const SizedBox(height: 18),
            item(Icons.touch_app_outlined, 'Editar',
                'Toca un bloque para renombrarlo, cambiar sus salones (nombre, piso, ícono, “Cómo llegar”) o mover sus esquinas. También sirve con pines y rutas.'),
            item(Icons.add_box_outlined, 'Bloque',
                'Dibuja un edificio: dos toques (rectángulo) o una esquina por toque (polígono). Al terminar escribe sus salones, por ejemplo «101-106, Baños, Oficina».'),
            item(Icons.add_location_alt_outlined, 'Pin',
                'Marca un lugar suelto: entrada, cancha, estacionamiento u otro. Se ve como un marcador y también se puede buscar.'),
            item(Icons.timeline, 'Ruta',
                'Traza por dónde se camina. Las rutas se conectan entre sí al tocar cerca de otra; los salones solo se alcanzan si hay un camino conectado a la entrada.'),
            item(Icons.fact_check_outlined, 'Revisar',
                'En el menú (⋮) usa «Revisar rutas y salones» antes de publicar: avisa de salones sin contorno o sin camino.'),
            item(Icons.layers_outlined, 'Mapa o satélite',
                'Dibujas sobre la vista que tengas activa (botón del globo). Cada vista guarda su propio contorno.'),
            item(Icons.undo, 'Deshacer',
                'La flecha ↶ regresa el último cambio. «Descartar cambios» (menú) vuelve a lo ya publicado.'),
            item(Icons.cloud_upload_outlined, 'Publicar',
                'Envía el mapa a los usuarios. El estado aparece arriba: naranja = cambios sin publicar, verde = todo publicado.'),
          ],
        ),
      ),
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

class _ItemMenu extends StatelessWidget {
  const _ItemMenu(this.icono, this.texto);
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icono, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(texto)),
        ],
      );
}
