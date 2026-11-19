import 'package:speech_to_text/speech_to_text.dart';

/// El motor de dictado visto desde la app. Se puede cambiar en pruebas (el real necesita un teléfono).
abstract class MotorDictado {
  /// Pide el permiso del micrófono y prepara el reconocimiento. false si el teléfono no lo tiene o no se dio permiso.
  Future<bool> preparar({required void Function(String error) alError});

  /// Empieza a escuchar. [alTexto] recibe lo reconocido hasta ahora (se va completando) y si ya es el final.
  Future<void> escuchar({required void Function(String texto, bool esFinal) alTexto});

  Future<void> detener();
}

class MotorDictadoReal implements MotorDictado {
  final SpeechToText _stt = SpeechToText();
  String? _idioma;
  bool _listo = false;

  @override
  Future<bool> preparar({required void Function(String error) alError}) async {
    if (_listo) return true;
    try {
      _listo = await _stt.initialize(onError: (e) => alError(e.errorMsg));
      if (!_listo) return false;
      // Español de Colombia si el teléfono lo tiene; si no, cualquier español; si no, el idioma del teléfono.
      final idiomas = await _stt.locales();
      String? elegir(bool Function(String) cumple) {
        for (final l in idiomas) {
          if (cumple(l.localeId.replaceAll('-', '_').toLowerCase())) return l.localeId;
        }
        return null;
      }

      _idioma = elegir((i) => i == 'es_co') ?? elegir((i) => i.startsWith('es'));
      return true;
    } catch (_) {
      _listo = false;
      return false;
    }
  }

  @override
  Future<void> escuchar({required void Function(String texto, bool esFinal) alTexto}) async {
    await _stt.listen(
      onResult: (r) => alTexto(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        localeId: _idioma,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Future<void> detener() => _stt.stop();
}
