import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/referencias_curva.dart';
import '../models/volteada.dart';

/// Lo que se puede medir en un registro y vigilar con una regla.
enum VariableMedida {
  temperatura('Temperatura de la masa', '°C'),
  humedad('Humedad', '%'),
  ph('pH', ''),
  brix('°Brix', ''),
  tempAmbiente('Temperatura ambiente', '°C');

  final String nombre;
  final String unidad;
  const VariableMedida(this.nombre, this.unidad);

  /// Valor medido en [v], o null si no se registró (pH, Brix y ambiente son opcionales).
  double? valorDe(Volteada v) => switch (this) {
        temperatura => v.temperatura,
        humedad => v.humedad,
        ph => v.ph,
        brix => v.brix,
        tempAmbiente => v.tempAmbiente,
      };

  static VariableMedida? porNombre(String? n) {
    for (final x in values) {
      if (x.name == n) return x;
    }
    return null;
  }
}

String _n(double v) => (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1)).replaceAll('.', ',');

/// Una regla: "si [variable] sale de [minimo]..[maximo] (en la [etapa], desde la
/// hora [desdeHora] del lote), avisar con [mensaje]". Cada regla lleva su [fuente].
class ReglaAlerta {
  final String id;
  final VariableMedida variable;

  /// Etapa a la que aplica (Etapa.fermentacion / Etapa.secado); null = cualquiera.
  final String? etapa;
  final double? minimo;
  final double? maximo;

  /// La regla solo vale desde esta hora del lote (null = siempre).
  final double? desdeHora;
  final bool activa;
  final String mensaje;
  final String fuente;

  /// true si viene con la app (se puede editar, y "restaurar" la deja como estaba).
  final bool deFabrica;

  const ReglaAlerta({
    required this.id,
    required this.variable,
    this.etapa,
    this.minimo,
    this.maximo,
    this.desdeHora,
    this.activa = true,
    required this.mensaje,
    required this.fuente,
    this.deFabrica = false,
  });

  ReglaAlerta copyWith({
    VariableMedida? variable,
    String? etapa,
    bool quitarEtapa = false,
    double? minimo,
    bool quitarMinimo = false,
    double? maximo,
    bool quitarMaximo = false,
    double? desdeHora,
    bool quitarDesdeHora = false,
    bool? activa,
    String? mensaje,
    String? fuente,
  }) =>
      ReglaAlerta(
        id: id,
        variable: variable ?? this.variable,
        etapa: quitarEtapa ? null : (etapa ?? this.etapa),
        minimo: quitarMinimo ? null : (minimo ?? this.minimo),
        maximo: quitarMaximo ? null : (maximo ?? this.maximo),
        desdeHora: quitarDesdeHora ? null : (desdeHora ?? this.desdeHora),
        activa: activa ?? this.activa,
        mensaje: mensaje ?? this.mensaje,
        fuente: fuente ?? this.fuente,
        deFabrica: deFabrica,
      );

  /// Evalúa el registro [v], tomado a las [horas] del lote. Devuelve la alerta
  /// si el valor sale del rango, o null si no aplica o está dentro.
  AlertaDisparada? evaluar(Volteada v, double horas) {
    if (!activa) return null;
    if (etapa != null && v.etapa != etapa) return null;
    if (desdeHora != null && horas < desdeHora!) return null;
    final valor = variable.valorDe(v);
    if (valor == null) return null;
    final bajo = minimo != null && valor < minimo!;
    final alto = maximo != null && valor > maximo!;
    if (!bajo && !alto) return null;
    return AlertaDisparada(regla: this, valor: valor, bajo: bajo);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'variable': variable.name,
        'etapa': etapa,
        'minimo': minimo,
        'maximo': maximo,
        'desdeHora': desdeHora,
        'activa': activa,
        'mensaje': mensaje,
        'fuente': fuente,
        'deFabrica': deFabrica,
      };

  static ReglaAlerta? fromJson(Object? j) {
    if (j is! Map) return null;
    final variable = VariableMedida.porNombre(j['variable'] as String?);
    final id = j['id'];
    if (variable == null || id is! String || id.isEmpty) return null;
    return ReglaAlerta(
      id: id,
      variable: variable,
      etapa: j['etapa'] as String?,
      minimo: (j['minimo'] as num?)?.toDouble(),
      maximo: (j['maximo'] as num?)?.toDouble(),
      desdeHora: (j['desdeHora'] as num?)?.toDouble(),
      activa: j['activa'] as bool? ?? true,
      mensaje: (j['mensaje'] as String?) ?? '',
      fuente: (j['fuente'] as String?) ?? '',
      deFabrica: j['deFabrica'] as bool? ?? false,
    );
  }
}

/// Una regla que se cumplió con un registro concreto.
class AlertaDisparada {
  final ReglaAlerta regla;
  final double valor;
  final bool bajo;
  const AlertaDisparada({required this.regla, required this.valor, required this.bajo});

  /// Texto corto para la notificación y el aviso en pantalla.
  String get texto {
    final r = regla, u = r.variable.unidad.isEmpty ? '' : ' ${r.variable.unidad}';
    final limite = bajo ? 'por debajo de ${_n(r.minimo!)}$u' : 'por encima de ${_n(r.maximo!)}$u';
    return '${r.variable.nombre}: ${_n(valor)}$u, $limite. ${r.mensaje}'.trim();
  }
}

/// Reglas que trae la app. Los números salen de [ReferenciasCurva] (la única
/// tabla de rangos con fuente): aquí no se escribe ninguno aparte.
///
/// Solo hay dos, porque son las únicas con un límite respaldado por las fuentes:
///  - fermentación, bajo el mínimo (FHIA dice "arriba de 45 ºC a partir del
///    tercer día"; no pone tope, por eso no hay regla de "muy caliente");
///  - secado, sobre el tope (La Salle: "no debe superar los 50ºC").
/// Para cualquier otra variable (pH, Brix, humedad...) no hay fuente verificada:
/// el productor puede agregar su propia regla con la fuente que le dé su técnico.
List<ReglaAlerta> reglasDeFabrica() {
  const ferm = ReferenciasCurva.fermentacionTemperatura;
  const sec = ReferenciasCurva.secadoTemperatura;
  return [
    ReglaAlerta(
      id: 'fab_fermentacion_fria',
      variable: VariableMedida.temperatura,
      etapa: Etapa.fermentacion,
      minimo: ferm.minimo,
      desdeHora: ferm.desdeHora,
      mensaje: 'La masa debería estar caliente. Revise que se esté volteando cada 24 h '
          'y que la masa esté tapada para conservar el calor.',
      fuente: 'FHIA, InfoCacao No. 14 (2017), pp. 3-4: la temperatura debe subir y mantenerse '
          '"arriba de 45 ºC a partir del tercer día"; sin volteo "se enfría la masa"; '
          'tapar la masa con hojas ayuda a mantener el calor.',
      deFabrica: true,
    ),
    ReglaAlerta(
      id: 'fab_secado_caliente',
      variable: VariableMedida.temperatura,
      etapa: Etapa.secado,
      maximo: sec.maximo,
      mensaje: 'Baje el calor del secado: no debe pasar de ${_n(sec.maximo!)} °C.',
      fuente: 'Universidad de La Salle / FEDECACAO (Medina, 2022), p. 7: la temperatura de '
          'secado "no debe superar los 50ºC".',
      deFabrica: true,
    ),
  ];
}

/// Guarda las reglas en el teléfono (funciona sin internet).
class ReglasAlertaStorage {
  static const clave = 'reglas_alerta_v1';

  /// Las reglas guardadas, o las de fábrica si nunca se editaron o el dato está dañado.
  static Future<List<ReglaAlerta>> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(clave);
    if (texto == null) return reglasDeFabrica();
    try {
      final lista = jsonDecode(texto);
      if (lista is! List) return reglasDeFabrica();
      return lista.map(ReglaAlerta.fromJson).whereType<ReglaAlerta>().toList();
    } catch (_) {
      return reglasDeFabrica();
    }
  }

  static Future<void> guardar(List<ReglaAlerta> reglas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(clave, jsonEncode(reglas.map((r) => r.toJson()).toList()));
  }

  /// Vuelve a las reglas de fábrica (borra las propias y las ediciones).
  static Future<void> restaurar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(clave);
  }
}

class EvaluadorAlertas {
  EvaluadorAlertas._();

  /// Todas las alertas que dispara [registro] (tomado a las [horas] del lote).
  static List<AlertaDisparada> evaluar(Volteada registro, double horas, List<ReglaAlerta> reglas) => [
        for (final r in reglas) ?r.evaluar(registro, horas),
      ];
}
