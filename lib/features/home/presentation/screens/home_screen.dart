import 'dart:async';
import 'dart:math' as math;

import 'package:orienta_tec/core/servicio_actualizacion.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:orienta_tec/app/theme/tema_app.dart';
import 'package:orienta_tec/core/mapa_datos.dart';
import 'package:orienta_tec/core/mapa_repositorio.dart';
import 'package:orienta_tec/features/admin/editor_mapa.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Marca y constantes
// ---------------------------------------------------------------------------
const Color _azul = Color(0xFF1B396A);
const Color _cian = Color(0xFF00E5FF);
const Color _cianOscuro = Color(0xFF00A9C0);
const Color _casing = Color(0xFF0B2A5B);
const Color _usuarioAzul = Color(0xFF2F80ED);
const Color _rosa = Color(0xFFFF3366);

const String _claveCarto = '';

const String _urlTilesOsm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _urlTilesCarto =
    'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
const String _urlTiles = _claveCarto == ''
    ? _urlTilesOsm
    : '$_urlTilesCarto?key=$_claveCarto';
const String _textoAtribucion = _claveCarto == ''
    ? '© OpenStreetMap'
    : '© OpenStreetMap contributors, © CARTO';

// Mapa oscuro. Sin clave usa los mismos tiles de OpenStreetMap que el modo
// claro, invertidos y teñidos de azul marino (no necesita registro).
// Opcional: con una clave gratuita de MapTiler (maptiler.com) se usa su estilo
// oscuro real, con parques y agua de colores como Google Maps.
const String _claveMapTiler = '';
const String _urlTilesOscuro =
    'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}{r}.png?key=$_claveMapTiler';
const String _textoAtribucionOscuro = _claveMapTiler == ''
    ? '© OpenStreetMap'
    : '© MapTiler © OpenStreetMap contributors';

const String _paqueteApp = 'com.example.orienta_tec';
const String _rutaImagen = 'assets/images/campus_orizaba.png';

const LatLng _centroCampus = LatLng(18.8552, -97.0981);
const LatLng _accesoPrincipalGeo = LatLng(18.85472947868148, -97.09831297465401);

const double _imgW = 1407;
const double _imgH = 768;

const double _metrosPorPixel = 0.3;
const double _metrosPorMinuto = 80;
const double _umbralDesvioM = 25;
const double _radioLlegadaM = 12;

const Rect _zonaCampus = Rect.fromLTWH(-260, -260, _imgW + 520, _imgH + 520);
const double _zoomEtiquetas = 17.3;

// ---------------------------------------------------------------------------
// Calibración fija
// ---------------------------------------------------------------------------
class _ReferenciaEsquina {
  const _ReferenciaEsquina(this.px);
  final Offset px;
}

const List<_ReferenciaEsquina> _esquinasImagen = [
  _ReferenciaEsquina(Offset(0, 0)),
  _ReferenciaEsquina(Offset(_imgW, 0)),
  _ReferenciaEsquina(Offset(0, _imgH)),
  _ReferenciaEsquina(Offset(_imgW, _imgH)),
];

const List<List<double>> _calibracion = [
  [18.8559257, -97.1003893],
  [18.8571637, -97.0967997],
  [18.8541782, -97.0997915],
  [18.8555020, -97.0960564],
];

class _PuntoGeo {
  const _PuntoGeo(this.px, this.lat, this.lng);
  final Offset px;
  final double lat;
  final double lng;
}

class _GeoRef {
  _GeoRef._(
    this._lat0,
    this._lng0,
    this._mLng,
    this._p0,
    this._a,
    this._b,
    this._d,
    this._e,
    this.metrosPorPixel,
  );

  static const double _mLat = 110540;

  final double _lat0;
  final double _lng0;
  final double _mLng;
  final Offset _p0;
  final double _a;
  final double _b;
  final double _d;
  final double _e;
  final double metrosPorPixel;

  static _GeoRef? desdeValores(List<List<double>> v) {
    if (v.length < 4) return null;
    return desdePuntos([
      for (var i = 0; i < 4; i++)
        _PuntoGeo(_esquinasImagen[i].px, v[i][0], v[i][1]),
    ]);
  }

  static _GeoRef? desdePuntos(List<_PuntoGeo> pts) {
    if (pts.length < 4) return null;
    if (pts.any((p) => p.lat == 0 && p.lng == 0)) return null;

    final lat0 = pts[0].lat;
    final lng0 = pts[0].lng;
    final mLng = 111320 * math.cos(lat0 * math.pi / 180);

    double sumX = 0, sumY = 0, sumXX = 0, sumYY = 0, sumXY = 0;
    double sumDxX = 0, sumDxY = 0, sumDyX = 0, sumDyY = 0;

    for (var i = 0; i < 4; i++) {
      final x = (pts[i].lng - lng0) * mLng;
      final y = (pts[i].lat - lat0) * _mLat;
      final dx = pts[i].px.dx - pts[0].px.dx;
      final dy = pts[i].px.dy - pts[0].px.dy;

      sumX += x;
      sumY += y;
      sumXX += x * x;
      sumYY += y * y;
      sumXY += x * y;
      sumDxX += dx * x;
      sumDxY += dx * y;
      sumDyX += dy * x;
      sumDyY += dy * y;
    }

    final det = (sumXX * sumYY) - (sumXY * sumXY);
    if (det.abs() < 1e-5) return null;

    final a = (sumDxX * sumYY - sumDxY * sumXY) / det;
    final b = (sumDxY * sumXX - sumDxX * sumXY) / det;
    final d = (sumDyX * sumYY - sumDyY * sumXY) / det;
    final e = (sumDyY * sumXX - sumDyX * sumXY) / det;

    final pxPorMetro = math.sqrt((a * e - b * d).abs());
    if (pxPorMetro == 0) return null;

    return _GeoRef._(lat0, lng0, mLng, pts[0].px, a, b, d, e, 1 / pxPorMetro);
  }

  Offset aPlano(double lat, double lng) {
    final x = (lng - _lng0) * _mLng;
    final y = (lat - _lat0) * _mLat;
    return Offset(_p0.dx + _a * x + _b * y, _p0.dy + _d * x + _e * y);
  }

  LatLng aLatLng(Offset px) {
    final dx = px.dx - _p0.dx;
    final dy = px.dy - _p0.dy;
    final det = _a * _e - _b * _d;
    final x = (_e * dx - _b * dy) / det;
    final y = (_a * dy - _d * dx) / det;
    return LatLng(_lat0 + y / _mLat, _lng0 + x / _mLng);
  }
}

// ---------------------------------------------------------------------------
// Datos: Salones y Red de Caminos
// ---------------------------------------------------------------------------
class _Arista {
  const _Arista(this.a, this.b);
  final Offset a, b;
}

class _Hallazgo {
  const _Hallazgo(this.indice, this.punto, this.distancia);
  final int indice;
  final Offset punto;
  final double distancia;
}

class _Vecino {
  const _Vecino(this.nodo, this.peso);
  final int nodo;
  final double peso;
}

Offset _limitarARect(Offset p, Rect r) => Offset(
      p.dx.clamp(r.left, r.right).toDouble(),
      p.dy.clamp(r.top, r.bottom).toDouble(),
    );

class _Red {
  _Red(List<List<Offset>> caminos) {
    for (final c in caminos) {
      for (var i = 0; i < c.length - 1; i++) {
        _aristas.add(_Arista(c[i], c[i + 1]));
      }
    }
  }

  final List<_Arista> _aristas = [];

  _Hallazgo _masCercano(List<_Arista> aristas, Rect zona) {
    _Hallazgo? mejor;
    for (var i = 0; i < aristas.length; i++) {
      final e = aristas[i];
      final largo = (e.b - e.a).distance;
      final n = math.max(1, (largo / 5).ceil());
      for (var k = 0; k <= n; k++) {
        final p = Offset.lerp(e.a, e.b, k / n)!;
        final d = (p - _limitarARect(p, zona)).distance;
        if (mejor == null || d < mejor.distancia) {
          mejor = _Hallazgo(i, p, d);
        }
      }
    }
    return mejor!;
  }

  Offset _insertar(List<_Arista> aristas, _Hallazgo h) {
    final e = aristas[h.indice];
    aristas.removeAt(h.indice);
    aristas.add(_Arista(e.a, h.punto));
    aristas.add(_Arista(h.punto, e.b));
    return h.punto;
  }

  List<Offset>? ruta(Offset origen, Rect destino) {
    if (_aristas.isEmpty) return null;
    final aristas = List<_Arista>.of(_aristas);
    final qo = _insertar(aristas, _masCercano(aristas, Rect.fromLTWH(origen.dx, origen.dy, 0, 0)));
    final qd = _insertar(aristas, _masCercano(aristas, destino));

    final ids = <Offset, int>{};
    final nodos = <Offset>[];
    final ady = <List<_Vecino>>[];
    int id(Offset o) => ids.putIfAbsent(o, () {
          nodos.add(o);
          ady.add(<_Vecino>[]);
          return nodos.length - 1;
        });

    for (final e in aristas) {
      final u = id(e.a);
      final v = id(e.b);
      final w = (e.b - e.a).distance;
      ady[u].add(_Vecino(v, w));
      ady[v].add(_Vecino(u, w));
    }
    final inicio = id(qo);
    final fin = id(qd);

    final dist = List<double>.filled(nodos.length, double.infinity);
    final previo = List<int>.filled(nodos.length, -1);
    final visto = List<bool>.filled(nodos.length, false);
    dist[inicio] = 0;
    for (var it = 0; it < nodos.length; it++) {
      var u = -1;
      for (var i = 0; i < nodos.length; i++) {
        if (!visto[i] && (u == -1 || dist[i] < dist[u])) u = i;
      }
      if (u == -1 || dist[u] == double.infinity) break;
      visto[u] = true;
      if (u == fin) break;
      for (final v in ady[u]) {
        final nd = dist[u] + v.peso;
        if (nd < dist[v.nodo]) {
          dist[v.nodo] = nd;
          previo[v.nodo] = u;
        }
      }
    }
    if (dist[fin] == double.infinity) return null;

    final camino = <Offset>[];
    for (var n = fin; n != -1; n = previo[n]) {
      camino.add(nodos[n]);
    }
    return [origen, ...camino.reversed, _limitarARect(qd, destino)];
  }
}

class _Paso {
  const _Paso(this.icono, this.giro, this.texto);
  final IconData icono;
  final String giro;
  final String texto;
}

class _Ruta {
  const _Ruta(this.puntos, this.pasos, this.acumulado, this.mpp);
  final List<Offset> puntos;
  final List<_Paso> pasos;
  final List<double> acumulado;
  final double mpp;

  double get largo => acumulado.last;
  double get metros => largo * mpp;
  int get minutos => math.max(1, (metros / _metrosPorMinuto).ceil());
}

class _Proyeccion {
  const _Proyeccion(this.tramo, this.desvio, this.avance, this.punto);
  final int tramo;
  final double desvio;
  final double avance;
  final Offset punto;
}

List<Offset> _simplificar(List<Offset> crudo) {
  final r = <Offset>[];
  for (final p in crudo) {
    if (r.isEmpty || (p - r.last).distance > 1) r.add(p);
  }
  if (r.length < 3) return r;
  final s = <Offset>[r.first];
  for (var i = 1; i < r.length - 1; i++) {
    final a = r[i] - s.last;
    final b = r[i + 1] - r[i];
    final cruz = a.dx * b.dy - a.dy * b.dx;
    final punto = a.dx * b.dx + a.dy * b.dy;
    if (cruz.abs() < 0.02 * a.distance * b.distance && punto > 0) continue;
    s.add(r[i]);
  }
  s.add(r.last);
  return s;
}

String _metros(double px, double mpp) {
  final m = px * mpp;
  return '${math.max(5, (m / 5).round() * 5)} m';
}

_Ruta _construirRuta(List<Offset> crudo, Salon destino, double mpp) {
  final pts = _simplificar(crudo);
  final pasos = <_Paso>[];
  final acumulado = <double>[0];
  for (var i = 0; i < pts.length - 1; i++) {
    final v = pts[i + 1] - pts[i];
    acumulado.add(acumulado.last + v.distance);
    final d = _metros(v.distance, mpp);
    if (i == 0) {
      pasos.add(_Paso(Icons.straight, 'Avanza recto', 'Avanza recto $d'));
      continue;
    }
    final u = pts[i] - pts[i - 1];
    final cruz = u.dx * v.dy - u.dy * v.dx;
    final punto = u.dx * v.dx + u.dy * v.dy;
    final seno = cruz / (u.distance * v.distance);
    if (seno.abs() < 0.35 && punto > 0) {
      pasos.add(_Paso(Icons.straight, 'Continúa recto', 'Continúa recto $d'));
    } else if (cruz > 0) {
      pasos.add(_Paso(Icons.turn_right, 'Gira a la derecha', 'Gira a la derecha y avanza $d'));
    } else {
      pasos.add(_Paso(Icons.turn_left, 'Gira a la izquierda', 'Gira a la izquierda y avanza $d'));
    }
  }
  pasos.add(_Paso(Icons.flag_rounded, 'Llegas al ${destino.nombre}', 'Llegaste al ${destino.nombre}'));
  return _Ruta(pts, pasos, acumulado, mpp);
}

_Proyeccion _proyectar(_Ruta r, Offset p) {
  _Proyeccion? mejor;
  for (var i = 0; i < r.puntos.length - 1; i++) {
    final a = r.puntos[i];
    final ab = r.puntos[i + 1] - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = l2 == 0 ? 0.0 : ((((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2).clamp(0.0, 1.0).toDouble());
    final q = a + ab * t;
    final d = (p - q).distance;
    if (mejor == null || d < mejor.desvio) {
      mejor = _Proyeccion(i, d, r.acumulado[i] + ab.distance * t, q);
    }
  }
  return mejor!;
}

Offset _puntoEn(_Ruta r, double d) {
  for (var i = 0; i < r.puntos.length - 1; i++) {
    if (d <= r.acumulado[i + 1]) {
      final l = r.acumulado[i + 1] - r.acumulado[i];
      final t = l == 0 ? 0.0 : (d - r.acumulado[i]) / l;
      return Offset.lerp(r.puntos[i], r.puntos[i + 1], t)!;
    }
  }
  return r.puntos.last;
}

double _distanciaM(LatLng a, LatLng b) {
  final dy = (a.latitude - b.latitude) * 110540;
  final dx = (a.longitude - b.longitude) * 111320 * math.cos(a.latitude * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

class _OpcionTema {
  const _OpcionTema(this.modo, this.icono, this.titulo, this.subtitulo);
  final ThemeMode modo;
  final IconData icono;
  final String titulo;
  final String? subtitulo;
}

class _Estado {
  const _Estado(this.icono, this.texto, this.color);
  final IconData icono;
  final String texto;
  final Color color;
}

// ---------------------------------------------------------------------------
// Pantalla Principal (Mapa)
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.admin = false});

  /// true = Orienta-Tec-Administrador (dibujar salones y rutas).
  final bool admin;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _claveHistorial = 'historial_busquedas';
  static const int _maxHistorial = 8;

  // Mapa oscuro sin clave: invierte los tiles de OpenStreetMap conservando el
  // color (invertir + girar el tono 180°) y los lleva a azul marino.
  //   fondo ~ #1C2434, parques ~ verde oscuro, agua ~ azul, edificios ~ gris azulado
  // Para más azul sube el último número de la fila B; para parques más
  // verdes, baja el segundo valor de la fila R (-1.287) hacia -1.4.
  static const ColorFilter _filtroMapaOscuro = ColorFilter.matrix(<double>[
    0.5166, -1.287, -0.1296, 0, 240.85, // R
    -0.3834, -0.387, -0.1296, 0, 251.55, // G
    -0.3834, -1.287, 0.7704, 0, 272.95, // B
    0, 0, 0, 1, 0,
  ]);

  static final LatLngBounds _limitesCamara = LatLngBounds(
    LatLng(_centroCampus.latitude - 0.006, _centroCampus.longitude - 0.008),
    LatLng(_centroCampus.latitude + 0.006, _centroCampus.longitude + 0.008),
  );

  // Salones y rutas vigentes. En la app de usuarios se actualizan solos
  // cuando el administrador publica; en la de administrador son el borrador.
  late DatosMapa _datos = repositorioMapa.value;
  late _Red _red = _Red(_datos.caminos);
  final EditorMapa _editor = EditorMapa(repositorioMapa.value);
  Timer? _syncTimer;

  List<Salon> get _salones => _datos.salones;
  final SearchController _busqueda = SearchController();

  late final _GeoRef? _geo = _GeoRef.desdeValores(_calibracion);

  final MapController _mapa = MapController();
  late final AnimationController _camCtrl = AnimationController(vsync: this)..addListener(_tickCamara);
  LatLng _c0 = _centroCampus;
  LatLng _c1 = _centroCampus;
  double _z0 = 17.5;
  double _z1 = 17.5;
  bool _mapaListo = false;
  double _zoom = 17.5;
  bool _etiquetasVisibles = false;

  // Rotación del mapa (grados) para mostrar u ocultar la brújula.
  final ValueNotifier<double> _rotacion = ValueNotifier<double>(0);
  late final AnimationController _rotCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..addListener(_tickRotacion);
  double _rot0 = 0;

  // Números de salón buscados por el usuario (el más reciente primero).
  List<String> _historial = <String>[];

  bool _verImagen = false;
  int? _piso;
  EdgeInsets _seguro = EdgeInsets.zero;
  final ValueNotifier<double> _extHoja = ValueNotifier<double>(0);

  StreamSubscription<Position>? _gpsSub;
  bool _permiso = false;
  LatLng? _posGps;
  Offset? _posPx;
  bool _cerca = false;

  Salon? _salon;
  _Ruta? _ruta;
  bool _navegando = false;
  int _paso = 0;
  bool _llegada = false;
  bool _siguiendo = true;
  double _avancePx = 0;
  Offset? _posUsuario;
  String? _aviso;
  Timer? _simTimer;
  bool _simulando = false;
  DateTime _ultimoRecalculo = DateTime.fromMillisecondsSinceEpoch(0);

  double get _mpp => _geo?.metrosPorPixel ?? _metrosPorPixel;

  Offset get _origen {
    final g = _geo;
    if (g != null) {
      return g.aPlano(_accesoPrincipalGeo.latitude, _accesoPrincipalGeo.longitude);
    }
    return const Offset(745, 397);
  }

  Offset get _origenRuta => (_cerca && _posPx != null) ? _posPx! : _origen;
  bool get _mostrarHoja => _salon != null && _ruta != null && !_navegando;


@override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.admin) {
      _editor.addListener(_alCambiarEditor);
    } else {
      repositorioMapa.addListener(_alCambiarRepositorio);
      if (repositorioMapa.remotoConfigurado) {
        _syncTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => repositorioMapa.sincronizar(),
        );
      }

      // Verificación de actualización para la versión de usuario
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ServicioActualizacion.verificarActualizacion(context);
      });
    }

    _cargarHistorial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.admin) _iniciarUbicacion();
      // Carga la imagen del modo satélite con calma, para que no se trabe
      // la primera vez que se activa.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) precacheImage(const AssetImage(_rutaImagen), context);
      });
    });
  }


    


  void _alCambiarEditor() {
    if (!mounted) return;
    setState(() {
      _datos = _editor.datos;
      _red = _Red(_datos.caminos);
    });
  }

  /// El administrador publicó cambios: se redibuja el mapa y, si el usuario
  /// tenía una ruta abierta, se recalcula con los datos nuevos.
  void _alCambiarRepositorio() {
    if (!mounted) return;
    final nuevos = repositorioMapa.value;
    setState(() {
      _datos = nuevos;
      _red = _Red(nuevos.caminos);
    });
    final actual = _salon;
    if (actual == null) return;
    final i = nuevos.salones.indexWhere((s) => s.numero == actual.numero);
    if (i < 0) {
      _limpiar();
      return;
    }
    if (_navegando) {
      setState(() => _salon = nuevos.salones[i]);
      return;
    }
    _seleccionar(nuevos.salones[i]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.admin) {
      repositorioMapa.sincronizar();
    }
  }

  bool _esActivo(Salon s) => widget.admin ? s.numero == _editor.salonSel : s == _salon;

  List<int> get _pisosDisponibles => (_salones.map((s) => s.piso).toSet().toList()..sort());

  /// Equivalente en px del plano a ~16 px de pantalla con el zoom actual.
  double _radioToque() {
    final metrosPorPxPantalla = 156543.03392 * math.cos(_centroCampus.latitude * math.pi / 180) / math.pow(2, _zoom);
    return 16 * metrosPorPxPantalla / _mpp;
  }

  Future<void> _tocarEditor(Offset plano) async {
    final r = _editor.alTocar(plano, imagen: _verImagen, radio: _radioToque());
    if (r == ResultadoToque.salonTerminado) {
      await crearSalonDibujado(context, _editor);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    repositorioMapa.removeListener(_alCambiarRepositorio);
    _editor.removeListener(_alCambiarEditor);
    _editor.dispose();
    _gpsSub?.cancel();
    _simTimer?.cancel();
    _camCtrl.dispose();
    _rotCtrl.dispose();
    _rotacion.dispose();
    _busqueda.dispose();
    _mapa.dispose();
    _extHoja.dispose();
    super.dispose();
  }

  void _tickCamara() {
    if (!_mapaListo) return;
    final t = Curves.easeInOutCubic.transform(_camCtrl.value);
    _mapa.move(
      LatLng(
        _c0.latitude + (_c1.latitude - _c0.latitude) * t,
        _c0.longitude + (_c1.longitude - _c0.longitude) * t,
      ),
      _z0 + (_z1 - _z0) * t,
    );
  }

  void _tickRotacion() {
    if (!_mapaListo) return;
    final t = Curves.easeInOutCubic.transform(_rotCtrl.value);
    _mapa.rotate(_rot0 * (1 - t));
  }

  /// Devuelve el mapa a la orientación norte, girando por el lado más corto.
  void _norte() {
    if (!_mapaListo) return;
    var r = _mapa.camera.rotation % 360;
    if (r > 180) r -= 360;
    if (r.abs() < 0.5) {
      _mapa.rotate(0);
      return;
    }
    _rot0 = r;
    _rotCtrl.forward(from: 0);
  }

  Future<void> _cargarHistorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getStringList(_claveHistorial) ?? const <String>[];
      if (!mounted) return;
      setState(() => _historial = List<String>.of(guardado));
    } catch (_) {
      // Sin historial guardado se muestran las sugerencias normales.
    }
  }

  Future<void> _guardarHistorial(List<String> lista) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_claveHistorial, lista);
    } catch (_) {
      // Si no se puede guardar, igual funciona durante esta sesión.
    }
  }

  void _registrarBusqueda(Salon s) {
    final lista = <String>[s.numero, ..._historial.where((n) => n != s.numero)];
    if (lista.length > _maxHistorial) {
      lista.removeRange(_maxHistorial, lista.length);
    }
    setState(() => _historial = lista);
    _guardarHistorial(lista);
  }

  void _borrarHistorial() {
    setState(() => _historial = <String>[]);
    _guardarHistorial(const <String>[]);
  }

  /// Los salones que el usuario buscó, del más reciente al más antiguo.
  List<Salon> get _recomendados {
    final out = <Salon>[];
    for (final n in _historial) {
      final i = _salones.indexWhere((s) => s.numero == n);
      if (i >= 0) out.add(_salones[i]);
      if (out.length == 4) break;
    }
    return out;
  }

  IconData _iconoTema(ThemeMode modo) => switch (modo) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  void _elegirTema() {
    const opciones = <_OpcionTema>[
      _OpcionTema(ThemeMode.system, Icons.brightness_auto_outlined, 'Automático', 'Sigue el modo de tu teléfono'),
      _OpcionTema(ThemeMode.light, Icons.light_mode_outlined, 'Claro', null),
      _OpcionTema(ThemeMode.dark, Icons.dark_mode_outlined, 'Oscuro', null),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Paleta.of(context).superficie,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) {
        final p = Paleta.of(ctx);
        return SafeArea(
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: controladorTema,
            builder: (ctx, actual, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Apariencia',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.acento),
                    ),
                  ),
                ),
                for (final o in opciones)
                  ListTile(
                    leading: Icon(o.icono, color: p.acento),
                    title: Text(o.titulo, style: TextStyle(color: p.texto)),
                    subtitle: o.subtitulo == null ? null : Text(o.subtitulo!, style: TextStyle(color: p.textoSec)),
                    trailing: actual == o.modo ? Icon(Icons.check_circle, color: p.primario) : null,
                    onTap: () {
                      controladorTema.cambiar(o.modo);
                      Navigator.pop(ctx);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _irA(LatLng destino, double zoom, {int ms = 600}) {
    if (!_mapaListo) return;
    final cam = _mapa.camera;
    _c0 = cam.center;
    _z0 = cam.zoom;
    _c1 = destino;
    _z1 = zoom;
    _camCtrl.duration = Duration(milliseconds: ms);
    _camCtrl.forward(from: 0);
  }

  EdgeInsets _paddingAjuste() {
    final sup = _seguro.top + (_navegando && !_llegada ? 118 : 132);
    final inf = _seguro.bottom +
        (_navegando ? (_llegada ? 190 : 210) : (_salon == null ? 250 : 300)) +
        20;
    return EdgeInsets.fromLTRB(32, sup, 32, inf);
  }

  void _ajustarA(List<LatLng> pts, {double maxZoom = 19.5}) {
    if (!_mapaListo || pts.isEmpty) return;
    _camCtrl.stop();
    _mapa.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: _paddingAjuste(),
        maxZoom: maxZoom,
      ),
    );
  }

  void _verCampus() {
    final geo = _geo;
    if (geo == null) {
      _irA(_centroCampus, 17.5);
      return;
    }
    final pts = <LatLng>[];
    for (final s in _salones) {
      for (final p in s.esquinasImagen) {
        pts.add(geo.aLatLng(p));
      }
    }
    _ajustarA(pts, maxZoom: 18);
  }

  void _enfocarRuta() {
    final r = _ruta;
    final geo = _geo;
    if (r == null || geo == null || r.puntos.length < 2) return;
    _ajustarA(r.puntos.map(geo.aLatLng).toList());
  }

  void _seguirUsuario() {
    final u = _posUsuario;
    final geo = _geo;
    if (u == null || geo == null) return;
    _irA(geo.aLatLng(u), math.max(_zoom, 18.5), ms: 350);
  }

  Future<void> _irAMiUbicacion() async {
    if (_navegando) {
      setState(() => _siguiendo = true);
      _seguirUsuario();
      return;
    }
    if (!_permiso) {
      await _iniciarUbicacion();
      if (!_permiso) return;
    }
    if (_cerca && _posGps != null) {
      _irA(_posGps!, 19);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estás fuera del campus. Te mostramos el acceso principal.')),
      );
    }
    _irA(_accesoPrincipalGeo, 18.5);
  }

  Future<void> _iniciarUbicacion() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _permiso = false);
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      final ok = p == LocationPermission.always || p == LocationPermission.whileInUse;
      if (!mounted) return;
      setState(() => _permiso = ok);
      if (!ok) return;
      _gpsSub?.cancel();
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
        ),
      ).listen(_alRecibirGps, onError: (Object _) {});
    } catch (_) {
      if (mounted) setState(() => _permiso = false);
    }
  }

  void _recalcularCerca() {
    final g = _posGps;
    final geo = _geo;
    if (g == null) {
      _posPx = null;
      _cerca = false;
    } else if (geo != null) {
      final px = geo.aPlano(g.latitude, g.longitude);
      _posPx = px;
      _cerca = _zonaCampus.contains(px);
    } else {
      _posPx = null;
      _cerca = _distanciaM(g, _centroCampus) < 700;
    }
  }

  void _alRecibirGps(Position pos) {
    if (!mounted) return;
    setState(() {
      _posGps = LatLng(pos.latitude, pos.longitude);
      _recalcularCerca();
    });
    if (_navegando && !_simulando && !_llegada) {
      final px = _posPx;
      if (px == null || !_cerca) {
        setState(() => _aviso = 'Parece que estás fuera del campus.');
        return;
      }
      if (pos.accuracy > 40) {
        setState(() => _aviso = 'Señal GPS débil (±${pos.accuracy.round()} m)');
        return;
      }
      setState(() => _aviso = null);
      _alActualizarPosicion(px);
    }
  }

  void _seleccionar(Salon s) {
    if (widget.admin) {
      _editor.seleccionarSalon(s.numero);
      final g = _geo;
      if (g != null) {
        _irA(g.aLatLng(_verImagen ? s.centro : s.centroMapa), math.max(_zoom, 18.5));
      }
      return;
    }
    final pts = _red.ruta(_origenRuta, s.area);
    if (pts == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay una ruta disponible al ${s.nombre}.')),
      );
      return;
    }
    _detenerSimulacion();
    setState(() {
      _salon = s;
      _ruta = _construirRuta(pts, s, _mpp);
      _navegando = false;
      _llegada = false;
      _paso = 0;
      _avancePx = 0;
      _posUsuario = null;
      _aviso = null;
      _extHoja.value = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _enfocarRuta());
  }

  void _limpiar() {
    _detenerSimulacion();
    setState(() {
      _salon = null;
      _ruta = null;
      _navegando = false;
      _llegada = false;
      _paso = 0;
      _avancePx = 0;
      _posUsuario = null;
      _aviso = null;
    });
    _busqueda.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verCampus());
  }

  void _iniciar() {
    final s = _salon;
    if (s == null) return;
    final pts = _red.ruta(_origenRuta, s.area);
    if (pts == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay una ruta disponible al ${s.nombre}.')),
      );
      return;
    }
    final r = _construirRuta(pts, s, _mpp);
    final trivial = r.puntos.length < 2;
    setState(() {
      _ruta = r;
      _navegando = true;
      _paso = 0;
      _avancePx = 0;
      _llegada = trivial;
      _siguiendo = true;
      _posUsuario = null;
      _aviso = null;
    });
    if (trivial) return;
    if (_geo != null && _permiso && _cerca && _posPx != null) {
      _detenerSimulacion();
      _alActualizarPosicion(_posPx!);
    } else {
      setState(() => _aviso = 'Estás fuera del campus: vista previa del recorrido');
      _iniciarSimulacion();
    }
  }

  void _terminar() {
    _detenerSimulacion();
    setState(() {
      _navegando = false;
      _llegada = false;
      _paso = 0;
      _avancePx = 0;
      _posUsuario = null;
      _aviso = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _enfocarRuta());
  }

  void _detenerSimulacion() {
    _simTimer?.cancel();
    _simTimer = null;
    _simulando = false;
  }

  void _iniciarSimulacion() {
    final r = _ruta;
    if (r == null || r.puntos.length < 2) return;
    _detenerSimulacion();
    _simulando = true;
    var d = 0.0;
    final tick = 4.0 * 0.2 / _mpp;
    _alActualizarPosicion(r.puntos.first);
    _simTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      final actual = _ruta;
      if (!mounted || actual == null || !_navegando) {
        t.cancel();
        return;
      }
      d += tick;
      _alActualizarPosicion(_puntoEn(actual, math.min(d, actual.largo)));
      if (d >= actual.largo) t.cancel();
    });
  }

  void _alternarSimulacion() {
    if (_simulando) {
      if (_geo != null && _permiso && _cerca && _posPx != null) {
        _detenerSimulacion();
        setState(() => _aviso = null);
        _alActualizarPosicion(_posPx!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No estás en el campus: solo puedes ver la simulación.')),
        );
      }
    } else {
      _iniciarSimulacion();
    }
  }

  void _alActualizarPosicion(Offset px) {
    final r = _ruta;
    if (r == null || !_navegando || r.puntos.length < 2) return;
    final pr = _proyectar(r, px);

    if (pr.desvio * _mpp > _umbralDesvioM) {
      _recalcular(px);
      return;
    }

    final restanteM = (r.largo - pr.avance) * _mpp;
    final llego = restanteM < _radioLlegadaM;
    setState(() {
      _posUsuario = pr.punto;
      _avancePx = pr.avance;
      _llegada = llego;
      _paso = llego ? r.pasos.length - 1 : math.min(pr.tramo, r.pasos.length - 2);
    });
    if (_siguiendo) _seguirUsuario();
    if (llego) _detenerSimulacion();
  }

  void _recalcular(Offset desde) {
    setState(() {
      _posUsuario = desde;
      _aviso = 'Te saliste de la ruta. Recalculando…';
    });
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoRecalculo) < const Duration(seconds: 6)) return;
    _ultimoRecalculo = ahora;

    final s = _salon;
    if (s == null) return;
    final pts = _red.ruta(desde, s.area);
    if (pts == null) return;
    setState(() {
      _ruta = _construirRuta(pts, s, _mpp);
      _paso = 0;
      _avancePx = 0;
    });
  }

  bool _visiblePorPiso(Salon s) => _piso == null || s.piso == _piso || s == _salon;

  List<Polygon> _poligonos(_GeoRef geo) {
    final p = Paleta.of(context);
    final out = <Polygon>[];
    for (final s in _salones) {
      if (!_visiblePorPiso(s)) continue;
      final activo = _esActivo(s);
      final sat = _verImagen;
      final esquinas = sat ? s.esquinasImagen : s.esquinasMapa;
      if (esquinas.length < 3) continue;
      out.add(Polygon(
        points: esquinas.map(geo.aLatLng).toList(),
        color: activo
            ? _cian.withValues(alpha: 0.45)
            : (sat ? Colors.white.withValues(alpha: 0.14) : p.mapa.withValues(alpha: p.oscuro ? 0.28 : 0.20)),
        borderColor: activo ? (p.oscuro ? _cian : _cianOscuro) : (sat ? Colors.white : p.mapa),
        borderStrokeWidth: activo ? 4 : 2,
      ));
    }
    return out;
  }

  List<Polyline> _lineas(_GeoRef geo) {
    final r = _ruta;
    if (r == null || r.puntos.length < 2) return <Polyline>[];
    List<LatLng> ll(List<Offset> p) => p.map(geo.aLatLng).toList();

    var resto = r.puntos;
    final out = <Polyline>[];
    if (_navegando && _avancePx > 0) {
      final corte = _puntoEn(r, _avancePx);
      final hecho = <Offset>[];
      final pendiente = <Offset>[corte];
      for (var i = 0; i < r.puntos.length; i++) {
        if (r.acumulado[i] <= _avancePx) {
          hecho.add(r.puntos[i]);
        } else {
          pendiente.add(r.puntos[i]);
        }
      }
      hecho.add(corte);
      resto = pendiente;
      if (hecho.length >= 2) {
        out.add(Polyline(
          points: ll(hecho),
          color: const Color(0xFF9FB0C3),
          strokeWidth: 6,
          borderColor: _casing,
          borderStrokeWidth: 2.5,
        ));
      }
    }
    if (resto.length >= 2) {
      out.add(Polyline(
        points: ll(resto),
        color: _cian,
        strokeWidth: 6,
        borderColor: _casing,
        borderStrokeWidth: 2.5,
      ));
    }
    return out;
  }

  List<Marker> _marcadores() {
    final geo = _geo;
    final out = <Marker>[];

    if (geo != null) {
      for (final s in _salones) {
        if (!_visiblePorPiso(s)) continue;
        final activo = _esActivo(s);
        final pos = geo.aLatLng(_verImagen ? s.centro : s.centroMapa);
        if (activo && _ruta != null) {
          out.add(Marker(
            point: pos,
            width: 46,
            height: 46,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.location_on, size: 46, color: _rosa, shadows: [Shadow(color: Colors.black45, blurRadius: 6)]),
          ));
          continue;
        }
        // Con el mapa alejado no se dibuja nada sobre los salones (solo su
        // contorno); las etiquetas aparecen al acercar.
        if (!_etiquetasVisibles && !activo) continue;
        out.add(Marker(
          point: pos,
          width: 64,
          height: 30,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _seleccionar(s),
              child: _EtiquetaSalon(numero: s.numero, activa: activo),
            ),
          ),
        ));
      }

      if (!_cerca && !_navegando) {
        out.add(Marker(
          point: _accesoPrincipalGeo,
          width: 36,
          height: 36,
          child: const _MarcadorOrigen(),
        ));
      }
    }

    final u = _posUsuario;
    if (_navegando && u != null && geo != null) {
      out.add(Marker(point: geo.aLatLng(u), width: 44, height: 44, child: const _MarcadorUsuario()));
    } else if (_cerca && _posGps != null) {
      out.add(Marker(point: _posGps!, width: 44, height: 44, child: const _MarcadorUsuario()));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    _seguro = MediaQuery.paddingOf(context);
    final p = Paleta.of(context);
    final geo = _geo;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: p.oscuro ? Brightness.light : Brightness.dark,
        statusBarBrightness: p.oscuro ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: p.fondo,
        body: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: FlutterMap(
                mapController: _mapa,
                options: MapOptions(
                  initialCenter: _centroCampus,
                  initialZoom: 17.5,
                  minZoom: 15,
                  maxZoom: 21,
                  cameraConstraint: CameraConstraint.containCenter(bounds: _limitesCamara),
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  onMapReady: () {
                    _mapaListo = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _verCampus();
                    });
                  },
                  onTap: (_, punto) {
                    final g = _geo;
                    if (g == null) return;
                    final plano = g.aPlano(punto.latitude, punto.longitude);
                    if (widget.admin) {
                      _tocarEditor(plano);
                      return;
                    }
                    final s = _salonEn(plano);
                    if (s != null) _seleccionar(s);
                  },
                  onPositionChanged: (camara, hayGesto) {
                    _zoom = camara.zoom;
                    if ((camara.rotation - _rotacion.value).abs() > 0.1) {
                      _rotacion.value = camara.rotation;
                    }
                    if (hayGesto && _rotCtrl.isAnimating) _rotCtrl.stop();
                    if (hayGesto && _navegando && _siguiendo) {
                      setState(() => _siguiendo = false);
                    }
                    final visibles = camara.zoom >= _zoomEtiquetas;
                    if (visibles != _etiquetasVisibles) {
                      setState(() => _etiquetasVisibles = visibles);
                    }
                  },
                ),
                children: [
                  _capaTiles(p),
                  if (geo != null && _verImagen)
                    OverlayImageLayer(
                      overlayImages: [
                        RotatedOverlayImage(
                          imageProvider: const AssetImage(_rutaImagen),
                          topLeftCorner: geo.aLatLng(const Offset(0, 0)),
                          bottomLeftCorner: geo.aLatLng(const Offset(0, _imgH)),
                          bottomRightCorner: geo.aLatLng(const Offset(_imgW, _imgH)),
                          opacity: 0.96,
                        ),
                      ],
                    ),
                  if (geo != null) PolygonLayer(polygons: _poligonos(geo)),
                  if (geo != null && _ruta != null) PolylineLayer(polylines: _lineas(geo)),
                  MarkerLayer(rotate: true, markers: _marcadores()),
                  if (widget.admin && geo != null) ..._editor.capas(aLatLng: geo.aLatLng, imagen: _verImagen),
                ],
              ),
              ),
            ),
            _capaSuperior(),
            if (_mostrarHoja) _capaDetalle() else _capaInferior(),
          ],
        ),
      ),
    );
  }

  Widget _capaTiles(Paleta p) {
    if (!p.oscuro) {
      return TileLayer(
        urlTemplate: _urlTiles,
        userAgentPackageName: _paqueteApp,
        maxNativeZoom: 19,
        retinaMode: _claveCarto != '' && RetinaMode.isHighDensity(context),
      );
    }
    if (_claveMapTiler != '') {
      return TileLayer(
        urlTemplate: _urlTilesOscuro,
        userAgentPackageName: _paqueteApp,
        maxNativeZoom: 19,
        retinaMode: RetinaMode.isHighDensity(context),
      );
    }
    return ColorFiltered(
      colorFilter: _filtroMapaOscuro,
      child: TileLayer(
        urlTemplate: _urlTilesOsm,
        userAgentPackageName: _paqueteApp,
        maxNativeZoom: 19,
      ),
    );
  }

  Salon? _salonEn(Offset p) {
    for (final s in _salones) {
      if (puntoCercaDePoligono(p, _verImagen ? s.esquinasImagen : s.esquinasMapa)) return s;
    }
    return null;
  }

  Widget _capaSuperior() {
    final Widget hijo;
    if (_navegando && !_llegada) {
      hijo = _bannerNavegacion();
    } else {
      hijo = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _barraBusqueda(),
          const SizedBox(height: 10),
          _chips(),
        ],
      );
    }
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: hijo,
            ),
          ),
        ),
      ),
    );
  }

  Widget _botonesMapa() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_geo != null) ...[
          _BotonMapa(
            icono: _verImagen ? Icons.map_outlined : Icons.satellite_alt_outlined,
            tooltip: _verImagen ? 'Vista de mapa' : 'Vista satélite',
            onPressed: () => setState(() => _verImagen = !_verImagen),
          ),
          const SizedBox(height: 8),
        ],
        _BotonBrujula(rotacion: _rotacion, onPressed: _norte),
        _BotonMapa(
          icono: Icons.my_location,
          tooltip: _navegando ? 'Seguir mi ubicación' : 'Mi ubicación',
          destacado: _navegando && !_siguiendo,
          onPressed: _irAMiUbicacion,
        ),
      ],
    );
  }

  Widget _capaInferior() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12, bottom: 12),
                      child: _Atribucion(),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 10),
                      child: _botonesMapa(),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: widget.admin ? _panelAdmin() : _panel(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _capaDetalle() {
    final s = _salon!;
    final r = _ruta!;
    final safeBottom = _seguro.bottom;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight;
          final minF = (270 / h).clamp(0.22, 0.5).toDouble();
          return Stack(
            children: [
              // Solo esta parte se redibuja mientras arrastras la hoja.
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _extHoja,
                  builder: (context, valor, _) {
                    final ext = valor.clamp(minF, 0.92).toDouble();
                    return Stack(
                      children: [
                        Positioned(
                          left: 12,
                          bottom: ext * h + 10,
                          child: const _Atribucion(),
                        ),
                        Positioned(
                          right: 12,
                          bottom: ext * h + 10,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: ext > 0.6 ? 0 : 1,
                            child: IgnorePointer(
                              ignoring: ext > 0.6,
                              child: _botonesMapa(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: NotificationListener<DraggableScrollableNotification>(
                    onNotification: (n) {
                      final e = n.extent;
                      if ((e - _extHoja.value).abs() > 0.003) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _extHoja.value = e;
                        });
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      key: ValueKey('hoja-${s.numero}'),
                      expand: false,
                      initialChildSize: minF,
                      minChildSize: minF,
                      maxChildSize: 0.92,
                      snap: true,
                      snapSizes: const [0.6],
                      builder: (context, scroll) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: Paleta.of(context).superficie,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: ListView(
                          controller: scroll,
                          padding: EdgeInsets.fromLTRB(20, 10, 20, 24 + safeBottom),
                          children: _contenidoHoja(s, r),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _contenidoHoja(Salon s, _Ruta r) {
    final p = Paleta.of(context);
    return [
      Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: p.divisor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.primario, borderRadius: BorderRadius.circular(16)),
            child: Text(
              s.numero,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.acento),
                ),
                Text(s.ubicacion, style: TextStyle(fontSize: 14, color: p.textoSec)),
              ],
            ),
          ),
          IconButton(onPressed: _limpiar, tooltip: 'Quitar destino', icon: const Icon(Icons.close)),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Icon(Icons.directions_walk, color: p.acento, size: 20),
          const SizedBox(width: 8),
          Text('${r.minutos} min', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.verde)),
          Text('  (${r.metros.round()} m)', style: TextStyle(fontSize: 14, color: p.textoSec)),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(_cerca ? Icons.my_location : Icons.trip_origin, color: _cianOscuro, size: 16),
          const SizedBox(width: 10),
          Text(
            _cerca ? 'Desde tu ubicación' : 'Desde el acceso principal',
            style: TextStyle(fontSize: 13, color: p.textoSec),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _iniciar,
          style: _estiloLleno(p),
          icon: const Icon(Icons.navigation_rounded, size: 20),
          label: Text(
            _cerca ? 'Iniciar ruta' : 'Vista previa de la ruta',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SizedBox(height: 22),
      _FotoSalon(salon: s),
      const SizedBox(height: 22),
      const _TituloSeccion('Detalles'),
      const SizedBox(height: 10),
      _FilaDetalle(icono: Icons.meeting_room_outlined, etiqueta: 'Tipo', valor: s.tipo),
      _FilaDetalle(icono: Icons.apartment_outlined, etiqueta: 'Edificio', valor: s.edificio),
      _FilaDetalle(icono: Icons.layers_outlined, etiqueta: 'Piso', valor: '${s.piso}'),
      const SizedBox(height: 6),
      Text(s.detalle, style: TextStyle(fontSize: 14, color: p.textoSec, height: 1.4)),
      const SizedBox(height: 22),
      const _TituloSeccion('Cómo llegar'),
      const SizedBox(height: 10),
      _PasoIndicacion(
        icono: _cerca ? Icons.my_location : Icons.trip_origin,
        texto: _cerca ? 'Parte desde tu ubicación' : 'Parte desde el acceso principal',
      ),
      for (final paso in r.pasos) _PasoIndicacion(icono: paso.icono, texto: paso.texto),
    ];
  }

  Widget _barraBusqueda() {
    final p = Paleta.of(context);
    return SearchAnchor.bar(
      searchController: _busqueda,
      barHintText: 'Buscar salón o edificio',
      barLeading: Icon(Icons.search, color: p.acento),
      barTrailing: [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: controladorTema,
          builder: (context, modo, _) => IconButton(
            icon: Icon(_iconoTema(modo), color: p.acento),
            tooltip: 'Apariencia',
            onPressed: _elegirTema,
          ),
        ),
      ],
      barBackgroundColor: WidgetStatePropertyAll(p.superficie),
      barElevation: const WidgetStatePropertyAll(6),
      viewBackgroundColor: p.superficie,
      suggestionsBuilder: (context, controller) {
        final q = controller.text.trim().toLowerCase();
        var lista = _salones.where((s) {
          return q.isEmpty || s.numero.contains(q) || s.nombre.toLowerCase().contains(q) || s.edificio.toLowerCase().contains(q);
        }).toList();
        // Sin texto escrito, primero van los salones que ya buscó.
        if (q.isEmpty && _historial.isNotEmpty) {
          final recientes = <Salon>[
            for (final n in _historial) ...lista.where((s) => s.numero == n),
          ];
          final resto = lista.where((s) => !_historial.contains(s.numero));
          lista = [...recientes, ...resto];
        }
        if (lista.isEmpty) {
          return [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Sin resultados.'),
            ),
          ];
        }
        return lista.map(
          (s) => ListTile(
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.primario, borderRadius: BorderRadius.circular(12)),
              child: Text(s.numero, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            title: Text(s.nombre),
            subtitle: Text(s.ubicacion),
            trailing: (q.isEmpty && _historial.contains(s.numero))
                ? Icon(Icons.history, size: 20, color: p.textoSec)
                : null,
            onTap: () {
              controller.closeView('');
              _registrarBusqueda(s);
              _seleccionar(s);
            },
          ),
        );
      },
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          if (widget.admin) ...[
            _ChipMapa(icono: Icons.admin_panel_settings, texto: 'Administrador', activo: true, onTap: () {}),
            const SizedBox(width: 8),
          ],
          _ChipMapa(icono: Icons.zoom_out_map, texto: 'Ver campus', onTap: _verCampus),
          for (final p in _pisosDisponibles) ...[
            const SizedBox(width: 8),
            _ChipMapa(
              icono: Icons.layers_outlined,
              texto: 'Piso $p',
              activo: _piso == p,
              onTap: () => setState(() => _piso = _piso == p ? null : p),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bannerNavegacion() {
    final p = Paleta.of(context);
    final r = _ruta!;
    final idx = math.min(_paso, r.pasos.length - 2);
    final siguiente = r.pasos[math.min(idx + 1, r.pasos.length - 1)];
    final metrosTramo = math.max(0.0, (r.acumulado[idx + 1] - _avancePx) * r.mpp);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.banner,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
            child: Icon(siguiente.icono, size: 34, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _posUsuario == null ? 'Buscando tu ubicación…' : 'En ${(metrosTramo / 5).ceil() * 5} m',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                Text(siguiente.giro, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelAdmin() => PanelEditor(
        editor: _editor,
        imagen: _verImagen,
        origen: _origen,
        metrosPorPixel: _mpp,
      );

  Widget _panel() {
    final p = Paleta.of(context);
    final Widget hijo;
    if (_salon == null || _ruta == null) {
      hijo = _panelInicio();
    } else if (_llegada) {
      hijo = _panelLlegada();
    } else {
      hijo = _panelNavegacion();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: p.oscuro ? Colors.black.withValues(alpha: 0.5) : _azul.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: hijo),
      ),
    );
  }

  _Estado _estadoUbicacion() {
    final p = Paleta.of(context);
    if (!_permiso) {
      return _Estado(Icons.location_off, 'Activa la ubicación para verte en el mapa', p.textoSec);
    }
    if (_posGps == null) {
      return _Estado(Icons.gps_not_fixed, 'Buscando tu ubicación…', p.textoSec);
    }
    if (_cerca) {
      return _Estado(Icons.gps_fixed, 'Estás en el campus: ubicación en tiempo real', p.verde);
    }
    return _Estado(Icons.place_outlined, 'Estás fuera del campus: rutas desde el acceso principal', p.textoSec);
  }

  Widget _panelInicio() {
    final p = Paleta.of(context);
    final e = _estadoUbicacion();
    final recientes = _recomendados;
    final lista = recientes.isEmpty ? _salones.take(4).toList() : recientes;
    return Column(
      key: const ValueKey('inicio'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/icono_chico.png',
                  cacheWidth: 144,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    decoration: BoxDecoration(
                      color: p.acento.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.school_rounded, color: p.acento),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TecNM Campus Orizaba', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.acento)),
                  Text('Salones y edificios', style: TextStyle(fontSize: 14, color: p.textoSec)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(e.icono, size: 18, color: e.color),
            const SizedBox(width: 8),
            Expanded(child: Text(e.texto, style: TextStyle(fontSize: 13, color: e.color))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                recientes.isEmpty ? 'Sugerencias' : 'Tus búsquedas recientes',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textoSec),
              ),
            ),
            if (recientes.isNotEmpty)
              TextButton(
                onPressed: _borrarHistorial,
                style: TextButton.styleFrom(
                  foregroundColor: p.acento,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Borrar'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in lista)
              ActionChip(
                avatar: recientes.isEmpty ? null : Icon(Icons.history, size: 18, color: p.textoSec),
                label: Text(s.nombre),
                backgroundColor: p.chip,
                side: BorderSide.none,
                labelStyle: TextStyle(color: p.acento, fontWeight: FontWeight.w600),
                onPressed: () => _seleccionar(s),
              ),
          ],
        ),
      ],
    );
  }

  Widget _panelNavegacion() {
    final p = Paleta.of(context);
    final aviso = p.oscuro ? Colors.orange.shade300 : Colors.orange.shade900;
    final r = _ruta!;
    final restanteM = math.max(0.0, (r.largo - _avancePx) * r.mpp);
    final minutos = math.max(1, (restanteM / _metrosPorMinuto).ceil());
    final progreso = r.largo == 0 ? 0.0 : (_avancePx / r.largo).clamp(0.0, 1.0);
    return Column(
      key: const ValueKey('navegacion'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$minutos min', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.verde)),
            Text('  (${restanteM.round()} m)', style: TextStyle(fontSize: 15, color: p.textoSec)),
            const Spacer(),
            Text(_salon?.nombre ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.acento)),
          ],
        ),
        if (_aviso != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.gps_not_fixed, size: 16, color: aviso),
              const SizedBox(width: 8),
              Expanded(child: Text(_aviso!, style: TextStyle(fontSize: 12.5, color: aviso))),
            ],
          ),
        ],
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progreso, minHeight: 6, color: p.primario, backgroundColor: p.divisor, borderRadius: BorderRadius.circular(3)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: _terminar, style: _estiloBorde(p), child: const Text('Salir'))),
            if (kDebugMode) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _alternarSimulacion,
                  style: _estiloBorde(p),
                  icon: Icon(_simulando ? Icons.gps_fixed : Icons.play_arrow, size: 18),
                  label: Text(_simulando ? 'Usar GPS' : 'Simular'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _panelLlegada() {
    final p = Paleta.of(context);
    final s = _salon!;
    return Column(
      key: const ValueKey('llegada'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: p.verde.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
              child: Icon(Icons.check_rounded, size: 34, color: p.verde),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Llegaste al ${s.nombre}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.acento)),
                  Text(s.ubicacion, style: TextStyle(fontSize: 13, color: p.textoSec)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _limpiar, style: _estiloLleno(p), child: const Text('Finalizar', style: TextStyle(fontWeight: FontWeight.w700))),
        ),
      ],
    );
  }

  ButtonStyle _estiloLleno(Paleta p) => FilledButton.styleFrom(
    backgroundColor: p.primario,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );

  ButtonStyle _estiloBorde(Paleta p) => OutlinedButton.styleFrom(
    foregroundColor: p.acento,
    side: BorderSide(color: p.acento),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    minimumSize: const Size(0, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}

// ---------------------------------------------------------------------------
// Componentes auxiliares
// ---------------------------------------------------------------------------
class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Paleta.of(context).acento),
    );
  }
}

class _FotoSalon extends StatelessWidget {
  const _FotoSalon({required this.salon});
  final Salon salon;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          salon.foto,
          cacheWidth: 900,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Container(
            color: Paleta.of(context).chip,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_camera_outlined, size: 34, color: Colors.grey.shade500),
                const SizedBox(height: 8),
                Text(
                  'Foto del ${salon.nombre} próximamente',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaDetalle extends StatelessWidget {
  const _FilaDetalle({required this.icono, required this.etiqueta, required this.valor});
  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icono, size: 20, color: p.acento),
          const SizedBox(width: 12),
          Text(etiqueta, style: TextStyle(fontSize: 14, color: p.textoSec)),
          const Spacer(),
          Text(valor, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.texto)),
        ],
      ),
    );
  }
}

class _PasoIndicacion extends StatelessWidget {
  const _PasoIndicacion({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: p.acento.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icono, size: 20, color: p.acento),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 15, color: p.texto))),
        ],
      ),
    );
  }
}

class _BotonMapa extends StatelessWidget {
  const _BotonMapa({required this.icono, required this.tooltip, required this.onPressed, this.destacado = false});
  final IconData icono;
  final String tooltip;
  final VoidCallback onPressed;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    return Material(
      color: destacado ? p.primario : p.superficie,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icono, color: destacado ? Colors.white : p.acento),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _ChipMapa extends StatelessWidget {
  const _ChipMapa({required this.icono, required this.texto, required this.onTap, this.activo = false});
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    final fg = activo ? Colors.white : p.acento;
    return Material(
      color: activo ? p.primario : p.superficie,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(texto, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EtiquetaSalon extends StatelessWidget {
  const _EtiquetaSalon({required this.numero, required this.activa});
  final String numero;
  final bool activa;

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activa ? p.primario : p.superficie.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Text(
        numero,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: activa ? Colors.white : p.acento),
      ),
    );
  }
}

class _MarcadorOrigen extends StatelessWidget {
  const _MarcadorOrigen();

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _cian.withValues(alpha: 0.35)),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.primario, border: Border.all(color: Colors.white, width: 3)),
      ),
    );
  }
}

class _MarcadorUsuario extends StatelessWidget {
  const _MarcadorUsuario();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _usuarioAzul.withValues(alpha: 0.22)),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _usuarioAzul,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
      ),
    );
  }
}

class _Atribucion extends StatelessWidget {
  const _Atribucion();

  @override
  Widget build(BuildContext context) {
    final p = Paleta.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: p.superficie.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
      child: Text(p.oscuro ? _textoAtribucionOscuro : _textoAtribucion, style: TextStyle(fontSize: 10.5, color: p.texto)),
    );
  }
}

/// Brújula: aparece solo cuando el mapa está girado y lo regresa al norte.
class _BotonBrujula extends StatelessWidget {
  const _BotonBrujula({required this.rotacion, required this.onPressed});
  final ValueListenable<double> rotacion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: rotacion,
      builder: (context, grados, _) {
        final g = grados % 360;
        if (g < 0.5 || g > 359.5) return const SizedBox.shrink();
        final p = Paleta.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.superficie,
            elevation: 4,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Orientar al norte',
              onPressed: onPressed,
              icon: Transform.rotate(
                angle: grados * math.pi / 180,
                child: const Icon(Icons.navigation, color: _rosa),
              ),
            ),
          ),
        );
      },
    );
  }
}

