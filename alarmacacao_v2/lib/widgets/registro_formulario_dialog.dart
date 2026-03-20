// lib/widgets/registro_formulario_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para FilteringTextInputFormatter

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
            const Text('Ingrese 5 valores de horas para las volteadas (0 para ignorar):'),
            ...List.generate(5, (index) => TextField(
              controller: _hourControllers[index],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly], // Solo permite dígitos
              decoration: InputDecoration(
                labelText: 'Volteada ${index + 1} (horas)',
              ),
            )),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancelar'),
          onPressed: () {
            Navigator.of(context).pop(null); // Retorna null si se cancela
          },
        ),
        ElevatedButton(
          child: const Text('Iniciar Simulación'),
          onPressed: () {
            List<int> parsedHours = [];
            bool hasError = false;
            for (var controller in _hourControllers) {
              final text = controller.text;
              if (text.isEmpty) {
                parsedHours.add(0); // Si está vacío, se considera 0 (ignorar)
              } else {
                final value = int.tryParse(text);
                if (value == null || value < 0) {
                  hasError = true;
                  ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Por favor, ingrese solo números enteros positivos para las horas.')),
                  );
                  break; // Sale del bucle si hay error
                }
                parsedHours.add(value);
              }
            }

            if (hasError) return; // Si hubo un error, no cierra el diálogo

            // Retorna un mapa con el título y las horas
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