import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/shared/ui.dart';

void main() {
  test('fmtSeconds formats HH:MM:SS', () {
    expect(fmtSeconds(3725), '01:02:05');
    expect(fmtSeconds(-5), '00:00:00');
  });

  test('fmtHm formats hours and minutes', () {
    expect(fmtHm(5400), '1h 30m');
  });

  test('cleanPayload keeps nullable, blanks text, drops the rest', () {
    final out = cleanPayload(
      {'a': null, 'b': null, 'c': null, 'd': 1},
      nullable: {'a'},
      text: {'b'},
    );
    expect(out, {'a': null, 'b': '', 'd': 1});
  });
}
