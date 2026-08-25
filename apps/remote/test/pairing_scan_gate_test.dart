import 'package:cinelark_remote/screens/pairing_scan_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reset accepts the same pairing code after a failed attempt', () {
    final gate = PairingScanGate();

    expect(gate.tryBeginCapture(), isTrue);
    expect(gate.tryBeginCapture(), isFalse);

    gate.reset();

    expect(gate.tryBeginCapture(), isTrue);
  });
}
