import 'package:flutter/material.dart';
import 'package:orienta_tec/core/mapa_datos.dart';

/// Ícono que el administrador puede elegir para un salón.
class OpcionIcono {
  const OpcionIcono(this.clave, this.nombre, this.icono);
  final String clave;
  final String nombre;
  final IconData icono;
}

/// Clave especial: mostrar siempre el nombre o número (sin ícono).
const String iconoSoloTexto = 'numero';

const List<OpcionIcono> opcionesIcono = [
  OpcionIcono('aula', 'Salón / aula', Icons.class_outlined),
  OpcionIcono('oficina', 'Oficina', Icons.business_center_outlined),
  OpcionIcono('bano', 'Baños', Icons.wc),
  OpcionIcono('laboratorio', 'Laboratorio (general)', Icons.biotech_outlined),
  OpcionIcono('lab_quimica', 'Lab. de Química', Icons.science_outlined),
  OpcionIcono('lab_mecanica', 'Lab. de Mecánica', Icons.settings_outlined),
  OpcionIcono('lab_electronica', 'Lab. de Electrónica', Icons.memory),
  OpcionIcono('lab_electrica', 'Lab. de Eléctrica', Icons.bolt),
  OpcionIcono('lab_sistemas', 'Lab. de Sistemas e Informática', Icons.code),
  OpcionIcono('computo', 'Centro de cómputo', Icons.computer_outlined),
  OpcionIcono('biblioteca', 'Biblioteca', Icons.local_library_outlined),
  OpcionIcono('cafeteria', 'Cafetería', Icons.restaurant_outlined),
  OpcionIcono('auditorio', 'Auditorio', Icons.theater_comedy_outlined),
  OpcionIcono('enfermeria', 'Enfermería', Icons.medical_services_outlined),
  OpcionIcono('escalera', 'Escaleras', Icons.stairs_outlined),
  OpcionIcono('taller', 'Taller', Icons.build_outlined),
  OpcionIcono('servicio', 'Servicios', Icons.support_agent_outlined),
];

IconData? _porClave(String clave) {
  for (final o in opcionesIcono) {
    if (o.clave == clave) return o.icono;
  }
  return null;
}

/// Clave del ícono de un salón: la que eligió el administrador o, si lo dejó
/// en "Automático", una según su tipo y nombre. Los salones normales llevan
/// 'aula'. Devuelve '' si el administrador pidió mostrar solo texto.
String claveIconoDeSalon(Salon s) {
  if (s.pin || s.icono == iconoSoloTexto) return '';
  if (s.icono.isNotEmpty) return s.icono;
  return _claveAutomatica(s);
}

/// Clave que se elige sola según el tipo y el nombre (sin mirar lo que haya
/// elegido el administrador).
String _claveAutomatica(Salon s) {
  final t = sinAcentos('${s.tipo} ${s.numero}');
  bool tiene(List<String> palabras) => palabras.any(t.contains);
  if (tiene(['bano', 'sanitario'])) return 'bano';
  if (tiene(['escalera'])) return 'escalera';
  if (tiene(['oficina', 'direccion', 'coordinacion', 'jefatura', 'departamento', 'depto'])) return 'oficina';
  if (tiene(['enfermeria', 'consultorio'])) return 'enfermeria';
  if (tiene(['biblioteca'])) return 'biblioteca';
  if (tiene(['cafeteria'])) return 'cafeteria';
  if (tiene(['auditorio', 'aula magna'])) return 'auditorio';
  if (tiene(['computo'])) return 'computo';
  // Laboratorios: el ícono depende de la carrera (también se mira el nombre
  // del edificio, para códigos como LQ1 o LC03).
  final esLab = t.contains('laboratorio') || sinAcentos(s.tipo).contains('laboratorio');
  if (esLab) {
    final l = sinAcentos('${s.numero} ${s.edificio}');
    bool en(List<String> palabras) => palabras.any(l.contains);
    if (en(['quimic'])) return 'lab_quimica';
    if (en(['mecanic'])) return 'lab_mecanica';
    if (en(['electronic'])) return 'lab_electronica';
    if (en(['electric'])) return 'lab_electrica';
    if (en(['sistema', 'informatic', 'computacion'])) return 'lab_sistemas';
    return 'laboratorio';
  }
  return 'aula';
}

/// Ícono para las miniaturas (buscador, listas y ficha). null = solo texto.
IconData? iconoDeSalon(Salon s) {
  final c = claveIconoDeSalon(s);
  return c.isEmpty ? null : _porClave(c);
}

/// Tipos de lugar que llevan ícono también sobre el mapa. Los demás salones
/// muestran su número en la cajita.
const Set<String> _clavesIconoEnMapa = {'oficina', 'cafeteria', 'biblioteca', 'auditorio', 'bano'};

/// Ícono que se dibuja dentro de la cajita del mapa (null = mostrar el número).
/// Lo que el administrador elija para el mapa manda; en "Automático" solo
/// llevan ícono los tipos de la lista de arriba.
IconData? iconoEnMapa(Salon s) {
  if (s.pin || s.iconoMapa == iconoSoloTexto) return null;
  if (s.iconoMapa.isNotEmpty) return _porClave(s.iconoMapa);
  final c = _claveAutomatica(s);
  return _clavesIconoEnMapa.contains(c) ? _porClave(c) : null;
}
