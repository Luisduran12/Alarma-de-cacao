import 'package:flutter/material.dart';

import '../services/lugar_service.dart';

/// Muestra el nombre del lugar de unas coordenadas: el del servidor si ya se
/// resolvió, o la referencia más cercana de la lista offline (DANE). Funciona sin
/// internet y siempre dice cuando es solo una referencia aproximada.
class LugarTexto extends StatefulWidget {
  final double latitud;
  final double longitud;

  /// Se puede cambiar en pruebas.
  final LugarService? servicio;

  const LugarTexto({super.key, required this.latitud, required this.longitud, this.servicio});

  @override
  State<LugarTexto> createState() => _LugarTextoState();
}

class _LugarTextoState extends State<LugarTexto> {
  late Future<NombreLugar?> _nombre;

  @override
  void initState() {
    super.initState();
    _nombre = _buscar();
  }

  @override
  void didUpdateWidget(LugarTexto old) {
    super.didUpdateWidget(old);
    if (old.latitud != widget.latitud || old.longitud != widget.longitud) _nombre = _buscar();
  }

  Future<NombreLugar?> _buscar() async {
    try {
      return await (widget.servicio ?? LugarService()).nombreDe(widget.latitud, widget.longitud);
    } catch (_) {
      return null; // un fallo aquí nunca debe romper la pantalla
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return FutureBuilder<NombreLugar?>(
      future: _nombre,
      builder: (context, snap) {
        final n = snap.data;
        if (n == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(n.texto, style: tema.textTheme.bodyMedium)),
                ],
              ),
              Text(
                n.aproximado
                    ? 'Referencia aproximada: el centro poblado o municipio más cercano, no la vereda. '
                        'Fuente: ${n.fuente}.'
                    : n.fuente,
                style: tema.textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
