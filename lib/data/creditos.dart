/// Créditos y licencias de lo que la app usa de terceros. Repite lo de `docs/creditos.md` (una prueba comprueba
/// que los nombres clave sigan en los dos). Si cambia una licencia o una fuente, cambie los dos.
class Credito {
  final String titulo;
  final String texto;
  final String? enlace;
  const Credito(this.titulo, this.texto, {this.enlace});
}

class Creditos {
  Creditos._();

  static const aviso = 'Gracias a quienes publicaron estos datos y documentos para que cualquiera los use.';

  static const items = <Credito>[
    Credito(
      'Clima: Open-Meteo',
      'Weather data by Open-Meteo.com. Datos con licencia CC BY 4.0. La app envía la ubicación redondeada a unos 1.000 m. '
          'El uso gratuito de Open-Meteo es solo para apps sin cobro ni publicidad.',
      enlace: 'https://open-meteo.com/',
    ),
    Credito(
      'Municipios y centros poblados: DANE',
      'DIVIPOLA del Departamento Administrativo Nacional de Estadística (DANE), publicada en datos.gov.co (corte 30 de '
          'diciembre de 2024). Licencia CC BY-SA 4.0. Cambios: se unieron dos conjuntos, se cambiaron las mayúsculas, se '
          'quitaron filas repetidas y se guardó en formato compacto. La app dice "Cerca de..." porque no hay una lista '
          'oficial de veredas con coordenadas.',
      enlace: 'https://www.datos.gov.co/d/gdxc-w37w',
    ),
    Credito(
      'Nombre del lugar: OpenStreetMap',
      'Cuando hay internet, el nombre del lugar viene de OpenStreetMap (Nominatim). © colaboradores de OpenStreetMap, '
          'licencia ODbL.',
      enlace: 'https://www.openstreetmap.org/copyright',
    ),
    Credito(
      'Guía y respuestas: FHIA',
      'FHIA, InfoCacao No. 14 (2017): "Actividades de poscosecha para lograr cacao de calidad". Proyecto PROCACAHO, '
          'Honduras. Confirme con su técnico o asociación en Colombia.',
      enlace: 'https://fhia.org.hn/wp-content/uploads/InfoCacao_No14_Sept_2017.pdf',
    ),
    Credito(
      'Guía y respuestas: Universidad de La Salle y FEDECACAO',
      'Medina et al. (2022), "Cacao antioqueño: la sinfonía microbiana, química y sensorial". Universidad de Antioquia y '
          'Unilasallista, con FEDECACAO.',
      enlace: 'https://repository.unilasallista.edu.co/bitstreams/e9c09d20-867b-40ff-a4cf-cb68fbdbb3d1/download',
    ),
    Credito(
      'Guía y respuestas: ICA',
      'Instituto Colombiano Agropecuario (ICA), con Fedecacao (2012): "Manejo fitosanitario del cultivo del cacao". '
          'Solo se usan los síntomas y el manejo cultural, nunca productos ni dosis.',
      enlace: 'https://www.ica.gov.co/getattachment/c01fa43b-cf48-497a-aa7f-51e6da3f7e96/-',
    ),
    Credito(
      'Fotos de referencia: granos cortados (Zenodo)',
      'Oliveira, M. M.; Cerqueira, B. V.; Barbon Jr., S.; Barbin, D. F. "Images of fermented cocoa beans from cut-test '
          'experiments for computer vision classification". Zenodo. Licencia CC BY 4.0 según Zenodo; falta que los autores '
          'confirmen la licencia final. Son fotos de Brasil, en laboratorio. Se usan para evaluar el análisis de fotos; '
          'cambios: recorte, reducción a 640 px y sin datos ocultos.',
      enlace: 'https://doi.org/10.5281/zenodo.22824982',
    ),
    Credito(
      'Fotos de referencia: mazorcas con moniliasis (Zenodo)',
      'Alvarado Molina, J. F.; Restrepo-Arias, J. F.; Velásquez, D.; Branch Bedoya, J. W.; Maiza, M. "CocoaMoniliaDataSet" '
          '(2025). Zenodo. Licencia CC BY 4.0. Fotos con celular en fincas de Santander y Antioquia. Cambios: reducción a '
          '768 px y sin datos ocultos.',
      enlace: 'https://doi.org/10.5281/zenodo.17716661',
    ),
    Credito(
      'Inteligencia artificial: Anthropic',
      'El chat y el análisis de fotos usan modelos de Anthropic a través de nuestro servidor. Anthropic puede conservar lo '
          'que recibe hasta 30 días.',
    ),
  ];
}
