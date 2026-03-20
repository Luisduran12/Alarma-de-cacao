import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegistroFormularioDialog extends StatefulWidget {
  const RegistroFormularioDialog({super.key});

  @override
  State<RegistroFormularioDialog> createState() => _RegistroFormularioDialogState();
}

class _RegistroFormularioDialogState extends State<RegistroFormularioDialog> {
  final TextEditingController _titleController = TextEditingController();
  final List<TextEditingController> _hourControllers =
      List.generate(5, (_) => TextEditingController());

  @override
  void dispose() {
    _titleController.dispose();
    for (var controller in _hourControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configurar Nuevo Lote de Volteadas'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Título del Lote',
                hintText: 'Ej: Lote Mañana, Lote Especial',
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ingrese hasta 5 horas para las volteadas (deje en blanco o escriba 0 para ignorar):',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...List.generate(5, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  controller: _hourControllers[index],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Volteada ${index + 1} (horas)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancelar'),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
          ),
          child: const Text('Iniciar Simulación'),
          onPressed: () {
            List<int> parsedHours = [];
            bool hasError = false;

            for (var controller in _hourControllers) {
              final text = controller.text.trim();
              if (text.isEmpty) {
                parsedHours.add(0);
              } else {
                final value = int.tryParse(text);
                if (value == null || value < 0) {
                  hasError = true;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '⚠️ Ingresa solo números enteros positivos o deja vacío.',
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  break;
                }
                parsedHours.add(value);
              }
            }

            if (hasError) return;

            Navigator.of(context).pop({
              'title': _titleController.text.trim(),
              'hours': parsedHours,
            });
          },
        ),
      ],
    );
  }
}
