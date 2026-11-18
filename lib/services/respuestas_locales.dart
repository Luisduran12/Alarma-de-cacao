import 'package:intl/intl.dart';

import '../data/base_conocimiento.dart';
import '../data/guia_prueba_corte.dart';
import '../data/referencias_curva.dart';
import '../models/lote.dart';
import '../models/mensaje_chat.dart';
import '../models/volteada.dart';
import 'buscador_conocimiento.dart';
import 'resumen_curva.dart';

enum IntencionRapida { comoVa, cuandoVolteo, temperaturaNormal, pruebaCorte, comoSeco }

class PreguntaRapida {
  final String etiqueta;
  final IntencionRapida intencion;
  const PreguntaRapida(this.etiqueta, this.intencion);

  /// Los cinco botones del chat, en este orden.
  static const todas = [
    PreguntaRapida('¿Cómo va mi lote?', IntencionRapida.comoVa),
    PreguntaRapida('¿Cuándo volteo?', IntencionRapida.cuandoVolteo),
    PreguntaRapida('¿Está normal mi temperatura?', IntencionRapida.temperaturaNormal),
    PreguntaRapida('¿Cómo hago la prueba de corte?', IntencionRapida.pruebaCorte),
    PreguntaRapida('¿Cómo seco mi cacao?', IntencionRapida.comoSeco),
  ];
}

/// Una respuesta armada en el teléfono, sin internet y sin IA.
class RespuestaLocal {
  final String texto;
  final List<FuenteCitada> fuentes;

  /// false si no se encontró nada en la guía (el texto lo dice).
  final bool encontrada;
  const RespuestaLocal(this.texto, this.fuentes, {this.encontrada = true});
}

/// Contesta con lo que hay en el teléfono: datos del propio lote, la base de conocimiento
/// (cada fragmento con su fuente), las preguntas frecuentes y el glosario. No inventa: si no
/// encuentra nada, lo dice. Las comparaciones con rangos usan [ReferenciasCurva], que es la
/// única tabla de rangos de la app.
class RespuestasLocales {
  /// Se muestra junto a las respuestas que salen de aquí cuando la IA no se pudo usar.
  static const avisoSinIA = 'Esta respuesta sale de la guía guardada en el teléfono. La IA necesita conexión a internet.';

  static const sinResultado = 'No encontré eso en la guía guardada en el teléfono. Con internet puede preguntarle a la IA. '
      'También puede consultar a su técnico, a su asociación o a FEDECACAO.';

  final BaseConocimiento base;
  final BuscadorConocimiento buscador;
  RespuestasLocales(this.base) : buscador = BuscadorConocimiento(base);

  static final _fecha = DateFormat('d/MM \'a las\' HH:mm');
  static String _num(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  static String _horas(double h) => ResumenCurva.duracion(h);

  /// Responde una pregunta escrita. Si es igual a un botón rápido, usa los datos del [lote].
  RespuestaLocal responder(String pregunta, {Lote? lote, DateTime? ahora}) {
    final norm = BuscadorConocimiento.normalizar(pregunta);
    if (norm.isEmpty) return const RespuestaLocal(sinResultado, [], encontrada: false);

    for (final r in PreguntaRapida.todas) {
      if (BuscadorConocimiento.normalizar(r.etiqueta) == norm) return rapida(r.intencion, lote: lote, ahora: ahora);
    }

    // Una pregunta escrita igual que una de la lista gana siempre; si no, una definición
    // ("¿qué es la temperatura ambiente?") se contesta con el glosario antes que con la lista.
    final faq = buscador.mejorFaq(pregunta);
    final exacta = faq != null && faq.preguntas.any((p) => BuscadorConocimiento.normalizar(p) == norm);
    final esDefinicion = RegExp(r'^(que es|que son|que significa|que quiere decir|a que se refiere)\b|\bsignifica\b').hasMatch(norm);
    final termino = buscador.terminoEn(pregunta);
    if (!exacta && esDefinicion && termino != null) return _deTermino(termino);
    if (faq != null) return _deFragmentos([for (final id in faq.fragmentos) base.fragmentoPorId(id)!]);

    final frs = buscador.buscar(pregunta, limite: 2);
    if (frs.isNotEmpty) return _deFragmentos(frs);

    if (termino != null) return _deTermino(termino);
    return const RespuestaLocal(sinResultado, [], encontrada: false);
  }

  RespuestaLocal rapida(IntencionRapida i, {Lote? lote, DateTime? ahora}) {
    final t = ahora ?? DateTime.now();
    return switch (i) {
      IntencionRapida.comoVa => _comoVa(lote, t),
      IntencionRapida.cuandoVolteo => _cuandoVolteo(lote, t),
      IntencionRapida.temperaturaNormal => _temperatura(lote, t),
      IntencionRapida.pruebaCorte => _deFaq('faq-05', extra: GuiaPruebaCorte.avisoNtc),
      IntencionRapida.comoSeco => _deFaq('faq-06'),
    };
  }

  // ---- armado ----

  RespuestaLocal _deFaq(String id, {String? extra}) {
    final f = base.faq.firstWhere((x) => x.id == id);
    return _deFragmentos([for (final fid in f.fragmentos) base.fragmentoPorId(fid)!], extra: extra);
  }

  RespuestaLocal _deFragmentos(List<Fragmento> frs, {String? intro, String? extra}) {
    final b = StringBuffer();
    if (intro != null) b.writeln('$intro\n');
    for (final f in frs) {
      b.writeln('• ${f.texto}\n  (Fuente: ${f.fuente})\n');
    }
    if (extra != null) b.writeln(extra);
    return RespuestaLocal(b.toString().trim(), _fuentes(frs));
  }

  List<FuenteCitada> _fuentes(List<Fragmento> frs) => [for (final f in frs) FuenteCitada(f.id, f.fuente)];

  RespuestaLocal _deTermino(TerminoGlosario g) {
    final fuente = g.fuenteId == null ? 'definición de esta app' : g.fuente;
    return RespuestaLocal('${g.termino}: ${g.definicion}\n  (Fuente: $fuente)',
        g.fuenteId == null ? const [] : [FuenteCitada('glosario', g.fuente)]);
  }

  Fragmento _frag(String id) => base.fragmentoPorId(id)!;

  // ---- respuestas con datos del lote ----

  List<Volteada> _medidos(Lote lote) => lote.volteadas.where((v) => v.confirmada).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));

  RespuestaLocal _comoVa(Lote? lote, DateTime ahora) {
    if (lote == null) return const RespuestaLocal('Abra un lote para ver cómo va.', [], encontrada: false);
    final medidos = _medidos(lote);
    if (medidos.isEmpty) {
      return const RespuestaLocal('Todavía no hay registros de temperatura en este lote, así que no puedo decir cómo va. '
          'Anote la primera medida con el termómetro dentro de la masa.', []);
    }
    final inicio = lote.inicioCiclo ?? lote.createdAt;
    final etapa = medidos.last.etapa;
    final horas = ahora.difference(inicio).inMinutes / 60.0;
    final r = ResumenCurva.calcular(lote.volteadas, inicio);
    final texto = StringBuffer('El lote está en ${Etapa.nombre(etapa).toLowerCase()}, lleva ${_horas(horas < 0 ? 0 : horas)} '
        'y tiene ${r.registros} ${r.registros == 1 ? 'registro' : 'registros'}.\n');
    for (final f in r.frases()) {
      texto.writeln('• $f');
    }
    final fuentes = <FuenteCitada>[];
    if (r.horasConReferencia >= 1) {
      final ref = ReferenciasCurva.temperaturaPara(etapa);
      if (ref != null) {
        texto.writeln('\n(Fuente de la referencia: ${ref.fuente})');
        fuentes.add(FuenteCitada(etapa == Etapa.secado ? 'ref-secado' : 'ref-fermentacion', ref.fuente));
      }
    }
    return RespuestaLocal(texto.toString().trim(), fuentes);
  }

  RespuestaLocal _cuandoVolteo(Lote? lote, DateTime ahora) {
    String? intro;
    if (lote != null) {
      final pendientes = lote.volteadas.where((v) => !v.confirmada).toList()..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
      if (pendientes.isEmpty) {
        intro = 'Este lote no tiene volteadas programadas pendientes.';
      } else {
        final p = pendientes.first;
        final faltan = p.fechaProgramada.difference(ahora);
        intro = faltan.isNegative
            ? 'Tiene una volteada pendiente desde el ${_fecha.format(p.fechaProgramada)}. Si ya la hizo, confírmela en el lote.'
            : 'Su próxima alarma de volteo es el ${_fecha.format(p.fechaProgramada)} (en ${_horas(faltan.inMinutes / 60.0)}).';
      }
    }
    return _deFragmentos([_frag('vol-01'), _frag('vol-02')], intro: intro);
  }

  RespuestaLocal _temperatura(Lote? lote, DateTime ahora) {
    final medidos = lote == null ? <Volteada>[] : _medidos(lote);
    if (medidos.isEmpty) {
      final r = _deFragmentos([_frag('ferm-04')], intro: 'Todavía no hay temperatura registrada en este lote para comparar. Esto es lo que dice la guía:');
      return r;
    }
    final u = medidos.last;
    final inicio = lote!.inicioCiclo ?? lote.createdAt;
    final horas = u.fecha.difference(inicio).inMinutes / 60.0;
    final ref = ReferenciasCurva.temperaturaPara(u.etapa)!;
    final unidad = ref.unidad;
    final valor = '${_num(u.temperatura)} $unidad';
    final estado = ReferenciasCurva.estadoTemperatura(u.temperatura, horas, u.etapa);
    final intro = switch (estado) {
      EstadoRango.sinReferencia =>
        'Su última temperatura fue $valor (a las ${_horas(horas)}). En las primeras ${ref.desdeHora!.round()} horas '
            'de la fermentación no tengo un rango verificado para decir si es normal.',
      EstadoRango.dentro => 'Su última temperatura fue $valor (a las ${_horas(horas)}) y está dentro de la referencia '
          '(${_rango(ref)}).',
      EstadoRango.bajo => 'Su última temperatura fue $valor (a las ${_horas(horas)}) y está por debajo de la referencia '
          '(${_rango(ref)}).',
      EstadoRango.alto => ref.maximoEsLimite
          ? 'Su última temperatura fue $valor (a las ${_horas(horas)}) y está por encima del máximo de la referencia '
              '(${_rango(ref)}).'
          : 'Su última temperatura fue $valor (a las ${_horas(horas)}). Es más que ${_num(ref.maximo!)} $unidad, pero la '
              'fuente dice "${_num(ref.maximo!)} $unidad o más", no un tope.',
    };
    final r = _deFragmentos([_frag(u.etapa == Etapa.secado ? 'sec-06' : 'ferm-04')],
        intro: '$intro\nLa temperatura es la de la masa o el grano, no la del ambiente.',
        extra: estado == EstadoRango.dentro ? null : 'Si tiene dudas, consulte a su técnico, asociación o FEDECACAO.');
    return r;
  }

  static String _rango(RangoReferencia r) {
    final u = r.unidad;
    if (r.minimo != null && r.maximo != null) {
      return r.maximoEsLimite ? 'de ${_num(r.minimo!)} a ${_num(r.maximo!)} $u' : 'desde ${_num(r.minimo!)} hasta ${_num(r.maximo!)} $u o más';
    }
    if (r.maximo != null) return 'máximo ${_num(r.maximo!)} $u';
    return 'mínimo ${_num(r.minimo!)} $u';
  }
}
