import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/archivos_respaldo.dart';
import '../services/borrar_datos.dart';
import '../services/consentimiento_fotos.dart';
import '../services/consentimiento_ubicacion.dart';
import '../services/consentimiento_voz.dart';
import '../services/copia_seguridad.dart';
import '../services/preferencias_app.dart';
import 'ayuda_screen.dart';
import 'creditos_screen.dart';
import 'permisos_screen.dart';
import 'politica_screen.dart';

/// Ajustes: letra y colores, batería, autorizaciones (Ley 1581), copia de seguridad, borrar datos y ayuda.
class AjustesScreen extends StatefulWidget {
  /// Se pueden cambiar en pruebas.
  final PreferenciasApp? preferencias;
  final CopiaSeguridad? copia;
  final BorrarDatos? borrar;
  final ArchivosRespaldo? archivos;

  /// Pantalla a la que se vuelve después de borrar todo (por defecto, la de permisos, que vuelve a pedir autorización).
  final WidgetBuilder? trasBorrar;

  const AjustesScreen({super.key, this.preferencias, this.copia, this.borrar, this.archivos, this.trasBorrar});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  late final PreferenciasApp _prefs = widget.preferencias ?? PreferenciasApp.instancia;
  late final CopiaSeguridad _copia = widget.copia ?? CopiaSeguridad();
  late final BorrarDatos _borrar = widget.borrar ?? BorrarDatos();
  late final ArchivosRespaldo _archivos = widget.archivos ?? const ArchivosRespaldo();

  bool? _ubicacion, _fotos, _voz;
  bool _cargado = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_redibujar);
    _leerAutorizaciones();
  }

  @override
  void dispose() {
    _prefs.removeListener(_redibujar);
    super.dispose();
  }

  void _redibujar() {
    if (mounted) setState(() {});
  }

  Future<void> _leerAutorizaciones() async {
    final u = await ConsentimientoUbicacion.obtener();
    final f = await ConsentimientoFotos.obtener();
    final v = await ConsentimientoVoz.obtener();
    if (!mounted) return;
    setState(() {
      _ubicacion = u;
      _fotos = f;
      _voz = v;
      _cargado = true;
    });
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<bool> _confirmar(String titulo, String texto, String boton, {bool peligro = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(child: Text(texto)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: peligro ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(boton),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  // --- respaldo ---------------------------------------------------------------------------------------------------

  Future<void> _guardarCopia() async {
    setState(() => _ocupado = true);
    try {
      await _archivos.compartir(_copia.nombreArchivo(), await _copia.exportar());
    } catch (e) {
      _aviso('No se pudo preparar la copia de seguridad.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _recuperarCopia() async {
    setState(() => _ocupado = true);
    try {
      final contenido = await _archivos.elegir();
      if (contenido == null) return;
      final r = await _copia.validar(contenido);
      if (!mounted) return;
      setState(() => _ocupado = false); // sin el círculo de espera detrás de la pregunta
      final f = r.creadoEn.toLocal();
      final fecha = '${f.day}/${f.month}/${f.year}';
      final ok = await _confirmar(
        '¿Recuperar esta copia?',
        'La copia es del $fecha y tiene ${r.lotes} lotes, ${r.registros} registros y ${r.mensajesChat} mensajes del chat.\n\n'
            'Se REEMPLAZARÁ lo que hay ahora en este teléfono. Las fotos no viajan en la copia. Las alarmas de los registros '
            'que aún no pasan se vuelven a programar.',
        'Sí, recuperar',
        peligro: true,
      );
      if (!ok || !mounted) return;
      setState(() => _ocupado = true);
      await _copia.importar(contenido);
      _aviso('Copia recuperada: ${r.lotes} lotes y ${r.registros} registros.');
    } on RespaldoInvalido catch (e) {
      _aviso('${e.mensaje} No se cambió nada.');
    } catch (e) {
      _aviso('No se pudo recuperar la copia. No se cambió nada.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _borrarTodo() async {
    final ok = await _confirmar(
      '¿Borrar TODOS sus datos?',
      'Se borran de este teléfono: todos los lotes y registros, las fotos, el historial del chat, las alarmas y sus '
          'ajustes. No se puede deshacer.\n\nSi quiere conservarlos, primero guarde una copia de seguridad.\n\n'
          'Lo que Anthropic haya recibido del chat o de las fotos puede conservarlo hasta 30 días y no se puede borrar desde aquí.',
      'Sí, borrar todo',
      peligro: true,
    );
    if (!ok || !mounted) return;
    setState(() => _ocupado = true);
    final r = await _borrar.todo();
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (!r.completo) {
      _aviso('No se pudo borrar todo (${r.fallos.join(', ')}). Intente de nuevo.');
      return;
    }
    // Se vuelve al inicio: la app vuelve a pedir autorización para la ubicación, como la primera vez.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: widget.trasBorrar ?? (_) => const PermisosScreen()),
      (_) => false,
    );
  }

  // --- piezas -----------------------------------------------------------------------------------------------------

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Semantics(header: true, child: Text(t, style: Theme.of(context).textTheme.titleMedium)),
      );

  Widget _interruptor(String titulo, String detalle, bool? valor, Future<void> Function(bool) alCambiar) {
    return SwitchListTile(
      title: Text(titulo),
      subtitle: Text(detalle),
      isThreeLine: true,
      value: valor == true,
      onChanged: _cargado ? alCambiar : null,
    );
  }

  Future<void> _cambiarUbicacion(bool v) async {
    await ConsentimientoUbicacion.registrar(v);
    setState(() => _ubicacion = v);
  }

  Future<void> _cambiarFotos(bool v) async {
    await ConsentimientoFotos.registrar(v);
    setState(() => _fotos = v);
  }

  Future<void> _cambiarVoz(bool v) async {
    await ConsentimientoVoz.registrar(v);
    setState(() => _voz = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: Stack(
        children: [
          ListView(
            children: [
              _titulo('Letra y colores'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tamaño de la letra'),
                    const SizedBox(height: 8),
                    SegmentedButton<TamanoLetra>(
                      showSelectedIcon: false,
                      segments: [for (final t in TamanoLetra.values) ButtonSegment(value: t, label: Text(t.nombre))],
                      selected: {_prefs.tamano},
                      onSelectionChanged: (s) => _prefs.cambiarTamano(s.first),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Alto contraste'),
                subtitle: const Text('Colores más fuertes para leer mejor con el sol.'),
                value: _prefs.altoContraste,
                onChanged: _prefs.cambiarAltoContraste,
              ),
              _titulo('Batería'),
              SwitchListTile(
                title: const Text('Ahorro de batería'),
                subtitle: const Text('Quita el video de fondo y no busca nombres de lugar ni reintenta fotos por su cuenta. '
                    'Las alarmas siguen sonando.'),
                isThreeLine: true,
                value: _prefs.ahorroBateria,
                onChanged: _prefs.cambiarAhorroBateria,
              ),
              _titulo('Sus autorizaciones'),
              _interruptor('Usar mi ubicación', 'Para el punto de secado y el clima. Solo cuando usted toca el botón.',
                  _ubicacion, _cambiarUbicacion),
              _interruptor('Enviar fotos para analizar', 'La foto va reducida y sin datos ocultos a un servidor y a Anthropic.',
                  _fotos, _cambiarFotos),
              _interruptor('Dictar con la voz', 'Lo escucha el servicio de voz de su teléfono. Esta app no guarda el audio.',
                  _voz, _cambiarVoz),
              _titulo('Sus datos'),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Guardar copia de seguridad'),
                subtitle: const Text('Un archivo con sus lotes y registros, para guardarlo o enviarlo.'),
                onTap: _ocupado ? null : _guardarCopia,
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Recuperar copia de seguridad'),
                subtitle: const Text('Reemplaza lo que hay en este teléfono por el contenido del archivo.'),
                onTap: _ocupado ? null : _recuperarCopia,
              ),
              ListTile(
                leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                title: Text('Borrar todos mis datos', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                subtitle: const Text('Quita de este teléfono todo lo que la app guardó.'),
                onTap: _ocupado ? null : _borrarTodo,
              ),
              _titulo('Ayuda e información'),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('Glosario y guía rápida'),
                subtitle: const Text('Funciona sin internet.'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AyudaScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Política de privacidad'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PoliticaScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: const Text('Créditos y licencias'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreditosScreen())),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${AppInfo.nombre} · versión ${AppInfo.version}', style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
          if (_ocupado) const ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
