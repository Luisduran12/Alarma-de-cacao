import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alarmacacao5_0/services/instalacion_id.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('la primera vez crea un UUID v4 válido y lo guarda', () async {
    final id = await InstalacionId.obtener();
    expect(InstalacionId.esValido(id), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InstalacionId.clave), id);
  });

  test('las siguientes veces devuelve el mismo', () async {
    final a = await InstalacionId.obtener();
    final b = await InstalacionId.obtener();
    expect(b, a);
  });

  test('instalaciones distintas tienen IDs distintos', () async {
    final a = await InstalacionId.obtener();
    SharedPreferences.setMockInitialValues({});
    final b = await InstalacionId.obtener();
    expect(b, isNot(a));
  });

  test('un valor guardado dañado se reemplaza por uno válido', () async {
    SharedPreferences.setMockInitialValues({InstalacionId.clave: 'esto-no-es-un-uuid'});
    final id = await InstalacionId.obtener();
    expect(InstalacionId.esValido(id), isTrue);
    expect(id, isNot('esto-no-es-un-uuid'));
  });

  test('esValido solo acepta UUID v4', () {
    expect(InstalacionId.esValido('3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c'), isTrue);
    for (final malo in [null, '', 'hola', '3f2b8c1e-9d4a-1b7e-8a1c-0e5d6f7a8b9c', '3f2b8c1e9d4a4b7e8a1c0e5d6f7a8b9c']) {
      expect(InstalacionId.esValido(malo), isFalse, reason: '$malo');
    }
  });

  test('no lleva nada del productor: solo el UUID', () async {
    final id = await InstalacionId.obtener();
    expect(id.length, 36);
    expect(RegExp(r'^[0-9a-f-]+$').hasMatch(id), isTrue);
  });
}
