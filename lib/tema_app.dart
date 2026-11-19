import 'package:flutter/material.dart';

import 'services/preferencias_app.dart';

/// Tema de la app. Con "alto contraste" los colores del esquema se calculan con el nivel máximo de contraste
/// de Material 3, y el texto sale en negrita media. Todos los botones miden al menos 48 dp de alto.
class TemaApp {
  TemaApp._();

  static ThemeData construir({bool altoContraste = false}) {
    final esquema = ColorScheme.fromSeed(
      seedColor: Colors.brown,
      contrastLevel: altoContraste ? 1.0 : 0.0,
    );
    const minimo = Size(64, 48);
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: minimo)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(minimumSize: minimo)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: minimo)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: minimo)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    );
  }

  /// Aplica el tamaño de letra elegido encima del que ya tenga el teléfono en sus ajustes.
  static Widget conPreferencias(BuildContext context, Widget? hijo, PreferenciasApp p) {
    final mq = MediaQuery.of(context);
    final sistema = mq.textScaler.scale(100) / 100;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(sistema * p.tamano.factor)),
      child: hijo ?? const SizedBox.shrink(),
    );
  }

  /// Relación de contraste WCAG 2.1 entre dos colores (de 1 a 21). AA pide 4,5 para texto normal y 3 para texto
  /// grande y componentes gráficos.
  static double contraste(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final claro = la > lb ? la : lb, oscuro = la > lb ? lb : la;
    return (claro + 0.05) / (oscuro + 0.05);
  }
}
