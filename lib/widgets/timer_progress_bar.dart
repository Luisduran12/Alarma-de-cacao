import 'dart:async';

import 'package:flutter/material.dart';

/// Barra de progreso de un ciclo calculada desde la hora de INICIO GUARDADA.
///
/// Antes dependía de un temporizador en memoria (RealTimeTimer) y volvía a 0
/// al cerrar la app. Ahora el progreso es (ahora - inicio) / (fin - inicio):
/// al reabrir la app muestra exactamente el avance real.
/// El Timer interno solo refresca la pantalla; no lleva la cuenta.
class TimerProgressBar extends StatefulWidget {
  final DateTime inicio;
  final DateTime fin;
  final VoidCallback? onTimerComplete;
  final Color? progressColor;
  final Color? backgroundColor;
  final double height;
  final TextStyle? textStyle;

  /// Para pruebas: permite fijar "ahora".
  final DateTime Function() reloj;

  const TimerProgressBar({
    super.key,
    required this.inicio,
    required this.fin,
    this.onTimerComplete,
    this.progressColor,
    this.backgroundColor,
    this.height = 8.0,
    this.textStyle,
    this.reloj = DateTime.now,
  });

  /// Progreso entre 0.0 y 1.0 para un instante dado.
  static double calcularProgreso(DateTime inicio, DateTime fin, DateTime ahora) {
    final total = fin.difference(inicio).inSeconds;
    if (total <= 0) return 1.0;
    return (ahora.difference(inicio).inSeconds / total).clamp(0.0, 1.0);
  }

  @override
  State<TimerProgressBar> createState() => _TimerProgressBarState();
}

class _TimerProgressBarState extends State<TimerProgressBar> {
  Timer? _refresco;
  bool _completadoNotificado = false;

  @override
  void initState() {
    super.initState();
    _refresco = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  String _formato(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final dias = d.inDays;
    final horas = d.inHours.remainder(24);
    final minutos = d.inMinutes.remainder(60);
    return dias > 0 ? '${dias}d ${horas}h ${minutos}m' : '${horas}h ${minutos}m';
  }

  @override
  Widget build(BuildContext context) {
    final ahora = widget.reloj();
    final progreso = TimerProgressBar.calcularProgreso(widget.inicio, widget.fin, ahora);

    if (progreso >= 1.0 && !_completadoNotificado) {
      _completadoNotificado = true;
      if (widget.onTimerComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onTimerComplete!());
      }
    }

    final estilo = widget.textStyle ?? Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progreso,
          backgroundColor: widget.backgroundColor ?? Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            widget.progressColor ?? Theme.of(context).colorScheme.primary,
          ),
          minHeight: widget.height,
          semanticsLabel: 'Progreso del ciclo',
          semanticsValue: '${(progreso * 100).round()}%',
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Transcurrido: ${_formato(ahora.difference(widget.inicio))}', style: estilo),
            Text(
              progreso >= 1.0 ? 'Ciclo terminado' : 'Faltan: ${_formato(widget.fin.difference(ahora))}',
              style: estilo?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}
