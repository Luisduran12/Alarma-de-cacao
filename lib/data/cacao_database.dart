import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migracion_prefs.dart';

/// Base de datos local (SQLite) de Cacao Light: única fuente de datos.
///
/// Tablas:
///  - lotes:     un lote de cacao en beneficio.
///  - recordatorios: avisos de medir la temperatura (no son registros).
///  - lugares:   caché de nombres de lugar resueltos por el servidor.
///  - chat_mensajes: historial de la conversación de cada lote (solo en el teléfono).
///  - registros: volteadas programadas y datos medidos (fecha, temperatura,
///               humedad, observación, latitud, longitud, etapa y, opcionales,
///               pH, Brix y temperatura ambiente).
class CacaoDatabase {
  static const String nombreArchivo = 'cacao_light.db';
  /// v1: tablas lotes y registros.
  /// v2: resultado del grano en lotes (calidad_resultado, observacion_resultado).
  /// v3: pH, Brix y temperatura ambiente opcionales en registros.
  /// v4: tabla recordatorios (avisos de medir la temperatura cada 12 h).
  /// v5: tabla lugares (nombres de lugar resueltos por el servidor, como caché).
  /// v6: tabla chat_mensajes (historial del chat por lote).
  static const int version = 6;

  static Future<Database>? _instancia;

  /// Base de datos de la app (se abre una sola vez). La primera vez migra los
  /// datos que estaban en SharedPreferences.
  static Future<Database> instancia() => _instancia ??= _abrirApp();

  static Future<Database> _abrirApp() async {
    final dir = await getDatabasesPath();
    final db = await abrir(databaseFactory, p.join(dir, nombreArchivo));
    await MigracionPrefs.migrarSiHaceFalta(db);
    return db;
  }

  /// Abre (o crea) una base de datos en [ruta]. Se usa también en pruebas
  /// con `databaseFactoryFfi` e `inMemoryDatabasePath`.
  static Future<Database> abrir(DatabaseFactory factory, String ruta) {
    return factory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => crearTablas(db),
        onUpgrade: (db, anterior, _) async {
          if (anterior < 2) await _agregarResultado(db);
          if (anterior < 3) await _agregarMedidasOpcionales(db);
          if (anterior < 4) await _crearRecordatorios(db);
          if (anterior < 5) await _crearLugares(db);
          if (anterior < 6) await _crearChatMensajes(db);
        },
      ),
    );
  }

  static Future<void> crearTablas(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE lotes (
        id            TEXT PRIMARY KEY,
        titulo        TEXT NOT NULL,
        estado        TEXT NOT NULL,
        creado_en     TEXT NOT NULL,
        inicio_ciclo  TEXT,
        fin_ciclo     TEXT,
        plantilla     TEXT,
        calidad_resultado      TEXT,
        observacion_resultado  TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE registros (
        id                TEXT PRIMARY KEY,
        lote_id           TEXT NOT NULL REFERENCES lotes(id) ON DELETE CASCADE,
        mensaje           TEXT NOT NULL DEFAULT '',
        fecha_programada  TEXT NOT NULL,
        fecha             TEXT NOT NULL,
        temperatura       REAL,
        humedad           REAL,
        observacion       TEXT NOT NULL DEFAULT '',
        latitud           REAL,
        longitud          REAL,
        etapa             TEXT NOT NULL DEFAULT 'fermentacion',
        confirmada        INTEGER NOT NULL DEFAULT 0,
        notif_id          INTEGER NOT NULL DEFAULT 0,
        ph                REAL,
        brix              REAL,
        temp_ambiente     REAL
      )
    ''');
    await db.execute('CREATE INDEX idx_registros_lote ON registros(lote_id)');
    await _crearRecordatorios(db);
    await _crearLugares(db);
    await _crearChatMensajes(db);
  }

  /// Historial del chat: una conversación por lote, que se borra junto con el lote.
  /// `fuentes` es un JSON con las fuentes citadas en esa respuesta.
  static Future<void> _crearChatMensajes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE chat_mensajes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        lote_id    TEXT NOT NULL REFERENCES lotes(id) ON DELETE CASCADE,
        rol        TEXT NOT NULL,
        texto      TEXT NOT NULL,
        origen     TEXT NOT NULL DEFAULT 'ia',
        fuentes    TEXT NOT NULL DEFAULT '[]',
        creado_en  TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_chat_lote ON chat_mensajes(lote_id)');
  }

  /// Caché de nombres de lugar: la clave son las coordenadas redondeadas a 3
  /// decimales (≈ 110 m). Solo guarda lo que respondió el servidor; el nombre de
  /// la lista offline se calcula al momento y no se guarda.
  static Future<void> _crearLugares(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE lugares (
        clave        TEXT PRIMARY KEY,
        nombre       TEXT NOT NULL,
        origen       TEXT NOT NULL,
        fuente       TEXT NOT NULL DEFAULT '',
        resuelto_en  TEXT NOT NULL
      )
    ''');
  }

  /// Avisos programados que NO son registros del lote (por ejemplo, "medir la
  /// temperatura"): así no cuentan como volteadas pendientes ni impiden que el
  /// lote se marque como completado.
  static Future<void> _crearRecordatorios(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE recordatorios (
        id                TEXT PRIMARY KEY,
        lote_id           TEXT NOT NULL REFERENCES lotes(id) ON DELETE CASCADE,
        notif_id          INTEGER NOT NULL,
        fecha_programada  TEXT NOT NULL,
        tipo              TEXT NOT NULL DEFAULT 'medir_temperatura'
      )
    ''');
    await db.execute('CREATE INDEX idx_recordatorios_lote ON recordatorios(lote_id)');
  }

  /// Solo agrega columnas nulas: los registros existentes no se tocan.
  static Future<void> _agregarMedidasOpcionales(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE registros ADD COLUMN ph REAL');
    await db.execute('ALTER TABLE registros ADD COLUMN brix REAL');
    await db.execute('ALTER TABLE registros ADD COLUMN temp_ambiente REAL');
  }

  static Future<void> _agregarResultado(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE lotes ADD COLUMN calidad_resultado TEXT');
    await db.execute('ALTER TABLE lotes ADD COLUMN observacion_resultado TEXT');
  }
}
