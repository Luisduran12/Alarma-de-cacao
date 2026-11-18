import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/guia_prueba_corte.dart';

/// Dibujos esquemáticos del PROCEDIMIENTO de la prueba de corte. No son fotos
/// ni muestran el color real de ningún grano (eso no está verificado): usan los
/// colores de la app.
class IlustracionCorte extends StatelessWidget {
  final TipoIlustracion tipo;
  final double alto;
  const IlustracionCorte({super.key, required this.tipo, this.alto = 120});

  static String descripcion(TipoIlustracion t) => switch (t) {
        TipoIlustracion.muestreo => 'Dibujo: un cajón visto desde arriba con 9 puntos marcados, y una flecha '
            'hacia un montón de 100 granos.',
        TipoIlustracion.corte => 'Dibujo: un grano con una línea punteada a lo largo, y una flecha hacia '
            'sus dos mitades abiertas.',
        TipoIlustracion.conteo => 'Dibujo: una cuadrícula de 100 puntos con 70 marcados, como ejemplo del 70 %.',
        TipoIlustracion.temperatura => 'Dibujo: una línea de temperatura que sube y al final baja.',
        TipoIlustracion.ninguna => '',
      };

  @override
  Widget build(BuildContext context) {
    if (tipo == TipoIlustracion.ninguna) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    return Semantics(
      // container: sin esto la descripción se fusiona con la tarjeta que la contiene
      // y un lector de pantalla anunciaría toda la tarjeta como si fuera una imagen.
      container: true,
      image: true,
      label: descripcion(tipo),
      child: ExcludeSemantics(
        child: SizedBox(
          height: alto,
          width: double.infinity,
          child: CustomPaint(
            painter: _Pintor(tipo, principal: c.primary, trazo: c.onSurfaceVariant, fondo: c.surfaceContainerHighest),
          ),
        ),
      ),
    );
  }
}

class _Pintor extends CustomPainter {
  final TipoIlustracion tipo;
  final Color principal, trazo, fondo;
  _Pintor(this.tipo, {required this.principal, required this.trazo, required this.fondo});

  Paint get _relleno => Paint()..color = principal;
  Paint get _linea => Paint()
    ..color = trazo
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;

  void _flecha(Canvas canvas, Offset a, Offset b) {
    canvas.drawLine(a, b, _linea);
    final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
    for (final d in [2.6, -2.6]) {
      canvas.drawLine(b, b - Offset(math.cos(ang + d * 0.2) * 12, math.sin(ang + d * 0.2) * 12), _linea);
    }
  }

  void _texto(Canvas canvas, String t, Offset centro, {double tam = 14}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: trazo, fontSize: tam, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centro - Offset(tp.width / 2, tp.height / 2));
  }

  void _grano(Canvas canvas, Offset c, double rx, double ry, {double giro = 0, bool lleno = true}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(giro);
    final r = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
    if (lleno) canvas.drawOval(r, _relleno);
    canvas.drawOval(r, _linea..strokeWidth = 2);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cy = h / 2;
    switch (tipo) {
      case TipoIlustracion.muestreo:
        // Cajón visto desde arriba con 9 puntos de muestreo.
        final caja = Rect.fromCenter(center: Offset(w * 0.28, cy), width: w * 0.34, height: h * 0.78);
        canvas.drawRRect(RRect.fromRectAndRadius(caja, const Radius.circular(8)), Paint()..color = fondo);
        canvas.drawRRect(RRect.fromRectAndRadius(caja, const Radius.circular(8)), _linea);
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 3; j++) {
            canvas.drawCircle(
              Offset(caja.left + caja.width * (0.2 + 0.3 * i), caja.top + caja.height * (0.2 + 0.3 * j)),
              6,
              _relleno,
            );
          }
        }
        _flecha(canvas, Offset(w * 0.5, cy), Offset(w * 0.64, cy));
        // Montón de granos
        final rnd = math.Random(7);
        for (var k = 0; k < 14; k++) {
          final a = rnd.nextDouble() * math.pi * 2, d = math.sqrt(rnd.nextDouble()) * h * 0.3;
          _grano(canvas, Offset(w * 0.8 + math.cos(a) * d, cy + math.sin(a) * d), 7, 4.5, giro: a);
        }
        _texto(canvas, '100 granos', Offset(w * 0.8, h - 6), tam: 12);
      case TipoIlustracion.corte:
        // Grano entero con línea de corte a lo largo → dos mitades abiertas.
        final c1 = Offset(w * 0.25, cy);
        _grano(canvas, c1, h * 0.36, h * 0.2, giro: -0.4);
        canvas.save();
        canvas.translate(c1.dx, c1.dy);
        canvas.rotate(-0.4);
        final punteada = _linea..strokeWidth = 2;
        for (var x = -h * 0.42; x < h * 0.42; x += 12) {
          canvas.drawLine(Offset(x, 0), Offset(x + 6, 0), punteada);
        }
        canvas.restore();
        _flecha(canvas, Offset(w * 0.45, cy), Offset(w * 0.58, cy));
        _grano(canvas, Offset(w * 0.72, cy - h * 0.2), h * 0.34, h * 0.13, giro: -0.4, lleno: false);
        _grano(canvas, Offset(w * 0.78, cy + h * 0.2), h * 0.34, h * 0.13, giro: -0.4, lleno: false);
      case TipoIlustracion.conteo:
        // 10 x 10 granos; 70 marcados (ejemplo).
        final lado = math.min(h * 0.9, w * 0.45), paso = lado / 10;
        final x0 = w * 0.08, y0 = (h - lado) / 2;
        for (var i = 0; i < 100; i++) {
          final f = i ~/ 10, col = i % 10;
          final c = Offset(x0 + col * paso + paso / 2, y0 + f * paso + paso / 2);
          if (i < 70) {
            canvas.drawCircle(c, paso * 0.36, _relleno);
          } else {
            canvas.drawCircle(c, paso * 0.34, _linea..strokeWidth = 1.6);
          }
        }
        _texto(canvas, '70 de 100', Offset(w * 0.74, cy - 12), tam: 18);
        _texto(canvas, '= 70 %', Offset(w * 0.74, cy + 12), tam: 18);
      case TipoIlustracion.temperatura:
        // Línea que sube y baja al final, con ejes.
        final izq = w * 0.08, der = w * 0.95, arriba = h * 0.12, abajo = h * 0.86;
        canvas.drawLine(Offset(izq, arriba), Offset(izq, abajo), _linea..strokeWidth = 1.8);
        canvas.drawLine(Offset(izq, abajo), Offset(der, abajo), _linea..strokeWidth = 1.8);
        final puntos = [0.0, 0.15, 0.38, 0.62, 0.8, 0.9, 1.0];
        final alturas = [0.9, 0.7, 0.45, 0.25, 0.2, 0.3, 0.55];
        final ruta = Path();
        for (var i = 0; i < puntos.length; i++) {
          final p = Offset(izq + (der - izq) * puntos[i] * 0.97, arriba + (abajo - arriba) * alturas[i]);
          i == 0 ? ruta.moveTo(p.dx, p.dy) : ruta.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(ruta, Paint()..color = principal..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeCap = StrokeCap.round);
        _texto(canvas, 'baja al final', Offset(w * 0.78, abajo - 10), tam: 12);
        _texto(canvas, 'horas', Offset((izq + der) / 2, h - 2), tam: 11);
      case TipoIlustracion.ninguna:
        break;
    }
  }

  @override
  bool shouldRepaint(_Pintor old) => old.tipo != tipo || old.principal != principal || old.trazo != trazo;
}
