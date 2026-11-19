import 'package:flutter/material.dart';

import '../models/analisis_foto.dart';

/// El semáforo del análisis: color, ícono Y palabras (el color solo no lo ve todo el mundo).
class SemaforoFoto extends StatelessWidget {
  final Semaforo semaforo;
  final bool compacto;
  const SemaforoFoto(this.semaforo, {super.key, this.compacto = false});

  static String texto(Semaforo s) => switch (s) {
        Semaforo.verde => 'Sin problemas a la vista',
        Semaforo.amarillo => 'Hay algo que vigilar',
        Semaforo.rojo => 'Problema serio: consulte al técnico',
      };

  static IconData icono(Semaforo s) => switch (s) {
        Semaforo.verde => Icons.check_circle,
        Semaforo.amarillo => Icons.warning_amber_rounded,
        Semaforo.rojo => Icons.error,
      };

  static (Color, Color) colores(Semaforo s) => switch (s) {
        Semaforo.verde => (const Color(0xFFD7F0D9), const Color(0xFF1B5E20)),
        Semaforo.amarillo => (const Color(0xFFFFF0B8), const Color(0xFF6B4F00)),
        Semaforo.rojo => (const Color(0xFFFFD9D6), const Color(0xFF8C1D18)),
      };

  @override
  Widget build(BuildContext context) {
    final (fondo, color) = colores(semaforo);
    final estilo = compacto ? Theme.of(context).textTheme.bodyMedium : Theme.of(context).textTheme.titleLarge;
    return Semantics(
      container: true,
      label: 'Semáforo: ${texto(semaforo)}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: compacto ? 6 : 14),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: compacto ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(icono(semaforo), color: color, size: compacto ? 20 : 32),
            const SizedBox(width: 10),
            Flexible(child: Text(texto(semaforo), style: estilo?.copyWith(color: color, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }
}
