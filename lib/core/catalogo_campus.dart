import 'dart:ui' show Offset;

import 'package:orienta_tec/core/mapa_datos.dart';

// ---------------------------------------------------------------------------
// Catálogo inicial de salones
// ---------------------------------------------------------------------------
// Sirve para cargar de un jalón los salones de los edificios que ya están
// dibujados en el mapa (menú del administrador: "Cargar catálogo inicial").
// Después todo se edita desde el administrador; este archivo solo se usa una vez.
//
// Cada columna es una fila de salones a lo largo del edificio, de arriba hacia
// abajo. Los edificios se buscan por una palabra de su nombre registrado.

class _ColumnaCatalogo {
  const _ColumnaCatalogo(this.piso, this.salones);
  final int piso;
  final List<String> salones;
}

class _EdificioCatalogo {
  const _EdificioCatalogo({
    required this.nombre,
    required this.claves,
    this.excluir = const <String>[],
    required this.columnas,
  });

  /// Nombre que tendrá el bloque.
  final String nombre;

  /// Palabras (sin acentos, minúsculas) que identifican al edificio ya registrado.
  final List<String> claves;
  final List<String> excluir;
  final List<_ColumnaCatalogo> columnas;
}

const List<_EdificioCatalogo> _catalogo = [
  _EdificioCatalogo(
    nombre: 'Centro de Cómputo',
    claves: ['comput'],
    columnas: [
      _ColumnaCatalogo(1, ['L03', 'L05', 'L08', 'L02', 'L09']),
      _ColumnaCatalogo(1, ['L01', 'L07', 'L04', 'L06', 'L10']),
    ],
  ),
  _EdificioCatalogo(
    nombre: 'Centro de Idiomas',
    claves: ['idioma'],
    columnas: [
      _ColumnaCatalogo(1, ['Oficina Idiomas', 'Room 1', 'Room 2']),
    ],
  ),
  _EdificioCatalogo(
    nombre: 'Edificio Industrial',
    claves: ['industrial'],
    excluir: ['laboratorio', 'ergonomia', 'simulacion'],
    columnas: [
      _ColumnaCatalogo(1, ['MT1', 'MT2']),
    ],
  ),
];

/// Reemplaza los salones de los edificios del catálogo que ya existen en
/// [datos]. El contorno se toma del edificio dibujado. Devuelve los datos
/// nuevos y los nombres de los bloques que se cargaron.
({DatosMapa datos, List<String> aplicados}) catalogoInicial(DatosMapa datos) {
  var salones = List<Salon>.of(datos.salones);
  final aplicados = <String>[];

  for (final cat in _catalogo) {
    final coinciden = <Salon>[
      for (final s in salones)
        if (cat.claves.any((k) => sinAcentos(s.edificio).contains(k)) &&
            !cat.excluir.any((k) => sinAcentos(s.edificio).contains(k)))
          s,
    ];
    if (coinciden.isEmpty) continue;

    final contornoImagen = contornoDeBloque(coinciden, true, propio: true);
    final contornoMapa = contornoDeBloque(coinciden, false, propio: true);

    final nuevos = <Salon>[];
    for (var k = 0; k < cat.columnas.length; k++) {
      final c = cat.columnas[k];
      for (final n in c.salones) {
        nuevos.add(Salon(
          numero: n,
          edificio: cat.nombre,
          piso: c.piso,
          columna: k,
          tipo: tipoSugerido(n),
          poligonoImagen: List<Offset>.of(contornoImagen),
          poligonoMapa: List<Offset>.of(contornoMapa),
        ));
      }
    }

    salones = [
      for (final s in salones)
        if (!coinciden.any((c) => identical(c, s))) s,
      ...nuevos,
    ];
    aplicados.add(cat.nombre);
  }
  return (datos: datos.copyWith(salones: salones), aplicados: aplicados);
}
