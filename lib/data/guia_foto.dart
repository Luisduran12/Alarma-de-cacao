import 'package:flutter/material.dart';

import '../models/analisis_foto.dart';

class PasoFoto {
  final IconData icono;
  final String titulo;
  final String texto;
  const PasoFoto(this.icono, this.titulo, this.texto);
}

class GuiaFoto {
  final String titulo;
  final List<PasoFoto> pasos;
  const GuiaFoto(this.titulo, this.pasos);

  /// Dice de dónde sale esto, siempre visible: son consejos de la app para que la IA vea bien la foto,
  /// no una norma ni un procedimiento oficial (salvo el corte a lo largo, que es de FHIA).
  static const nota = 'Estos consejos son de esta app, para que la IA vea bien la foto. No son una norma.';

  static const noPersonas = PasoFoto(Icons.no_photography_outlined, 'Solo cacao', 'No fotografíe personas ni documentos.');

  static GuiaFoto para(ModoAnalisis modo) => switch (modo) {
        ModoAnalisis.corte => const GuiaFoto('Cómo fotografiar la prueba de corte', [
            PasoFoto(Icons.content_cut, 'Corte los granos a lo largo',
                'Corte cada grano a lo largo, de punta a punta, para que se vea el interior (así lo indica FHIA, InfoCacao No. 14, 2017).'),
            PasoFoto(Icons.view_week_outlined, 'Ponga las mitades en fila',
                'Ponga las mitades con el corte hacia arriba, una al lado de la otra y sin que se toquen.'),
            PasoFoto(Icons.crop_square, 'Fondo liso y claro', 'Use una hoja blanca o un paño liso, sin dibujos.'),
            PasoFoto(Icons.wb_sunny_outlined, 'Luz natural, sin sombras',
                'Tome la foto con luz del día, a la sombra o con el cielo nublado. Evite que su sombra tape los granos.'),
            PasoFoto(Icons.center_focus_strong_outlined, 'De cerca y quieta',
                'Acérquese hasta que los granos llenen casi toda la foto y espere a que el teléfono enfoque.'),
            noPersonas,
          ]),
        ModoAnalisis.granoSeco => const GuiaFoto('Cómo fotografiar el grano seco', [
            PasoFoto(Icons.grain, 'Una sola capa', 'Extienda varios granos en una sola capa, sin que queden montones.'),
            PasoFoto(Icons.crop_square, 'Fondo liso y claro', 'Use una hoja blanca o un paño liso.'),
            PasoFoto(Icons.wb_sunny_outlined, 'Luz natural, sin sombras', 'Luz del día, sin sombras sobre los granos.'),
            PasoFoto(Icons.center_focus_strong_outlined, 'De cerca y quieta',
                'Acérquese para que se vea la superficie de los granos y espere a que el teléfono enfoque.'),
            PasoFoto(Icons.add_a_photo_outlined, 'Si ve algo raro, otra foto',
                'Si hay un grano con polvo, manchas u hoyitos, tome una foto aparte bien de cerca.'),
            noPersonas,
          ]),
        ModoAnalisis.mazorcaHoja => const GuiaFoto('Cómo fotografiar una mazorca o una hoja', [
            PasoFoto(Icons.eco_outlined, 'Una sola mazorca u hoja', 'Ponga en el centro la mazorca (o la hoja) que le preocupa.'),
            PasoFoto(Icons.crop_free, 'Que se vea entera', 'Tome una foto donde se vea toda la mazorca, con su forma y color.'),
            PasoFoto(Icons.zoom_in, 'Y otra de la mancha', 'Si tiene manchas o polvo, tome otra foto bien de cerca de esa parte.'),
            PasoFoto(Icons.wb_sunny_outlined, 'Luz natural, sin contraluz',
                'Evite tomarla con el sol de frente o detrás de la mazorca.'),
            PasoFoto(Icons.center_focus_strong_outlined, 'Quieta y enfocada', 'Sostenga el teléfono quieto hasta que enfoque.'),
            noPersonas,
          ]),
      };
}
