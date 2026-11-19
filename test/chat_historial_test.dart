import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/mensaje_chat.dart';
import 'package:alarmacacao5_0/services/chat_historial.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ChatHistorial h;
  var reloj = DateTime.utc(2026, 11, 18, 12);

  Future<void> crearLote(String id) => db.insert('lotes', Lote(id: id, title: 'Lote $id', status: 'en proceso', createdAt: reloj).toRow());

  setUp(() async {
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    reloj = DateTime.utc(2026, 11, 18, 12);
    h = ChatHistorial(database: () async => db, ahora: () => reloj = reloj.add(const Duration(minutes: 1)));
    await crearLote('A');
    await crearLote('B');
  });
  tearDown(() => db.close());

  test('la base tiene la tabla del chat (desde la versión 6)', () async {
    expect(CacaoDatabase.version, greaterThanOrEqualTo(6));
    expect(await db.getVersion(), CacaoDatabase.version);
    final t = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='chat_mensajes'");
    expect(t, hasLength(1));
  });

  test('guarda y lista en orden, con rol, origen y fuentes', () async {
    await h.agregar('A', RolChat.usuario, '¿Cuándo volteo?');
    await h.agregar('A', RolChat.asistente, 'Cada 24 horas. [F1]',
        origen: OrigenMensaje.local, fuentes: const [FuenteCitada('vol-01', 'FHIA, InfoCacao No. 14 (2017), p. 4')]);
    final l = await h.listar('A');
    expect(l.map((m) => m.texto), ['¿Cuándo volteo?', 'Cada 24 horas. [F1]']);
    expect(l[0].rol, RolChat.usuario);
    expect(l[1].origen, OrigenMensaje.local);
    expect(l[1].fuentes.single.id, 'vol-01');
    expect(l[1].fuentes.single.fuente, contains('FHIA'));
    expect(l[1].id, isNotNull);
    expect(l[1].creadoEn.isAfter(l[0].creadoEn), isTrue);
  });

  test('cada lote tiene su propia conversación', () async {
    await h.agregar('A', RolChat.usuario, 'de A');
    await h.agregar('B', RolChat.usuario, 'de B');
    expect((await h.listar('A')).single.texto, 'de A');
    expect((await h.listar('B')).single.texto, 'de B');
    expect(await h.listar('C'), isEmpty);
  });

  test('limite devuelve los últimos, aún del más viejo al más nuevo', () async {
    for (var i = 1; i <= 5; i++) {
      await h.agregar('A', RolChat.usuario, 'm$i');
    }
    expect((await h.listar('A', limite: 2)).map((m) => m.texto), ['m4', 'm5']);
  });

  test('paraServidor: máximo 6 turnos, sin avisos de la app, texto recortado a 800', () async {
    for (var i = 1; i <= 5; i++) {
      await h.agregar('A', RolChat.usuario, 'p$i');
      await h.agregar('A', RolChat.asistente, 'r$i');
    }
    await h.agregar('A', RolChat.asistente, 'Sin conexión', origen: OrigenMensaje.sistema);
    await h.agregar('A', RolChat.usuario, 'x' * 900);
    final s = await h.paraServidor('A');
    expect(s, hasLength(6));
    expect(s.every((t) => t.keys.length == 2 && t.containsKey('rol') && t.containsKey('texto')), isTrue);
    expect(s.every((t) => t['rol'] == 'usuario' || t['rol'] == 'asistente'), isTrue);
    expect(s.any((t) => t['texto'] == 'Sin conexión'), isFalse);
    expect(s.last['texto']!.length, 800);
    expect((await h.paraServidor('B')), isEmpty);
  });

  test('borrar quita solo la conversación de ese lote', () async {
    await h.agregar('A', RolChat.usuario, 'a');
    await h.agregar('B', RolChat.usuario, 'b');
    expect(await h.borrar('A'), 1);
    expect(await h.listar('A'), isEmpty);
    expect(await h.listar('B'), hasLength(1));
  });

  test('al borrar el lote se borra su conversación', () async {
    await h.agregar('A', RolChat.usuario, 'a');
    await db.delete('lotes', where: 'id = ?', whereArgs: ['A']);
    expect(await h.listar('A'), isEmpty);
  });

  test('un mensaje con fuentes dañadas o rol desconocido no rompe la lectura', () async {
    await db.insert('chat_mensajes', {
      'lote_id': 'A', 'rol': 'raro', 'texto': 'hola', 'origen': 'otro', 'fuentes': '{no es json', 'creado_en': 'no es fecha',
    });
    final m = (await h.listar('A')).single;
    expect(m.texto, 'hola');
    expect(m.fuentes, isEmpty);
    expect(m.rol, RolChat.asistente);
    expect(m.origen, OrigenMensaje.sistema);
  });

  test('migración desde la versión 5: conserva lotes y crea la tabla del chat', () async {
    final dir = await Directory.systemTemp.createTemp('cacao_v5');
    addTearDown(() => dir.delete(recursive: true));
    final ruta = p.join(dir.path, 'v5.db');
    final vieja = await databaseFactoryFfi.openDatabase(ruta,
        options: OpenDatabaseOptions(version: 5, onCreate: (d, _) async {
          await CacaoDatabase.crearTablas(d);
          await d.execute('DROP TABLE chat_mensajes');
          await d.execute('DROP TABLE analisis_fotos');
          await d.insert('lotes', Lote(id: 'V', title: 'Viejo', status: 'en proceso', createdAt: DateTime(2026)).toRow());
        }));
    expect(await vieja.getVersion(), 5);
    await vieja.close();
    final nueva = await CacaoDatabase.abrir(databaseFactoryFfi, ruta);
    expect(await nueva.getVersion(), CacaoDatabase.version);
    expect((await nueva.query('lotes')).single['titulo'], 'Viejo');
    await ChatHistorial(database: () async => nueva).agregar('V', RolChat.usuario, 'hola');
    expect(await nueva.query('chat_mensajes'), hasLength(1));
    await nueva.close();
  });
}
