import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alarmacacao5_0/data/base_conocimiento.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/chat_service.dart';
import 'package:alarmacacao5_0/services/contexto_lote.dart';

const _id = '3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c';
final _inicio = DateTime(2026, 11, 10, 8);

Volteada _v(int hora, double t, double h,
        {String etapa = Etapa.fermentacion, bool conf = true, double? ph, double? brix, double? amb}) =>
    Volteada(
      id: 'v$hora${t.hashCode}', loteId: 'L', mensaje: '', temperatura: t, humedad: h, observacion: 'obs privada',
      fecha: _inicio.add(Duration(hours: hora)), fechaProgramada: _inicio.add(Duration(hours: hora)), confirmada: conf,
      etapa: etapa, latitud: 7.6031, longitud: -72.6011, ph: ph, brix: brix, tempAmbiente: amb,
    );

Lote _lote(List<Volteada> vs) => Lote(
    id: 'L', title: 'Lote de Don Pedro, finca La Esperanza', volteadas: vs, status: 'en proceso',
    createdAt: _inicio, inicioCiclo: _inicio);

Fragmento _frag(String id, {String texto = 'Voltee cada 24 horas.', String fuente = 'FHIA, InfoCacao No. 14 (2017), p. 4'}) =>
    Fragmento(id: id, tema: 'volteo', titulo: 't', texto: texto, fuente: fuente, fuenteId: 'fhia2017',
        citas: const [CitaTextual(1, 'x')], palabras: const ['volteo']);

void main() {
  group('ContextoLote', () {
    test('etapa, horas y registros; sin nombre del lote ni ubicación ni observaciones', () {
      final c = ContextoLote.desde(
          _lote([_v(24, 40.55, 85.0, ph: 4.5, brix: 10, amb: 26), _v(48, 45, 80)]), _inicio.add(const Duration(hours: 50)));
      expect(c.etapa, 'fermentacion');
      expect(c.horas, 50);
      expect(c.registros, hasLength(2));
      expect(c.registros.first, {'horas': 24.0, 'temperatura': 40.6, 'humedad': 85.0, 'ph': 4.5, 'brix': 10.0, 'tempAmbiente': 26.0});
      expect(c.registros.last.keys.toSet(), {'horas', 'temperatura', 'humedad'});
      final texto = jsonEncode(c.toJson());
      for (final prohibido in ['Pedro', 'Esperanza', 'obs privada', '7.6', '72.6', 'lat', 'lng', 'titulo', 'title']) {
        expect(texto, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('solo cuenta registros confirmados y los ordena por fecha', () {
      final c = ContextoLote.desde(_lote([_v(48, 45, 80), _v(24, 40, 85), _v(72, 0, 0, conf: false)]), _inicio.add(const Duration(hours: 80)));
      expect(c.registros.map((r) => r['horas']), [24.0, 48.0]);
    });

    test('máximo 8 registros: los más recientes', () {
      final c = ContextoLote.desde(_lote([for (var i = 1; i <= 12; i++) _v(i, 30.0 + i, 60)]), _inicio.add(const Duration(hours: 13)));
      expect(c.registros, hasLength(8));
      expect(c.registros.first['horas'], 5.0);
      expect(c.registros.last['horas'], 12.0);
    });

    test('la etapa es la del último registro; sin registros, fermentación', () {
      expect(ContextoLote.desde(_lote([_v(100, 30, 60, etapa: Etapa.secado)]), _inicio.add(const Duration(hours: 101))).etapa, 'secado');
      expect(ContextoLote.desde(_lote([]), _inicio).etapa, 'fermentacion');
      expect(ContextoLote.desde(_lote([]), _inicio).registros, isEmpty);
    });

    test('valores fuera del rango del servidor no se mandan', () {
      final c = ContextoLote.desde(
          _lote([_v(10, 95, 60), _v(11, 30, 130), _v(12, 30, 60, ph: 20, brix: 150, amb: 90), _v(13, double.nan, 60)]),
          _inicio.add(const Duration(hours: 14)));
      expect(c.registros, hasLength(1));
      expect(c.registros.single.keys.toSet(), {'horas', 'temperatura', 'humedad'});
    });

    test('horas nunca negativas ni mayores a 3000', () {
      expect(ContextoLote.desde(_lote([]), _inicio.subtract(const Duration(hours: 5))).horas, 0);
      expect(ContextoLote.desde(_lote([]), _inicio.add(const Duration(days: 400))).horas, 3000);
    });
  });

  group('ChatService', () {
    late List<http.Request> peticiones;
    late http.Response Function(http.Request) responder;

    ChatService servicio({String url = 'https://api.cacaolight.example/v1', Duration? timeout}) => ChatService(
          cliente: MockClient((r) async {
            peticiones.add(r);
            return responder(r);
          }),
          urlServidor: url,
          timeout: timeout,
          idInstalacion: () async => _id,
        );

    http.Response ok(Map<String, Object?> j, {int estado = 200, Map<String, String> h = const {}}) => http.Response.bytes(
        utf8.encode(jsonEncode(j)), estado, headers: {'content-type': 'application/json; charset=utf-8', ...h});

    setUp(() {
      peticiones = [];
      responder = (_) => ok({'respuesta': 'Voltee cada 24 horas [F1].', 'fuentes': [{'id': 'F1', 'fuente': 'x'}], 'truncada': false, 'aviso': 'a'});
    });

    test('POST a /chat con X-Install-Id y JSON; ruta correcta aunque la URL base termine en /', () async {
      await servicio().preguntar(mensaje: '¿Cuándo volteo?');
      await servicio(url: 'https://api.cacaolight.example/v1/').preguntar(mensaje: 'hola');
      expect(peticiones[0].method, 'POST');
      expect(peticiones[0].url.toString(), 'https://api.cacaolight.example/v1/chat');
      expect(peticiones[1].url.toString(), 'https://api.cacaolight.example/v1/chat');
      expect(peticiones[0].headers['X-Install-Id'], _id);
      expect(peticiones[0].headers['Content-Type'], contains('application/json'));
      expect(peticiones[0].url.query, isEmpty);
    });

    test('el cuerpo solo tiene los campos del contrato y nada del lote', () async {
      final c = ContextoLote.desde(_lote([_v(24, 40, 85)]), _inicio.add(const Duration(hours: 30)));
      await servicio().preguntar(
        mensaje: '  ¿Está normal mi temperatura?  ',
        contexto: c,
        historial: [{'rol': 'usuario', 'texto': 'hola'}, {'rol': 'asistente', 'texto': 'buenas'}],
        fragmentos: [_frag('ferm-04'), _frag('vol-01')],
      );
      final cuerpo = jsonDecode(peticiones.single.body) as Map<String, dynamic>;
      expect(cuerpo.keys.toSet(), {'mensaje', 'contexto', 'historial', 'fragmentos'});
      expect(cuerpo['mensaje'], '¿Está normal mi temperatura?');
      expect((cuerpo['contexto'] as Map).keys.toSet(), {'etapa', 'horas', 'registros'});
      expect((cuerpo['fragmentos'] as List).map((f) => f['id']), ['F1', 'F2']);
      expect(((cuerpo['fragmentos'] as List).first as Map).keys.toSet(), {'id', 'fuente', 'texto'});
      final crudo = peticiones.single.body;
      for (final prohibido in ['Pedro', 'Esperanza', 'obs privada', '7.60', '72.60', _id]) {
        expect(crudo, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('sin contexto, historial ni fragmentos solo manda el mensaje', () {
      expect(ChatService.armarCuerpo(mensaje: 'hola'), {'mensaje': 'hola'});
    });

    test('respeta los límites: mensaje 500, historial 6, fragmentos 5, textos recortados', () {
      final c = ChatService.armarCuerpo(
        mensaje: 'a' * 900,
        historial: [for (var i = 0; i < 9; i++) {'rol': 'usuario', 'texto': 't$i'}],
        fragmentos: [for (var i = 0; i < 8; i++) _frag('f$i', texto: 'x' * 2000, fuente: 'y' * 300)],
      );
      expect((c['mensaje'] as String).length, 500);
      expect(c['historial'] as List, hasLength(6));
      expect(((c['historial'] as List).first as Map)['texto'], 't3');
      final fr = c['fragmentos'] as List;
      expect(fr, hasLength(5));
      expect((fr.first['texto'] as String).length, 1500);
      expect((fr.first['fuente'] as String).length, 200);
    });

    test('devuelve el texto y traduce F1 a la fuente real; ignora citas que no envió', () async {
      responder = (_) => ok({
            'respuesta': ' Voltee cada 24 horas [F1] y [F9]. ',
            'fuentes': [{'id': 'F1', 'fuente': 'lo que diga el servidor'}, {'id': 'F9', 'fuente': 'inventada'}, {'id': 'F1', 'fuente': 'repetida'}],
            'truncada': true,
            'aviso': 'otro aviso',
          });
      final r = await servicio().preguntar(mensaje: 'x', fragmentos: [_frag('vol-01', fuente: 'FHIA, p. 4')]);
      expect(r.texto, 'Voltee cada 24 horas [F1] y [F9].');
      expect(r.fuentes.map((f) => f.id), ['vol-01']);
      expect(r.fuentes.single.fuente, 'FHIA, p. 4');
      expect(r.truncada, isTrue);
    });

    test('sin servidor configurado: error claro y no sale ninguna petición', () async {
      final s = ChatService(cliente: MockClient((r) async => fail('no debe salir')), urlServidor: '', idInstalacion: () async => _id);
      expect(s.servidorConfigurado, isFalse);
      await expectLater(s.preguntar(mensaje: 'x'), throwsA(isA<ChatException>().having((e) => e.codigo, 'codigo', 'sin_servidor')));
    });

    test('mensaje vacío: error de programación, sin petición', () async {
      expect(() => servicio().preguntar(mensaje: '   '), throwsArgumentError);
      expect(peticiones, isEmpty);
    });

    test('errores del servidor: usa su mensaje y su código, y Retry-After', () async {
      responder = (_) => ok({'error': {'codigo': 'limite_dia', 'mensaje': 'Hoy ya hizo muchas preguntas. Vuelva mañana.'}},
          estado: 429, h: {'retry-after': '3600'});
      final e = await servicio().preguntar(mensaje: 'x').then<ChatException?>((_) => null, onError: (e) => e as ChatException);
      expect(e!.codigo, 'limite_dia');
      expect(e.mensaje, 'Hoy ya hizo muchas preguntas. Vuelva mañana.');
      expect(e.reintentarEn, const Duration(hours: 1));
    });

    test('error sin el formato esperado: mensaje genérico y código por estado', () async {
      responder = (_) => http.Response('<html>Bad gateway</html>', 502);
      final e = await servicio().preguntar(mensaje: 'x').then<ChatException?>((_) => null, onError: (e) => e as ChatException);
      expect(e!.codigo, 'error_502');
      expect(e.mensaje, isNot(contains('html')));
      expect(e.reintentarEn, isNull);
    });

    test('mensaje de error larguísimo se recorta', () async {
      responder = (_) => ok({'error': {'codigo': 'x', 'mensaje': 'm' * 2000}}, estado: 500);
      final e = await servicio().preguntar(mensaje: 'x').then<ChatException?>((_) => null, onError: (e) => e as ChatException);
      expect(e!.mensaje.length, 300);
    });

    test('respuestas inválidas con 200 se rechazan', () async {
      for (final j in <Object?>[{}, {'respuesta': ''}, {'respuesta': 5}, {'respuesta': 'a' * 7000}, [], 'texto']) {
        responder = (_) => http.Response(jsonEncode(j), 200);
        final e = await servicio().preguntar(mensaje: 'x').then<ChatException?>((_) => null, onError: (e) => e as ChatException);
        expect(e?.codigo, 'respuesta_invalida', reason: '$j');
      }
      responder = (_) => http.Response('no es json', 200);
      await expectLater(servicio().preguntar(mensaje: 'x'), throwsA(isA<ChatException>()));
    });

    test('sin conexión (socket, cliente o tiempo agotado) → sin_conexion', () async {
      for (final falla in <Object>[const SocketException('sin red'), http.ClientException('sin red'), TimeoutException('lento')]) {
        final s = ChatService(cliente: MockClient((r) async => throw falla), urlServidor: 'https://x.example', idInstalacion: () async => _id);
        final e = await s.preguntar(mensaje: 'x').then<ChatException?>((_) => null, onError: (e) => e as ChatException);
        expect(e?.codigo, 'sin_conexion', reason: '$falla');
      }
    });

    test('el tiempo de espera se aplica', () async {
      final s = ChatService(
          cliente: MockClient((r) => Completer<http.Response>().future),
          urlServidor: 'https://x.example', timeout: const Duration(milliseconds: 30), idInstalacion: () async => _id);
      await expectLater(s.preguntar(mensaje: 'x'), throwsA(isA<ChatException>().having((e) => e.codigo, 'codigo', 'sin_conexion')));
    });

    test('el aviso fijo existe', () => expect(avisoGuia, 'Es una guía, no reemplaza al técnico.'));
  });
}
