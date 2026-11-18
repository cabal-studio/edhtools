// La prueba de ejemplo de `flutter create` (contador) no aplica a esta app.
// Las pruebas reales están en swiss_test.dart. Aquí solo se verifica la
// configuración de puntos, que no requiere Firebase.
import 'package:edhtools/logic/swiss.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('puntos por defecto', () {
    const p = Points();
    expect(p.forResult('W'), 5);
    expect(p.forResult('D'), 1);
    expect(p.forResult('L'), 0);
    expect(p.usesPlacement, false);
  });
}
