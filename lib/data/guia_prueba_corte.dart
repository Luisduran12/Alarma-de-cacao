/// Contenido de la guía de la prueba de corte.
///
/// Cada paso lleva la fuente de donde sale. Solo se escribe lo que dicen los
/// dos documentos que se leyeron completos (ver docs/fuentes-curva.md y
/// docs/guia-prueba-corte.md). Lo que NO se pudo verificar está en
/// [GuiaPruebaCorte.noVerificado] y NO se muestra como si fuera dato.
enum TipoIlustracion { ninguna, muestreo, corte, conteo, temperatura }

class PasoGuia {
  final int numero;
  final String titulo;
  final String texto;
  final String fuente;
  final TipoIlustracion ilustracion;

  const PasoGuia({
    required this.numero,
    required this.titulo,
    required this.texto,
    required this.fuente,
    this.ilustracion = TipoIlustracion.ninguna,
  });
}

class GuiaPruebaCorte {
  GuiaPruebaCorte._();

  static const fuenteFhia = 'FHIA, InfoCacao No. 14 (2017), p. 4';
  static const fuenteLaSalle = 'Universidad de La Salle / FEDECACAO (Medina, 2022), p. 10';

  static const pasos = <PasoGuia>[
    PasoGuia(
      numero: 1,
      titulo: '¿Cuándo?',
      texto: 'Empiece a partir del cuarto día de fermentación, a la hora de voltear.',
      fuente: '$fuenteFhia: "A partir del cuarto día, al momento de hacer el volteo, se hacen pruebas de corte".',
    ),
    PasoGuia(
      numero: 2,
      titulo: 'Tome la muestra',
      texto: 'Saque un poco de cacao de 9 puntos distintos de la masa. Mézclelo todo y separe 100 granos.',
      fuente: '$fuenteFhia: "unas 9 submuestras de varios puntos de la masa [...] una muestra de cien granos".',
      ilustracion: TipoIlustracion.muestreo,
    ),
    PasoGuia(
      numero: 3,
      titulo: 'Corte cada grano a lo largo',
      texto: 'Corte cada grano a lo largo, de punta a punta, para poder ver el interior.',
      fuente: '$fuenteFhia: "Cada grano se corta longitudinalmente y se observan las características internas".',
      ilustracion: TipoIlustracion.corte,
    ),
    PasoGuia(
      numero: 4,
      titulo: 'Mire por dentro y separe por grupos',
      texto: 'Mire el interior de cada mitad y póngalo en su grupo. Los grupos que se cuentan están más abajo.',
      fuente: '$fuenteLaSalle: se determinan granos "bien fermentados, insuficientemente fermentados, '
          'pizarrosos, mohosos, pasilla, germinados y dañados por insectos".',
    ),
    PasoGuia(
      numero: 5,
      titulo: 'Calcule el porcentaje',
      texto: 'Con 100 granos, cada grano vale 1 %. Por ejemplo: si 70 de los 100 están bien fermentados, '
          'la fermentación es del 70 %.',
      fuente: '$fuenteFhia: "70 a 75 granos están bien fermentados, representa un 70 a 75 % de fermentación".',
      ilustracion: TipoIlustracion.conteo,
    ),
    PasoGuia(
      numero: 6,
      titulo: 'Si aparece un grano pasado',
      texto: 'Si aparece un solo grano sobrefermentado, pare la fermentación para que no suba el '
          'porcentaje de granos sobrefermentados.',
      fuente: '$fuenteFhia: "Si [...] aparece un solo grano sobrefermentado, se debe parar la fermentación".',
    ),
    PasoGuia(
      numero: 7,
      titulo: 'Una señal de que se acaba',
      texto: 'Cuando la fermentación llega a su final, la temperatura del cajón empieza a bajar. '
          'Revise su curva de temperatura.',
      fuente: '$fuenteFhia: "Cuando la fermentación llega a su final, la temperatura del cacao en el cajón empieza a disminuir".',
      ilustracion: TipoIlustracion.temperatura,
    ),
    PasoGuia(
      numero: 8,
      titulo: 'Pregunte al comprador',
      texto: 'Cada comprador pide una calidad distinta. Pregunte cuál quiere antes de decidir cuándo parar.',
      fuente: '$fuenteFhia: "Los estándares de calidad varían entre los compradores".',
    ),
  ];

  /// Los grupos en que se separan los granos (nombres tal como los lista La Salle).
  static const grupos = <String>[
    'Bien fermentados',
    'Insuficientemente fermentados',
    'Pizarrosos',
    'Mohosos',
    'Pasilla',
    'Germinados',
    'Dañados por insectos',
  ];

  static const avisoGrupos = 'Pida a su técnico que le muestre cómo se ve cada grupo por dentro. '
      'Esta guía no describe el aspecto de cada grupo porque no se pudo verificar en una fuente.';

  static const avisoNtc = 'Esta guía sigue el procedimiento de FHIA (2017). La clasificación oficial es la prueba '
      'de corte de la NTC 1252: esta app no incluye el texto de la norma, y su procedimiento exacto '
      '(cuántos granos y qué porcentajes) puede ser distinto. Consulte a su técnico o a FEDECACAO.';

  static const avisoGuia = 'Es una guía, no reemplaza al técnico.';

  /// Lo que se buscó y NO se pudo confirmar (también en docs/guia-prueba-corte.md).
  static const noVerificado = <String>[
    'El texto de la NTC 1252 (es una norma de pago de ICONTEC): tamaño de la muestra y límites por grado.',
    'Cómo se ve por dentro cada grupo (color, textura): las fuentes consultadas no coinciden entre sí.',
    'Porcentajes mínimos de granos bien fermentados o máximos de pizarrosos: solo aparecen en cursos '
        'y resúmenes, no en un documento oficial leído.',
  ];
}
